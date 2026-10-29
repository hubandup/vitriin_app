-- is_demo_store ne sert qu'à demo_guard (SECURITY DEFINER) : inutile pour les utilisateurs.
revoke execute on function public.is_demo_store(uuid) from public, anon, authenticated;
