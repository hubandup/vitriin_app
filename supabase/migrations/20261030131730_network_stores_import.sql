-- Import des points de vente par la centrale (Excel / CSV).
-- La première version de import_network_stores est remplacée par la
-- migration suivante (20261030131848_network_stores_import_fix).
alter table public.stores add column if not exists invited_at timestamptz;

create or replace function public.unaccent_simple(t text)
returns text language sql immutable set search_path to '' as $$
  select translate(t,
    'àâäáãåçéèêëíìîïñóòôöõúùûüýÿÀÂÄÁÃÅÇÉÈÊËÍÌÎÏÑÓÒÔÖÕÚÙÛÜÝœŒæÆ',
    'aaaaaaceeeeiiiinooooouuuuyyAAAAAACEEEEIIIINOOOOOUUUUYoOaA');
$$;
revoke all on function public.unaccent_simple(text) from public, anon;
grant execute on function public.unaccent_simple(text) to authenticated, service_role;
