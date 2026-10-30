-- Démo : le magasin vitrine garde une promo « à traiter » (à venir, non obligatoire).
-- (Version exacte enregistrée côté Supabase : voir supabase_migrations.schema_migrations.)
do $do$
declare d text;
begin
  d := pg_get_functiondef('public.manager_build_demo(text)'::regprocedure);
  d := replace(d, '  -- Promos créées par le magasin vitrine.', $q$  update public.store_promotions spx set status = 'pending', activated_at = null
  where spx.store_id = v_store0 and spx.promotion_id in (
    select p.id from public.promotions p where p.created_by_network_id = v_net and p.starts_at > now() and not p.is_mandatory);
  delete from public.publications pu using public.store_promotions spx
  where pu.store_promotion_id = spx.id and spx.store_id = v_store0 and spx.status = 'pending';

  -- Promos créées par le magasin vitrine.$q$);
  execute d;
end
$do$;

update public.store_promotions spx set status = 'pending', activated_at = null
from public.networks n, public.promotions p
where n.is_demo and n.demo_sector in ('cheminees', 'jardinerie') and spx.store_id = (n.settings->>'demo_store_id')::uuid
  and p.id = spx.promotion_id and p.created_by_network_id = n.id and p.starts_at > now() and not p.is_mandatory;
delete from public.publications pu using public.store_promotions spx, public.networks n
where pu.store_promotion_id = spx.id and n.is_demo and n.demo_sector in ('cheminees', 'jardinerie')
  and spx.store_id = (n.settings->>'demo_store_id')::uuid and spx.status = 'pending';
