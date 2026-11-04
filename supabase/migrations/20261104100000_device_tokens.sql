-- App mobile : jetons de notification par appareil et par espace (client, magasin).
-- Table fermée : on n'y entre que par les fonctions ci-dessous. Lecture réservée aux fonctions serveur.
create table public.device_tokens (
  token      text not null check (token ~ '^Expo(nent)?PushToken\[[A-Za-z0-9_-]+\]$'),
  space      text not null check (space in ('client', 'magasin')),
  user_id    uuid not null references auth.users (id) on delete cascade,
  platform   text not null check (platform in ('ios', 'android')),
  updated_at timestamptz not null default now(),
  primary key (token, space)
);
create index device_tokens_user_idx on public.device_tokens (user_id);

alter table public.device_tokens enable row level security;
revoke all on public.device_tokens from public, anon, authenticated;
grant select, delete on public.device_tokens to service_role;

-- Rattache l'appareil au compte connecté (un téléphone qui change de compte suit le dernier connecté).
create or replace function public.register_device(p_token text, p_platform text, p_space text)
returns void language plpgsql security definer set search_path to '' as $$
begin
  if auth.uid() is null then raise exception 'Connexion requise.'; end if;
  insert into public.device_tokens (token, space, user_id, platform)
  values (p_token, p_space, auth.uid(), p_platform)
  on conflict (token, space) do update set user_id = excluded.user_id, platform = excluded.platform, updated_at = now();
end $$;
revoke all on function public.register_device(text, text, text) from public, anon;
grant execute on function public.register_device(text, text, text) to authenticated;

-- Appelée après déconnexion, donc sans compte : le jeton lui-même vaut preuve (il ne quitte jamais l'appareil et le serveur).
create or replace function public.unregister_device(p_token text, p_space text)
returns void language sql security definer set search_path to '' as $$
  delete from public.device_tokens where token = p_token and space = p_space;
$$;
revoke all on function public.unregister_device(text, text) from public;
grant execute on function public.unregister_device(text, text) to anon, authenticated;

-- Appareils des gérants concernés par une campagne (fonction serveur campaign-notify).
create or replace function public.campaign_push_tokens(p_ids uuid[])
returns table (token text, sp_id uuid) language sql stable security definer set search_path to '' as $$
  select d.token, sp.id
  from public.store_promotions sp
  join public.store_members m on m.store_id = sp.store_id
  join public.device_tokens d on d.user_id = m.user_id and d.space = 'magasin'
  where sp.id = any (p_ids);
$$;
revoke all on function public.campaign_push_tokens(uuid[]) from public, anon, authenticated;
grant execute on function public.campaign_push_tokens(uuid[]) to service_role;
