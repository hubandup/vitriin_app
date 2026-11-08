-- MOD-072 : validation en caisse par code vendeur.
-- Chaque magasin a un code à 4 chiffres. Le client montre sa promo, le vendeur tape ce code sur le
-- téléphone du client : l'utilisation est alors confirmée (used_at), ce qui remplace la confirmation
-- déclarative du client (vitrine_confirm_use, supprimée ici).
-- Le code n'est lisible que par les membres du magasin ; le client n'y a jamais accès.
-- MOD-073 (même migration) : un lien vers une promo terminée renvoie son magasin (section 5).

-- 1. Le code de chaque magasin
create table if not exists public.store_pins (
  store_id uuid primary key references public.stores(id) on delete cascade,
  pin text not null check (pin ~ '^[0-9]{4}$'),
  updated_at timestamptz not null default now()
);
alter table public.store_pins enable row level security;
revoke all on public.store_pins from anon, authenticated;
grant select on public.store_pins to authenticated;
drop policy if exists store_pins_select_members on public.store_pins;
create policy store_pins_select_members on public.store_pins
  for select to authenticated using (public.is_store_member(store_id));

-- Tirage aléatoire (gen_random_uuid = générateur cryptographique), sans les codes trop évidents,
-- et sans reprendre le code d'un autre magasin du même réseau (le code désigne le magasin qui valide).
create or replace function public.new_store_pin(p_network_id uuid default null, p_store_id uuid default null) returns text
language plpgsql volatile set search_path to '' as $$
declare b bytea; n int; v text; tries int := 0;
begin
  loop
    b := decode(replace(gen_random_uuid()::text, '-', ''), 'hex');
    n := get_byte(b, 0) * 256 + get_byte(b, 1);
    continue when n >= 60000; -- évite le biais du modulo
    v := lpad((n % 10000)::text, 4, '0');
    continue when v ~ '^(.)\1{3}$' or v in ('1234', '4321', '0123', '3210', '6789', '9876', '2580', '1212');
    tries := tries + 1;
    exit when p_network_id is null or tries > 500 or not exists (
      select 1 from public.store_pins k join public.stores s on s.id = k.store_id
      where s.network_id = p_network_id and k.pin = v and k.store_id is distinct from p_store_id);
  end loop;
  return v;
end;
$$;

-- Un code dès la création du magasin. Quand un magasin rejoint un réseau, il change de code
-- seulement si le sien y est déjà pris.
create or replace function public.stores_add_pin() returns trigger
language plpgsql security definer set search_path to '' as $$
begin
  if tg_op = 'UPDATE' then
    if new.network_id is null or new.network_id is not distinct from old.network_id then return new; end if;
    if not exists (select 1 from public.store_pins k join public.stores s on s.id = k.store_id
                   where s.network_id = new.network_id and k.store_id <> new.id
                     and k.pin = (select pin from public.store_pins where store_id = new.id)) then
      return new;
    end if;
  end if;
  insert into public.store_pins (store_id, pin) values (new.id, public.new_store_pin(new.network_id, new.id))
  on conflict (store_id) do update set pin = excluded.pin, updated_at = now();
  return new;
end;
$$;
drop trigger if exists stores_add_pin on public.stores;
create trigger stores_add_pin after insert or update of network_id on public.stores
  for each row execute function public.stores_add_pin();

-- Magasins existants : un par un, pour que chaque tirage voie les codes déjà donnés dans le réseau.
do $$ declare r record; begin
  for r in select s.id, s.network_id from public.stores s
           where not exists (select 1 from public.store_pins k where k.store_id = s.id) loop
    insert into public.store_pins (store_id, pin) values (r.id, public.new_store_pin(r.network_id, r.id));
  end loop;
end $$;

-- Le magasin change son code (s'il a circulé, ou au départ d'un vendeur).
create or replace function public.store_pin_renew(p_store_id uuid) returns text
language plpgsql security definer set search_path to '' as $$
declare v text := public.new_store_pin((select network_id from public.stores where id = p_store_id), p_store_id);
begin
  if (select auth.uid()) is null or not public.is_store_member(p_store_id) then
    raise exception 'Accès refusé' using errcode = '42501';
  end if;
  insert into public.store_pins (store_id, pin, updated_at) values (p_store_id, v, now())
  on conflict (store_id) do update set pin = excluded.pin, updated_at = now();
  return v;
end;
$$;

-- 2. Essais ratés, pour bloquer qui tenterait de deviner le code
create table if not exists public.pin_attempts (
  id bigint generated always as identity primary key,
  store_id uuid not null references public.stores(id) on delete cascade,
  client_id text not null,
  at timestamptz not null default now()
);
create index if not exists pin_attempts_store_time on public.pin_attempts (store_id, at desc);
alter table public.pin_attempts enable row level security;
revoke all on public.pin_attempts from anon, authenticated;

-- 3. Validation par le vendeur
-- Conditions : un affichage du code de moins de 24 h sur ce même appareil, et le code du magasin
-- de la promo ou de n'importe quel magasin du même réseau. La promo est alors comptée au magasin
-- qui a validé.
-- Blocage : 5 essais ratés en 15 min pour un appareil, 60 en 1 h pour un magasin.
-- Réponses : 'ok', 'bad_pin', 'locked', 'no_reveal'.
create or replace function public.vitrine_validate_use(p_id uuid, p_client_id text, p_pin text)
returns text language plpgsql security definer set search_path to '' as $$
declare v record; v_store uuid;
begin
  if p_client_id is null or p_client_id !~ '^[A-Za-z0-9_-]{8,64}$' then return 'no_reveal'; end if;

  select r.id, r.store_id as here, sp.store_id as origin, s.network_id as net into v
  from public.code_reveals r
  join public.store_promotions sp on sp.id = r.store_promotion_id
  join public.stores s on s.id = sp.store_id
  where r.store_promotion_id = p_id and r.client_id = p_client_id
    and r.revealed_at > now() - interval '24 hours'
  order by r.revealed_at desc limit 1;
  if not found then return 'no_reveal'; end if;

  delete from public.pin_attempts a where a.store_id = v.origin and a.at < now() - interval '1 hour';
  if (select count(*) from public.pin_attempts a
        where a.store_id = v.origin and a.client_id = p_client_id and a.at > now() - interval '15 minutes') >= 5
     or (select count(*) from public.pin_attempts a where a.store_id = v.origin) >= 60 then
    return 'locked';
  end if;

  if p_pin ~ '^[0-9]{4}$' then
    select k.store_id into v_store from public.store_pins k join public.stores s on s.id = k.store_id
    where k.pin = p_pin and (k.store_id in (v.here, v.origin) or (v.net is not null and s.network_id = v.net))
    order by (k.store_id = v.here) desc, (k.store_id = v.origin) desc limit 1;
  end if;
  if v_store is null then
    insert into public.pin_attempts (store_id, client_id) values (v.origin, p_client_id);
    return 'bad_pin';
  end if;

  -- Validée en caisse : le client était bien au magasin qui a donné son code.
  update public.code_reveals set used_at = coalesce(used_at, now()), store_id = v_store, located = true,
    confidence = 'probable', user_id = coalesce(user_id, (select auth.uid()))
  where id = v.id;
  return 'ok';
end;
$$;

-- 4. La confirmation déclarative du client disparaît
drop function if exists public.vitrine_confirm_use(uuid, text);

-- 5. Lien vers une promo terminée : on renvoie son magasin (sans la promo), pour montrer ses
-- autres promos en cours. Les fiches magasin sont déjà publiques (vitrine_store).
create or replace function public.vitrine_promo(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path to '' as $$
declare v record; v_store uuid;
begin
  select * into v from public.vitrine_live() l where l.sp_id = p_id;
  if found then
    return jsonb_build_object('promo', v.promo, 'store', public.vitrine_store_json(v.store_id));
  end if;
  select sp.store_id into v_store from public.store_promotions sp where sp.id = p_id;
  if v_store is null then return null; end if;
  return jsonb_build_object('ended', true, 'store', public.vitrine_store_json(v_store));
end;
$$;

-- Droits : seules les fonctions d'entrée sont appelables
revoke all on function public.new_store_pin(uuid, uuid) from public, anon, authenticated;
revoke all on function public.stores_add_pin() from public, anon, authenticated;
revoke all on function public.store_pin_renew(uuid) from public, anon;
grant execute on function public.store_pin_renew(uuid) to authenticated;
revoke all on function public.vitrine_validate_use(uuid, text, text) from public;
grant execute on function public.vitrine_validate_use(uuid, text, text) to anon, authenticated;
