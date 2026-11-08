-- BUG-013 : un seul mode de validation par promo, jamais deux à la fois (décision Charles).
-- promo_check(sp) donne LE mode : 'qr' (le vendeur scanne le QR du client), 'pin' (le vendeur tape son code),
-- 'ean' (code-barres ou code promo passé en caisse, le client confirme), 'web' (MOD-079 : code promo à utiliser
-- sur le site internet du magasin, le client confirme) ou 'none' (le client confirme).
--   1. Choix explicite du magasin (promotions.validation) ;
--   2. sinon : code-barres ou code promo => 'ean' ; anciens réglages code vendeur => 'pin' ; sinon 'qr' (MOD-078).
--   Réglage de la centrale : 'off' remplace qr/pin par 'ean' (s'il y a un code) ou 'none' ;
--   'required' remplace 'none' par 'qr'.
-- Le serveur fait respecter ce mode : QR délivré seulement en mode qr, code vendeur accepté seulement en mode
-- pin, code révélé seulement en mode ean ou web, confirmation par le client seulement en mode ean, web ou none.
-- Retour arrière : recréer les fonctions de 20261108220000_qr_default.sql, 20261108190000_promo_validation.sql
-- (vitrine_live), MOD-075 (vitrine_use_token), MOD-073 (vitrine_validate_use) et vitrine_reveal, puis
-- supprimer promo_check.

alter table public.promotions drop constraint if exists promotions_validation_check;
alter table public.promotions add constraint promotions_validation_check
  check (validation in ('qr', 'pin', 'ean', 'web', 'none'));

create or replace function public.promo_check(p_sp_id uuid) returns text
language sql stable security definer set search_path to '' as $$
  select case
      when m.mode = 'off' and x.k in ('qr', 'pin') then case when x.has_code then 'ean' else 'none' end
      when m.mode = 'required' and x.k = 'none' then 'qr'
      else x.k end
  from public.store_promotions sp
  join public.promotions p on p.id = sp.promotion_id
  join public.stores s on s.id = sp.store_id
  left join public.networks n on n.id = s.network_id
  cross join lateral (select coalesce(n.settings->>'pin_mode', 'optional') as mode) m
  cross join lateral (select (p.ean_code is not null or p.discount_code is not null) as has_code) c
  cross join lateral (select c.has_code, coalesce(p.validation, case
      when c.has_code then 'ean'
      when p.pin_required or s.pin_scope = 'all' or (s.pin_scope = 'per_promo' and sp.pin_required) then 'pin'
      else 'qr' end) as k) x
  where sp.id = p_sp_id;
$$;
revoke all on function public.promo_check(uuid) from public, anon, authenticated;

-- Validation par le vendeur (QR ou code) : le client ne peut pas confirmer seul.
create or replace function public.promo_pin_required(p_sp_id uuid) returns boolean
language sql stable security definer set search_path to '' as $$
  select public.promo_check(p_sp_id) in ('qr', 'pin');
$$;
revoke all on function public.promo_pin_required(uuid) from public, anon, authenticated;

create or replace function public.vitrine_live(p_store_id uuid default null)
returns table (sp_id uuid, store_id uuid, promo jsonb) language sql stable security definer set search_path to '' as $$
  select sp.id, sp.store_id, jsonb_build_object(
      'id', sp.id, 'store_id', sp.store_id,
      'title', coalesce(nullif(sp.overrides->>'title', ''), p.title),
      'text', coalesce(nullif(sp.overrides->>'text', ''), p.description, ''),
      'img', coalesce(nullif(sp.overrides->>'media_url', ''), p.media_url),
      'type', p.promo_type, 'mechanic', p.mechanic,
      'orig', p.details->'orig', 'val', p.details->'val', 'xy', p.details->'xy', 'sub', p.details->>'sub',
      'starts_at', p.starts_at, 'ends_at', p.ends_at,
      'has_code', x.k in ('ean', 'web') and (p.discount_code is not null or p.ean_code is not null),
      'likes', (select count(*) from public.promo_likes l where l.store_promotion_id = sp.id),
      'pin', x.k in ('qr', 'pin'),
      'check', x.k)
  from public.store_promotions sp join public.promotions p on p.id = sp.promotion_id
  cross join lateral (select coalesce(public.promo_check(sp.id), 'none') as k) x
  where sp.status = 'active' and not sp.hidden and not sp.suspended
    and p.status = 'active' and p.promo_type is not null and now() between p.starts_at and p.ends_at
    and (p_store_id is null or sp.store_id = p_store_id);
$$;
revoke all on function public.vitrine_live(uuid) from public, anon, authenticated;

-- Code révélé seulement en mode code-barres / code en caisse (ean) ou code promo du site (web).
create or replace function public.vitrine_reveal(p_id uuid, p_client_id text, p_lat double precision default null, p_lng double precision default null)
returns jsonb language plpgsql security definer set search_path to '' as $$
declare v record; v_uid uuid := auth.uid();
begin
  select p.discount_code, p.ean_code, l.promo->>'check' as k into v
  from public.vitrine_live() l join public.store_promotions sp on sp.id = l.sp_id join public.promotions p on p.id = sp.promotion_id
  where l.sp_id = p_id;
  if not found then raise exception 'Cette promotion n''est plus disponible.'; end if;
  perform public.record_code_reveal_at(p_id, p_client_id, p_lat, p_lng);
  if v_uid is not null then
    update public.code_reveals set user_id = v_uid
    where store_promotion_id = p_id and client_id = p_client_id and revealed_on = current_date and user_id is null;
  end if;
  if v.k = 'web' then return jsonb_build_object('code', v.discount_code, 'ean', null); end if;
  if v.k <> 'ean' then return jsonb_build_object('code', null, 'ean', null); end if;
  return jsonb_build_object('code', v.discount_code, 'ean', v.ean_code);
end;
$$;

-- QR délivré seulement en mode qr.
create or replace function public.vitrine_use_token(p_id uuid, p_client_id text)
returns text language plpgsql security definer set search_path to '' as $$
declare v_rev bigint; v_tok text;
begin
  if p_client_id is null or p_client_id !~ '^[A-Za-z0-9_-]{8,64}$' then return null; end if;
  if public.promo_check(p_id) is distinct from 'qr' then return null; end if;
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

-- Code vendeur accepté seulement en mode pin.
create or replace function public.vitrine_validate_use(p_id uuid, p_client_id text, p_pin text)
returns text language plpgsql security definer set search_path to '' as $$
declare v record; v_store uuid;
begin
  if p_client_id is null or p_client_id !~ '^[A-Za-z0-9_-]{8,64}$' then return 'no_reveal'; end if;
  if public.promo_check(p_id) is distinct from 'pin' then return 'wrong_mode'; end if;

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
