-- =============================================================================
-- Vitriin — Paramètres de la Centrale (29 octobre 2026) · docs/JOURNAL.md MOD-005
-- =============================================================================
-- 1. Identité de la centrale et réglages du réseau (networks).
-- 2. Prénom / nom (profiles).
-- 3. Acceptation automatique des promos réseau : réglage centrale + choix du
--    magasin (stores.auto_accept), appliqués par le trigger d'activation.
-- 4. Code EAN en caisse et types de promotion propres au réseau.
-- 5. Équipe centrale : liste des membres (RPC), rôles admin / éditeur
--    (éditeur = member), propriétaire protégé, envoi des promos par l'éditeur.
-- 6. La centrale (admin) peut corriger la fiche de ses magasins.
-- =============================================================================

-- 1. Identité et réglages ------------------------------------------------------
alter table public.networks
  add column legal_name    text,
  add column address       text,
  add column support_email text,
  add column phone         text,
  add column siret         text,
  add column siren         text,
  add column vat_number    text,
  add column cgv_url       text,
  add column settings      jsonb not null default '{}'::jsonb;

alter table public.networks
  add constraint networks_siret_format  check (siret is null or siret ~ '^\d{14}$'),
  add constraint networks_siren_format  check (siren is null or siren ~ '^\d{9}$'),
  add constraint networks_vat_format    check (vat_number is null or vat_number ~ '^[A-Z]{2}[A-Z0-9]{2,12}$'),
  add constraint networks_email_format  check (support_email is null or support_email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  add constraint networks_cgv_https     check (cgv_url is null or cgv_url ~ '^https://'),
  add constraint networks_settings_obj  check (jsonb_typeof(settings) = 'object');

comment on column public.networks.settings is
  'Réglages réseau : auto_accept (bool), discount_code (bool), ean_code (bool), '
  'custom_types ([{k,label,ico}]), email_templates ({invite, relance, promo}).';

grant update (legal_name, address, support_email, phone, siret, siren, vat_number, cgv_url, settings)
  on public.networks to authenticated;   -- policy networks_update_admins : admins seulement

-- 2. Prénom / nom ------------------------------------------------------------------
alter table public.profiles add column first_name text, add column last_name text;
grant update (first_name, last_name) on public.profiles to authenticated;

-- 3. Acceptation automatique --------------------------------------------------------
alter table public.stores add column auto_accept boolean not null default true;
comment on column public.stores.auto_accept is
  'Le magasin accepte d''office les promos de son réseau quand la centrale l''a activé. '
  'Le magasin peut le désactiver.';
grant update (auto_accept) on public.stores to authenticated;

create or replace function public.apply_mandatory_status()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if public.is_promotion_mandatory(new.promotion_id) then
    -- Campagne imposée : le magasin relaie, sans arbitrage.
    new.status := 'active';
    new.activated_at := coalesce(new.activated_at, now());
  elsif exists (
    select 1
    from public.promotions p
    join public.stores s on s.id = new.store_id
    join public.networks n on n.id = s.network_id
    where p.id = new.promotion_id
      and p.created_by_network_id = n.id
      and s.auto_accept
      and coalesce((n.settings->>'auto_accept')::boolean, false)
  ) then
    -- Acceptation automatique : activée, le magasin publie toujours lui-même.
    new.status := 'active';
    new.activated_at := coalesce(new.activated_at, now());
  else
    new.status := 'pending';
    new.activated_at := null;
  end if;
  return new;
end;
$$;
revoke execute on function public.apply_mandatory_status() from public, anon, authenticated;

-- 4. EAN et types propres -----------------------------------------------------------
alter table public.promotions add column ean_code text;
alter table public.promotions
  add constraint promotions_ean_format check (ean_code is null or ean_code ~ '^(\d{8}|\d{13})$');
alter table public.promotions drop constraint promotions_promo_type_check;
alter table public.promotions
  add constraint promotions_promo_type_check check (promo_type is null or promo_type ~ '^[a-z0-9_]{2,40}$');
grant insert (ean_code), update (ean_code) on public.promotions to authenticated;

-- 5. Équipe centrale ----------------------------------------------------------------
create or replace function public.network_members_list(p_network_id uuid)
returns table (user_id uuid, email text, first_name text, last_name text, avatar_url text, role public.network_role, created_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select nm.user_id, u.email::text, p.first_name, p.last_name, p.avatar_url, nm.role, nm.created_at
  from public.network_members nm
  join auth.users u on u.id = nm.user_id
  left join public.profiles p on p.id = nm.user_id
  where nm.network_id = p_network_id
    and public.is_network_member(p_network_id)
  order by nm.created_at;
$$;
revoke execute on function public.network_members_list(uuid) from public, anon;
grant execute on function public.network_members_list(uuid) to authenticated;

-- Le propriétaire ne se retire ni ne se rétrograde depuis l'app, et personne ne
-- devient propriétaire par l'app.
create or replace function public.guard_network_owner()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    return coalesce(new, old);            -- service_role / migrations
  end if;
  if tg_op = 'DELETE' and old.role = 'owner' then
    raise exception 'Le propriétaire du réseau ne peut pas être retiré.' using errcode = 'check_violation';
  end if;
  if tg_op = 'UPDATE' and (old.role = 'owner' or new.role = 'owner') and old.role is distinct from new.role then
    raise exception 'Le rôle de propriétaire ne se modifie pas depuis l''application.' using errcode = 'check_violation';
  end if;
  return coalesce(new, old);
end;
$$;
revoke execute on function public.guard_network_owner() from public, anon, authenticated;
create trigger network_members_guard_owner
  before update or delete on public.network_members
  for each row execute function public.guard_network_owner();

-- Recherche d'un compte par email, pour la fonction d'invitation (service_role).
create or replace function public.user_id_by_email(p_email text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select id from auth.users where lower(email) = lower(trim(p_email)) limit 1;
$$;
revoke execute on function public.user_id_by_email(text) from public, anon, authenticated;
grant execute on function public.user_id_by_email(text) to service_role;

-- L'éditeur (member) crée et envoie les promos ; l'admin gère en plus l'équipe,
-- les réglages et les magasins.
create or replace function public.send_promotion(
  p_promotion_id uuid,
  p_store_ids    uuid[] default null
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_network_id uuid;
  v_count      integer;
begin
  select p.created_by_network_id into v_network_id
  from public.promotions p where p.id = p_promotion_id;

  if v_network_id is null then
    raise exception 'Promotion introuvable ou non créée par une centrale.'
      using errcode = 'no_data_found';
  end if;

  if not public.is_network_member(v_network_id) then
    raise exception 'Action réservée à l''équipe de la centrale.'
      using errcode = 'insufficient_privilege';
  end if;

  insert into public.store_promotions (promotion_id, store_id)
  select p_promotion_id, s.id
  from public.stores s
  where s.network_id = v_network_id
    and (p_store_ids is null or s.id = any (p_store_ids))
  on conflict (promotion_id, store_id) do nothing;

  get diagnostics v_count = row_count;

  update public.promotions
  set status = 'active'
  where id = p_promotion_id and status in ('draft', 'scheduled');

  return v_count;
end;
$$;
revoke execute on function public.send_promotion(uuid, uuid[]) from public, anon;
grant execute on function public.send_promotion(uuid, uuid[]) to authenticated;

-- 6. La centrale corrige la fiche de ses magasins -----------------------------------
create policy stores_update_network_admins on public.stores
  for update to authenticated
  using (network_id is not null and public.is_network_admin(network_id))
  with check (network_id is not null and public.is_network_admin(network_id));
