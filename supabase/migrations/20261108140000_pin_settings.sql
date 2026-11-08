-- MOD-074 : code vendeur configurable, par la centrale, le magasin et la promo.
-- Centrale : networks.settings.pin_mode = 'required' (obligatoire) | 'optional' (au choix des magasins,
--   valeur par défaut) | 'off' (pas de code vendeur). Réglé par la centrale ou par le Manager Vitriin.
-- Magasin, si la centrale a choisi 'optional' (ou magasin indépendant) : stores.pin_scope =
--   'inherit' (seulement quand la centrale l'impose sur une campagne ; défaut : inactif)
--   | 'all' (toutes ses promos) | 'per_promo' (le magasin choisit promo par promo).
-- Promo : promotions.pin_required (la centrale l'impose sur une campagne),
--   store_promotions.pin_required (choix du magasin en mode 'per_promo').
-- Sans code vendeur, le client confirme lui-même (vitrine_confirm_use, déclaratif, rétablie).
-- code_reveals.validated_by : 'pin' (validé par le vendeur) ou 'client' (déclaré par le client).

alter table public.stores add column if not exists pin_scope text not null default 'inherit'
  check (pin_scope in ('inherit', 'all', 'per_promo'));
grant update (pin_scope) on public.stores to authenticated;

alter table public.promotions add column if not exists pin_required boolean not null default false;
grant insert (pin_required), update (pin_required) on public.promotions to authenticated;

alter table public.store_promotions add column if not exists pin_required boolean not null default false;
grant update (pin_required) on public.store_promotions to authenticated;

alter table public.code_reveals add column if not exists validated_by text
  check (validated_by in ('client', 'pin'));
-- Historique : avant le code vendeur (migration store_redeem_pin du 08/11, 05:23 UTC), tout était déclaratif.
update public.code_reveals
  set validated_by = case when used_at < '2026-11-08 05:23:07+00' then 'client' else 'pin' end
  where used_at is not null and validated_by is null;

-- Le code vendeur est-il demandé pour cette promo dans ce magasin ? Seule source de vérité.
create or replace function public.promo_pin_required(p_sp_id uuid) returns boolean
language sql stable security definer set search_path to '' as $$
  select case coalesce(n.settings->>'pin_mode', 'optional')
      when 'required' then true
      when 'off' then false
      else p.pin_required or s.pin_scope = 'all' or (s.pin_scope = 'per_promo' and sp.pin_required)
    end
  from public.store_promotions sp
  join public.promotions p on p.id = sp.promotion_id
  join public.stores s on s.id = sp.store_id
  left join public.networks n on n.id = s.network_id
  where sp.id = p_sp_id;
$$;

-- Le fil public dit au client s'il faudra faire valider par le vendeur ('pin').
create or replace function public.vitrine_live(p_store_id uuid default null)
returns table (sp_id uuid, store_id uuid, promo jsonb) language sql stable security definer set search_path to '' as $$
  select sp.id, sp.store_id, jsonb_build_object(
      'id', sp.id, 'store_id', sp.store_id,
      'title', coalesce(nullif(sp.overrides->>'title', ''), p.title),
      'text', coalesce(nullif(sp.overrides->>'text', ''), p.description, ''),
      'img', coalesce(nullif(sp.overrides->>'media_url', ''), p.media_url),
      'type', p.promo_type, 'mechanic', p.mechanic,
      'orig', p.details->'orig', 'val', p.details->'val', 'xy', p.details->'xy', 'sub', p.details->>'sub',
      'starts_at', p.starts_at, 'ends_at', p.ends_at, 'has_code', (p.discount_code is not null or p.ean_code is not null),
      'likes', (select count(*) from public.promo_likes l where l.store_promotion_id = sp.id),
      'pin', coalesce(public.promo_pin_required(sp.id), false))
  from public.store_promotions sp join public.promotions p on p.id = sp.promotion_id
  where sp.status = 'active' and not sp.hidden and not sp.suspended
    and p.status = 'active' and p.promo_type is not null and now() between p.starts_at and p.ends_at
    and (p_store_id is null or sp.store_id = p_store_id);
$$;
revoke all on function public.vitrine_live(uuid) from public, anon, authenticated;

-- Confirmation par le client, refusée quand le code vendeur est demandé.
create or replace function public.vitrine_confirm_use(p_id uuid, p_client_id text)
returns boolean language plpgsql security definer set search_path to '' as $$
declare n int;
begin
  if p_client_id is null or p_client_id !~ '^[A-Za-z0-9_-]{8,64}$' then return false; end if;
  if coalesce(public.promo_pin_required(p_id), true) then return false; end if;
  update public.code_reveals set used_at = coalesce(used_at, now()), validated_by = coalesce(validated_by, 'client'),
    user_id = coalesce(user_id, (select auth.uid()))
  where store_promotion_id = p_id and client_id = p_client_id and revealed_at > now() - interval '24 hours';
  get diagnostics n = row_count;
  return n > 0;
end;
$$;

-- Validation par le vendeur : inchangée (MOD-072), marque en plus validated_by = 'pin'.
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

  update public.code_reveals set used_at = coalesce(used_at, now()), validated_by = 'pin', store_id = v_store,
    located = true, confidence = 'probable', user_id = coalesce(user_id, (select auth.uid()))
  where id = v.id;
  return 'ok';
end;
$$;

-- Espace magasin : le code, le réglage de la centrale et celui du magasin, en un appel.
create or replace function public.store_pin_settings(p_store_id uuid) returns jsonb
language plpgsql stable security definer set search_path to '' as $$
begin
  if (select auth.uid()) is null or not public.is_store_member(p_store_id) then
    raise exception 'Accès refusé' using errcode = '42501';
  end if;
  return (select jsonb_build_object(
      'pin', (select k.pin from public.store_pins k where k.store_id = s.id),
      'mode', case when n.id is null then 'optional' else coalesce(n.settings->>'pin_mode', 'optional') end,
      'scope', s.pin_scope)
    from public.stores s left join public.networks n on n.id = s.network_id where s.id = p_store_id);
end;
$$;

-- Manager Vitriin : réglage de la centrale au set-up.
create or replace function public.manager_network_pin_mode(p_id uuid, p_mode text) returns jsonb
language plpgsql security definer set search_path to '' as $$
declare v jsonb;
begin
  perform public.manager_guard();
  if p_mode not in ('required', 'optional', 'off') then raise exception 'Réglage inconnu.'; end if;
  update public.networks set settings = coalesce(settings, '{}'::jsonb) || jsonb_build_object('pin_mode', p_mode)
  where id = p_id returning settings into v;
  if v is null then raise exception 'Centrale introuvable.'; end if;
  return v;
end;
$$;

revoke all on function public.promo_pin_required(uuid) from public, anon, authenticated;
revoke all on function public.vitrine_confirm_use(uuid, text) from public;
grant execute on function public.vitrine_confirm_use(uuid, text) to anon, authenticated;
revoke all on function public.vitrine_validate_use(uuid, text, text) from public;
grant execute on function public.vitrine_validate_use(uuid, text, text) to anon, authenticated;
revoke all on function public.store_pin_settings(uuid) from public, anon;
grant execute on function public.store_pin_settings(uuid) to authenticated;
revoke all on function public.manager_network_pin_mode(uuid, text) from public, anon;
grant execute on function public.manager_network_pin_mode(uuid, text) to authenticated;
