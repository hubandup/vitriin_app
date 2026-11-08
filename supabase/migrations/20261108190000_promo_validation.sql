-- MOD-076 : le magasin choisit la validation de chaque promo qu'il crée.
-- promotions.validation : 'qr' (le vendeur scanne le QR du client), 'pin' (le vendeur tape le code du
-- magasin sur le téléphone du client), 'ean' (code-barres scanné par la caisse, le client confirme),
-- 'none' (pas de validation, le client confirme). Null : ancien fonctionnement (MOD-074).
-- La centrale garde la main : 'required' impose une validation par le vendeur, 'off' l'interdit.

alter table public.promotions add column if not exists validation text
  check (validation in ('qr', 'pin', 'ean', 'none'));
grant insert (validation), update (validation) on public.promotions to authenticated;

create or replace function public.promo_pin_required(p_sp_id uuid) returns boolean
language sql stable security definer set search_path to '' as $$
  select case coalesce(n.settings->>'pin_mode', 'optional')
      when 'required' then true
      when 'off' then false
      else case when p.validation is not null then p.validation in ('qr', 'pin')
                else p.pin_required or s.pin_scope = 'all' or (s.pin_scope = 'per_promo' and sp.pin_required) end
    end
  from public.store_promotions sp
  join public.promotions p on p.id = sp.promotion_id
  join public.stores s on s.id = sp.store_id
  left join public.networks n on n.id = s.network_id
  where sp.id = p_sp_id;
$$;
revoke all on function public.promo_pin_required(uuid) from public, anon, authenticated;

-- Le fil indique la validation à afficher au client ('check' ; 'val' est déjà la valeur de la remise) :
-- 'qr' (QR seul, code vendeur en secours), 'pin' (code vendeur seul), 'vendor' (QR et code vendeur),
-- 'ean' ou 'none' (le client confirme lui-même). 'pin' (booléen) reste pour les anciens écrans.
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
      'pin', x.req,
      'check', case when x.req then (case when p.validation in ('qr', 'pin') then p.validation else 'vendor' end)
                    when p.validation = 'ean' then 'ean' else 'none' end)
  from public.store_promotions sp join public.promotions p on p.id = sp.promotion_id
  cross join lateral (select coalesce(public.promo_pin_required(sp.id), false) as req) x
  where sp.status = 'active' and not sp.hidden and not sp.suspended
    and p.status = 'active' and p.promo_type is not null and now() between p.starts_at and p.ends_at
    and (p_store_id is null or sp.store_id = p_store_id);
$$;
revoke all on function public.vitrine_live(uuid) from public, anon, authenticated;
