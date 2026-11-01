-- MOD-068 : Google Business Profile, préparation du branchement.
-- Quand le compte Google gère plusieurs fiches, le refresh token (chiffré par
-- l'Edge Function, clé hors base) attend 15 minutes que le commerçant choisisse.
create table if not exists private.google_pending (
  store_id   uuid primary key references public.stores (id) on delete cascade,
  user_id    uuid not null,
  cipher     bytea not null,
  locations  jsonb not null,
  expires_at timestamptz not null default now() + interval '15 minutes'
);

create or replace function public.google_pending_put(p_store_id uuid, p_user_id uuid, p_cipher bytea, p_locations jsonb)
returns void language sql security definer set search_path to '' as $$
  delete from private.google_pending where expires_at < now();
  insert into private.google_pending (store_id, user_id, cipher, locations)
  values (p_store_id, p_user_id, p_cipher, p_locations)
  on conflict (store_id) do update set user_id = excluded.user_id, cipher = excluded.cipher,
    locations = excluded.locations, expires_at = now() + interval '15 minutes';
$$;

-- Consommé une seule fois, et seulement par le compte qui a lancé la connexion.
create or replace function public.google_pending_take(p_store_id uuid, p_user_id uuid)
returns table (cipher bytea, locations jsonb) language sql security definer set search_path to '' as $$
  delete from private.google_pending g
  where g.store_id = p_store_id and g.user_id = p_user_id and g.expires_at > now()
  returning g.cipher, g.locations;
$$;

-- Liste des fiches à proposer (noms et adresses, jamais le chiffré), pour un membre du magasin.
create or replace function public.google_pending_locations(p_store_id uuid)
returns jsonb language plpgsql stable security definer set search_path to '' as $$
begin
  if not public.is_store_member(p_store_id) then raise exception 'Accès réservé au magasin.'; end if;
  return (select g.locations from private.google_pending g
          where g.store_id = p_store_id and g.user_id = auth.uid() and g.expires_at > now());
end;
$$;

revoke all on function public.google_pending_put(uuid, uuid, bytea, jsonb) from public, anon, authenticated;
revoke all on function public.google_pending_take(uuid, uuid) from public, anon, authenticated;
revoke all on function public.google_pending_locations(uuid) from public, anon;
grant execute on function public.google_pending_put(uuid, uuid, bytea, jsonb) to service_role;
grant execute on function public.google_pending_take(uuid, uuid) to service_role;
grant execute on function public.google_pending_locations(uuid) to authenticated;
