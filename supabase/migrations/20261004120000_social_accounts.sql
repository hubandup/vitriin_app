-- =============================================================================
-- Vitriin — Comptes sociaux connectés (plomberie Meta)
-- =============================================================================
-- Un magasin connecte ses Pages Facebook et ses comptes Instagram
-- professionnels. On stocke, par compte, le token qui permet de publier.
--
-- Principe structurant : LE TOKEN N'EST PAS DANS UNE TABLE EXPOSÉE.
--
--   public.social_accounts          → métadonnées, lisibles par le PDV et sa
--                                     centrale. Aucune colonne de token.
--   private.social_account_secrets  → le chiffré. Schéma absent de
--                                     `api.schemas` : hors d'atteinte de
--                                     PostgREST, quel que soit le rôle.
--
-- RLS filtre des LIGNES, pas des colonnes. Tant que le chiffré vit dans la même
-- table que le reste, un `select *` d'un membre du réseau parent le ramène. Le
-- séparer rend la garantie structurelle au lieu de déclarative.
--
-- Le chiffrement lui-même se fait en AES-256-GCM dans l'Edge Function, avec une
-- clé qui vit dans les secrets Supabase. Postgres ne voit que du bytea opaque
-- et ne connaît jamais la clé : le déchiffrement en SQL est impossible par
-- construction, pas par policy.
-- =============================================================================


-- =============================================================================
-- 1. SCHÉMA PRIVÉ
-- =============================================================================
-- Non listé dans `api.schemas` (config.toml) : PostgREST ne le sert pas. Les
-- REVOKE ci-dessous sont la seconde ligne de défense, si quelqu'un ajoutait un
-- jour `private` à la liste par inadvertance.

create schema if not exists private;

revoke all on schema private from public;
revoke usage on schema private from anon, authenticated;


-- =============================================================================
-- 2. ENUM
-- =============================================================================
-- Pas de valeur `expired` : un token de Page n'a pas d'expiration. Il meurt
-- silencieusement — révocation par le commerçant, perte de l'administration de
-- la Page, changement de mot de passe. On l'apprend par un code d'erreur Graph,
-- jamais par une date.

create type public.social_account_status as enum ('active', 'revoked', 'error');

comment on type public.social_account_status is
  'active : publiable. revoked : le commerçant doit refaire la connexion. '
  'error : échec transitoire côté Meta, on retentera.';


-- =============================================================================
-- 3. TABLES
-- =============================================================================

-- -----------------------------------------------------------------------------
-- social_accounts — un compte social connecté pour un magasin
-- -----------------------------------------------------------------------------
create table public.social_accounts (
  id                   uuid primary key default gen_random_uuid(),
  store_id             uuid not null references public.stores (id) on delete cascade,
  channel              public.publication_channel not null,

  external_account_id  text not null,
  parent_external_id   text,

  display_name         text not null,
  avatar_url           text,

  scopes               text[],
  status               public.social_account_status not null default 'active',
  last_error           text,
  last_error_at        timestamptz,
  last_checked_at      timestamptz,

  connected_by         uuid references public.profiles (id) on delete set null,
  connected_at         timestamptz not null default now(),
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),

  -- Reconnexion : on retombe sur la même ligne, on ne duplique pas.
  unique (store_id, channel, external_account_id),

  -- Un compte Instagram publie TOUJOURS via le token de sa Page porteuse. Sans
  -- cette Page, la ligne est inutilisable — autant l'interdire à l'écriture.
  constraint social_accounts_instagram_needs_parent
    check (channel <> 'instagram' or parent_external_id is not null)
);

comment on table public.social_accounts is
  'Comptes sociaux connectés d''un magasin. AUCUNE colonne de token : le '
  'chiffré vit dans private.social_account_secrets, hors PostgREST.';

comment on column public.social_accounts.external_account_id is
  'Identifiant côté Meta : page_id pour facebook, '
  'instagram_business_account_id pour instagram.';

comment on column public.social_accounts.parent_external_id is
  'Instagram uniquement : le page_id de la Page Facebook porteuse. Le compte '
  'Instagram professionnel n''a pas de token propre dans ce flux, il publie '
  'avec le token de sa Page.';

comment on column public.social_accounts.status is
  'Mis à jour par meta-publish quand une publication révèle un token mort, et '
  'par meta-health-check en amont — pour que la centrale voie « ce PDV n''est '
  'plus connecté » sans attendre qu''une campagne échoue.';

create trigger social_accounts_set_updated_at
  before update on public.social_accounts
  for each row execute function public.set_updated_at();


-- -----------------------------------------------------------------------------
-- private.social_account_secrets — le chiffré, et rien d'autre
-- -----------------------------------------------------------------------------
create table private.social_account_secrets (
  social_account_id    uuid primary key
                         references public.social_accounts (id) on delete cascade,
  access_token_cipher  bytea not null,
  key_version          smallint not null default 1,
  token_expires_at     timestamptz,
  rotated_at           timestamptz not null default now()
);

comment on table private.social_account_secrets is
  'Token chiffré en AES-256-GCM par l''Edge Function. La clé n''est nulle part '
  'en base : un dump de cette table ne donne rien.';

comment on column private.social_account_secrets.access_token_cipher is
  'iv (12 octets) || ciphertext || tag (16 octets). L''AAD du GCM est '
  '« store_id|channel|external_account_id » : un chiffré recopié d''une ligne '
  'vers une autre ne déchiffre pas.';

comment on column private.social_account_secrets.key_version is
  'Pour une rotation de TOKEN_ENCRYPTION_KEY sans déconnecter tout le monde : '
  'on déchiffre avec l''ancienne clé, on rechiffre avec la nouvelle.';

comment on column private.social_account_secrets.token_expires_at is
  'NULL pour un token de Page — il n''expire pas. La colonne existe pour le '
  'jour où on stockerait un token à durée de vie bornée.';


-- -----------------------------------------------------------------------------
-- private.oauth_states — anti-CSRF et anti-rejeu
-- -----------------------------------------------------------------------------
-- Le `state` est signé en HMAC, ce qui suffit contre la forge. Mais un state
-- signé reste rejouable tant qu'il n'a pas expiré. Ce nonce à usage unique
-- ferme la fenêtre : la ligne est supprimée au moment où on la lit.
--
-- Porte aussi le user_id, que le callback ne peut pas déduire autrement : il
-- s'exécute sans JWT (c'est Meta qui redirige le navigateur).

create table private.oauth_states (
  nonce       text primary key,
  store_id    uuid not null references public.stores (id) on delete cascade,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null
);

create index oauth_states_expires_at_idx on private.oauth_states (expires_at);


-- =============================================================================
-- 4. LES SEULES PORTES VERS LE CHIFFRÉ
-- =============================================================================
-- `private` n'étant pas exposé à PostgREST, même la service_role ne peut pas
-- l'interroger en REST. Ces fonctions SECURITY DEFINER sont l'unique accès, et
-- elles sont réservées à service_role.
--
-- `revoke execute ... from public` est indispensable : Postgres accorde EXECUTE
-- à PUBLIC par défaut sur toute nouvelle fonction. Ne pas nommer `anon` dans un
-- GRANT ne l'exclut PAS. Même motif que create_store / create_network dans la
-- migration initiale.
--
-- service_role contourne RLS, mais PAS les GRANT : ce REVOKE est une vraie
-- frontière, pas une convention.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Upsert atomique : le compte et son secret naissent ensemble
-- -----------------------------------------------------------------------------
-- En deux appels séparés, un échec entre les deux laisserait un compte affiché
-- comme connecté mais sans token — publiable en apparence, cassé en réalité.
create or replace function public.social_account_upsert(
  p_store_id            uuid,
  p_channel             public.publication_channel,
  p_external_account_id text,
  p_display_name        text,
  p_cipher              bytea,
  p_parent_external_id  text         default null,
  p_avatar_url          text         default null,
  p_scopes              text[]       default null,
  p_connected_by        uuid         default null,
  p_key_version         smallint     default 1,
  p_token_expires_at    timestamptz  default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  insert into public.social_accounts (
    store_id, channel, external_account_id, parent_external_id,
    display_name, avatar_url, scopes, connected_by,
    status, last_error, last_error_at, last_checked_at, connected_at
  )
  values (
    p_store_id, p_channel, p_external_account_id, p_parent_external_id,
    p_display_name, p_avatar_url, p_scopes, p_connected_by,
    'active', null, null, now(), now()
  )
  on conflict (store_id, channel, external_account_id) do update set
    parent_external_id = excluded.parent_external_id,
    display_name       = excluded.display_name,
    avatar_url         = excluded.avatar_url,
    scopes             = excluded.scopes,
    connected_by       = excluded.connected_by,
    -- Une reconnexion répare un compte révoqué : on repart propre.
    status             = 'active',
    last_error         = null,
    last_error_at      = null,
    last_checked_at    = now(),
    connected_at       = now()
  returning id into v_id;

  insert into private.social_account_secrets (
    social_account_id, access_token_cipher, key_version, token_expires_at, rotated_at
  )
  values (v_id, p_cipher, p_key_version, p_token_expires_at, now())
  on conflict (social_account_id) do update set
    access_token_cipher = excluded.access_token_cipher,
    key_version         = excluded.key_version,
    token_expires_at    = excluded.token_expires_at,
    rotated_at          = now();

  return v_id;
end;
$$;

comment on function public.social_account_upsert is
  'Unique chemin d''écriture d''un compte social. Insère la ligne publique et '
  'son secret dans la même transaction.';


-- -----------------------------------------------------------------------------
-- Lecture du chiffré — rend du bytea, jamais du clair
-- -----------------------------------------------------------------------------
create or replace function public.social_account_token_get(p_account_id uuid)
returns bytea
language sql
stable
security definer
set search_path = ''
as $$
  select s.access_token_cipher
  from private.social_account_secrets s
  where s.social_account_id = p_account_id;
$$;

comment on function public.social_account_token_get is
  'Rend le token CHIFFRÉ. Seule l''Edge Function détient la clé : même si cette '
  'fonction fuitait, l''appelant n''obtiendrait que des octets inexploitables.';


-- -----------------------------------------------------------------------------
-- Statut de connexion
-- -----------------------------------------------------------------------------
create or replace function public.social_account_set_status(
  p_account_id uuid,
  p_status     public.social_account_status,
  p_error      text default null
)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.social_accounts
  set status          = p_status,
      last_error      = p_error,
      last_error_at   = case when p_error is null then null else now() end,
      last_checked_at = now()
  where id = p_account_id;
$$;

comment on function public.social_account_set_status is
  'Appelée par meta-publish quand une publication révèle un token mort, et par '
  'meta-health-check en amont. p_error est déjà redacté côté Edge Function.';


-- -----------------------------------------------------------------------------
-- États OAuth
-- -----------------------------------------------------------------------------
create or replace function public.oauth_state_create(
  p_nonce       text,
  p_store_id    uuid,
  p_user_id     uuid,
  p_ttl_seconds integer default 600
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Ménage opportuniste : la table reste petite sans cron dédié.
  delete from private.oauth_states where expires_at < now();

  insert into private.oauth_states (nonce, store_id, user_id, expires_at)
  values (
    p_nonce, p_store_id, p_user_id,
    now() + make_interval(secs => greatest(p_ttl_seconds, 60))
  );
end;
$$;


-- Consomme le nonce : la ligne est SUPPRIMÉE au moment où on la lit. Un second
-- appel avec le même state ne rend rien. C'est ce DELETE ... RETURNING, et pas
-- la signature, qui empêche le rejeu.
create or replace function public.oauth_state_consume(p_nonce text)
returns table (store_id uuid, user_id uuid)
language sql
security definer
set search_path = ''
as $$
  delete from private.oauth_states s
  where s.nonce = p_nonce
    and s.expires_at > now()
  returning s.store_id, s.user_id;
$$;


-- =============================================================================
-- 5. IDEMPOTENCE DES PUBLICATIONS
-- =============================================================================
-- Sans cette contrainte, un second appel à meta-publish republie le post. Avec
-- elle, la fonction upsert la ligne en `pending` avant l'appel Graph puis met à
-- jour LA MÊME ligne : rejouable sans doublon, et un échec reste réessayable.
--
-- Cohérent avec le commentaire existant de la table : « un post par canal ».

alter table public.publications
  add constraint publications_one_post_per_channel
  unique (store_promotion_id, channel);


-- =============================================================================
-- 6. INDEX
-- =============================================================================

create index social_accounts_store_id_idx on public.social_accounts (store_id);

-- Taillé pour la requête de meta-publish : « les comptes publiables de ce
-- magasin ». Partiel, donc les comptes révoqués n'alourdissent pas l'index.
create index social_accounts_publishable_idx
  on public.social_accounts (store_id, channel)
  where status = 'active';

-- Pour le dashboard Centrale : « quels PDV ont décroché ».
create index social_accounts_broken_idx
  on public.social_accounts (store_id)
  where status <> 'active';


-- =============================================================================
-- 7. RLS
-- =============================================================================

alter table public.social_accounts enable row level security;

-- Le PDV voit ses comptes. La centrale parente aussi — c'est ce qui lui permet
-- d'afficher « ce point de vente n'est plus connecté ». Elle ne voit que des
-- métadonnées : le token n'est pas dans cette table.
--
-- Mêmes fonctions que store_members_select dans la migration initiale, donc
-- exactement la même sémantique de réseau parent.
create policy social_accounts_select on public.social_accounts
  for select to authenticated
  using (
    public.is_store_member(store_id)
    or public.is_store_network_member(store_id)
  );

-- Déconnecter un compte. Réservé au magasin : la centrale observe, elle ne
-- débranche pas ses franchisés.
--
-- Supprime notre copie et, en cascade, le secret. Ne révoque PAS côté Meta —
-- il faudrait un appel DELETE /{user-id}/permissions, donc une Edge Function
-- dédiée. À ouvrir si l'App Review l'exige.
create policy social_accounts_delete_members on public.social_accounts
  for delete to authenticated
  using (public.is_store_member(store_id));

-- Pas de policy INSERT ni UPDATE, volontairement : l'écriture passe
-- exclusivement par social_account_upsert en service_role. Même parti pris que
-- `publications` dans la migration initiale.


-- =============================================================================
-- 8. GRANTS
-- =============================================================================
-- « Automatically expose new tables » est désactivé sur ce projet : sans GRANT
-- explicite, la table reste invisible via PostgREST, policies ou pas.
-- =============================================================================

-- anon : rien. La vitrine publique n'a aucune raison de savoir qui est connecté
-- à quoi. Volontairement absent, pas oublié.

grant select, delete on public.social_accounts to authenticated;

-- service_role : écriture des métadonnées et des publications depuis les Edge
-- Functions. Explicite plutôt que dépendant des default privileges du projet.
grant usage on schema public to service_role;
grant select, insert, update, delete on public.social_accounts to service_role;
grant select, insert, update          on public.publications    to service_role;
grant select                          on public.store_promotions to service_role;
grant select                          on public.promotions       to service_role;
grant select                          on public.store_members    to service_role;

-- Les fonctions sensibles : REVOKE d'abord (PUBLIC a EXECUTE par défaut), puis
-- GRANT à service_role seule. Ni anon ni authenticated ne peuvent les appeler.
revoke execute on function public.social_account_upsert(
  uuid, public.publication_channel, text, text, bytea, text, text, text[], uuid,
  smallint, timestamptz
) from public;
revoke execute on function public.social_account_token_get(uuid)   from public;
revoke execute on function public.social_account_set_status(
  uuid, public.social_account_status, text
) from public;
revoke execute on function public.oauth_state_create(text, uuid, uuid, integer) from public;
revoke execute on function public.oauth_state_consume(text)        from public;

grant execute on function public.social_account_upsert(
  uuid, public.publication_channel, text, text, bytea, text, text, text[], uuid,
  smallint, timestamptz
) to service_role;
grant execute on function public.social_account_token_get(uuid)    to service_role;
grant execute on function public.social_account_set_status(
  uuid, public.social_account_status, text
) to service_role;
grant execute on function public.oauth_state_create(text, uuid, uuid, integer) to service_role;
grant execute on function public.oauth_state_consume(text)         to service_role;
