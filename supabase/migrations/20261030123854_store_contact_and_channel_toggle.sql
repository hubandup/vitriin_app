-- Fiche magasin complétée par le magasin : contact principal et site web.
alter table public.stores
  add column if not exists contact_first_name text check (length(contact_first_name) <= 60),
  add column if not exists contact_last_name text check (length(contact_last_name) <= 60),
  add column if not exists contact_phone text check (contact_phone ~ '^[0-9 +().-]{6,25}$'),
  add column if not exists contact_email text check (contact_email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' and length(contact_email) <= 200),
  add column if not exists website text check (website ~ '^https?://[^\s]+$' and length(website) <= 300);
grant update (contact_first_name, contact_last_name, contact_phone, contact_email, website) on public.stores to authenticated;

-- Un compte social connecté peut être désactivé sans être déconnecté :
-- le magasin ne publie plus dessus tant qu'il ne le réactive pas.
alter table public.social_accounts add column if not exists enabled boolean not null default true;
grant update (enabled) on public.social_accounts to authenticated;
drop policy if exists social_accounts_update_enabled_members on public.social_accounts;
create policy social_accounts_update_enabled_members on public.social_accounts
  for update to authenticated using (public.is_store_member(store_id)) with check (public.is_store_member(store_id));
