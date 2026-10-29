-- L'app magasin affiche le contact support de l'enseigne et ses CGV.
drop function if exists public.get_store_network(uuid);
create function public.get_store_network(p_store_id uuid)
returns table(network_id uuid, network_name text, logo_url text, support_email text, phone text, cgv_url text)
language sql stable security definer set search_path = ''
as $$
  select n.id, n.name, n.logo_url, n.support_email, n.phone, n.cgv_url
  from public.stores s
  join public.networks n on n.id = s.network_id
  where s.id = p_store_id
    and public.is_store_member(p_store_id);
$$;
revoke execute on function public.get_store_network(uuid) from public, anon;
grant execute on function public.get_store_network(uuid) to authenticated;
