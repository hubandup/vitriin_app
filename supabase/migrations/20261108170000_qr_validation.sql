-- MOD-075 : validation en caisse par QR code.
-- Quand le code vendeur est demandé, le téléphone du client affiche aussi un QR code à usage unique
-- (valable 10 min, renouvelé tant que l'écran reste ouvert). Le vendeur le scanne depuis son espace
-- magasin (bouton « Valider la promo d'un client ») ou avec l'appareil photo du téléphone : la promo
-- est validée sans taper de code, et l'écran du client passe tout seul à « Profité ».
-- Même règle que le code vendeur : le magasin de la promo ou n'importe quel magasin du même réseau.

alter table public.code_reveals drop constraint if exists code_reveals_validated_by_check;
alter table public.code_reveals add constraint code_reveals_validated_by_check
  check (validated_by in ('client', 'pin', 'qr'));

create table if not exists public.use_tokens (
  token text primary key check (token ~ '^[A-Za-z0-9_-]{22,64}$'),
  reveal_id bigint not null references public.code_reveals(id) on delete cascade,
  expires_at timestamptz not null default now() + interval '10 minutes',
  used_at timestamptz,
  used_by_store uuid references public.stores(id) on delete set null
);
create index if not exists use_tokens_reveal on public.use_tokens (reveal_id);
create index if not exists use_tokens_expires on public.use_tokens (expires_at);
alter table public.use_tokens enable row level security;
revoke all on public.use_tokens from anon, authenticated;

-- Client : un QR à usage unique pour l'affichage en cours (le précédent est annulé).
-- 32 octets aléatoires (deux gen_random_uuid), en base64url.
create or replace function public.vitrine_use_token(p_id uuid, p_client_id text) returns text
language plpgsql security definer set search_path to '' as $$
declare v_rev bigint; v_tok text;
begin
  if p_client_id is null or p_client_id !~ '^[A-Za-z0-9_-]{8,64}$' then return null; end if;
  select r.id into v_rev from public.code_reveals r
  where r.store_promotion_id = p_id and r.client_id = p_client_id and r.revealed_at > now() - interval '24 hours'
  order by r.revealed_at desc limit 1;
  if v_rev is null then return null; end if;
  delete from public.use_tokens where (reveal_id = v_rev and used_at is null) or expires_at < now() - interval '1 day';
  v_tok := rtrim(translate(encode(decode(replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', ''), 'hex'), 'base64'), '+/', '-_'), '=');
  insert into public.use_tokens (token, reveal_id) values (v_tok, v_rev);
  return v_tok;
end;
$$;

-- Client : la promo a-t-elle été validée par le vendeur (code ou QR) ? Interrogé toutes les 2,5 s.
create or replace function public.vitrine_use_status(p_id uuid, p_client_id text) returns boolean
language sql stable security definer set search_path to '' as $$
  select exists (select 1 from public.code_reveals r
    where r.store_promotion_id = p_id and r.client_id = p_client_id
      and r.revealed_at > now() - interval '24 hours'
      and r.used_at is not null and r.validated_by in ('pin', 'qr'));
$$;

-- Vendeur, connecté à son espace magasin : valide la promo du QR scanné.
-- Réponses (status) : ok, already, used, expired, not_allowed, unknown.
create or replace function public.store_validate_qr(p_token text, p_store_id uuid) returns jsonb
language plpgsql security definer set search_path to '' as $$
declare t record;
begin
  if (select auth.uid()) is null or not public.is_store_member(p_store_id) then
    raise exception 'Accès refusé' using errcode = '42501';
  end if;
  if p_token is null or p_token !~ '^[A-Za-z0-9_-]{22,64}$' then return jsonb_build_object('status', 'unknown'); end if;

  select u.expires_at, u.used_at, u.used_by_store, r.id as rid, sp.store_id as origin, s.network_id as net,
         s.name as origin_name, coalesce(nullif(sp.overrides->>'title', ''), p.title) as title
    into t
  from public.use_tokens u
  join public.code_reveals r on r.id = u.reveal_id
  join public.store_promotions sp on sp.id = r.store_promotion_id
  join public.promotions p on p.id = sp.promotion_id
  join public.stores s on s.id = sp.store_id
  where u.token = p_token
  for update of u;
  if not found then return jsonb_build_object('status', 'unknown'); end if;

  if t.used_at is not null then
    return jsonb_build_object('status', case when t.used_by_store = p_store_id then 'already' else 'used' end, 'title', t.title);
  end if;
  if t.expires_at < now() then return jsonb_build_object('status', 'expired', 'title', t.title); end if;
  if not (p_store_id = t.origin or (t.net is not null and exists (
      select 1 from public.stores x where x.id = p_store_id and x.network_id = t.net))) then
    return jsonb_build_object('status', 'not_allowed', 'title', t.title, 'store', t.origin_name);
  end if;

  update public.use_tokens set used_at = now(), used_by_store = p_store_id where token = p_token;
  update public.code_reveals set used_at = coalesce(used_at, now()),
    validated_by = case when validated_by = 'pin' then 'pin' else 'qr' end,
    store_id = p_store_id, located = true, confidence = 'probable'
  where id = t.rid;
  return jsonb_build_object('status', 'ok', 'title', t.title);
end;
$$;

revoke all on function public.vitrine_use_token(uuid, text) from public;
grant execute on function public.vitrine_use_token(uuid, text) to anon, authenticated;
revoke all on function public.vitrine_use_status(uuid, text) from public;
grant execute on function public.vitrine_use_status(uuid, text) to anon, authenticated;
revoke all on function public.store_validate_qr(text, uuid) from public, anon;
grant execute on function public.store_validate_qr(text, uuid) to authenticated;
