-- MOD-071 · Ping du workflow GitHub « Supabase keep-alive ».
-- Depuis 20261030205641_vitrine_publique, anon n'a plus de SELECT direct sur
-- stores : le ping tombait en 401. Cette fonction touche Postgres sans lire
-- aucune table.
-- Retour arrière : drop function public.keepalive();

create or replace function public.keepalive()
returns timestamptz
language sql
stable
security invoker
set search_path = ''
as $$ select now() $$;

revoke all on function public.keepalive() from public;
grant execute on function public.keepalive() to anon, authenticated;

comment on function public.keepalive() is 'Keep-alive GitHub Actions : renvoie now(), aucune donnée exposée.';
