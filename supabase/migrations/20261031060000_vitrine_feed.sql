-- MOD-058 : le fil particulier s'affiche toujours, même sans position.
-- Une promo de centrale n'apparaît qu'une fois : dans le magasin le plus proche (avec position) ou dans un seul
-- magasin (sans position). Avec position : les plus proches d'abord ; sans : les plus récentes. À affiner plus tard.
create or replace function public.vitrine_feed(p_lat double precision default null, p_lng double precision default null, p_demo boolean default false)
returns jsonb language sql stable security definer set search_path to '' as $$
  with c as (
    select distinct on (sp.promotion_id) sp.promotion_id, l.promo, s.id store_id, l.promo->>'starts_at' st,
      case when p_lat between -90 and 90 and p_lng between -180 and 180 and s.lat is not null then
        2 * 6371 * asin(sqrt(power(sin(radians(s.lat - p_lat) / 2), 2)
          + cos(radians(p_lat)) * cos(radians(s.lat)) * power(sin(radians(s.lng - p_lng) / 2), 2))) end d
    from public.vitrine_live() l
    join public.store_promotions sp on sp.id = l.sp_id
    join public.stores s on s.id = l.store_id
    left join public.networks n on n.id = s.network_id
    where (p_demo or not coalesce(n.is_demo, false))
    order by sp.promotion_id, d nulls last, s.id
  )
  select coalesce(jsonb_agg(jsonb_build_object('promo', c.promo, 'store', public.vitrine_store_json(c.store_id)) order by c.d nulls last, c.st desc), '[]'::jsonb)
  from (select * from c order by d nulls last, st desc limit 80) c;
$$;
revoke all on function public.vitrine_feed(double precision, double precision, boolean) from public;
grant execute on function public.vitrine_feed(double precision, double precision, boolean) to anon, authenticated;
