-- MOD-070 : l'app magasin doit savoir si elle tourne sur un réseau de démo (publication simulée)
-- ou réel (vraie connexion Meta / Google et vraie publication). Réservé aux membres du magasin.
create or replace function public.my_store_is_demo(p_store_id uuid)
returns boolean language plpgsql stable security definer set search_path to '' as $$
begin
  if not public.is_store_member(p_store_id) then raise exception 'Accès réservé au magasin.'; end if;
  return public.is_demo_store(p_store_id);
end;
$$;
revoke all on function public.my_store_is_demo(uuid) from public, anon;
grant execute on function public.my_store_is_demo(uuid) to authenticated;
