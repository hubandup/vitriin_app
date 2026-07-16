-- =============================================================================
-- Vitriin — Migration initiale
-- =============================================================================
-- Modèle : une promotion (le contenu) → N activations (store_promotions) →
-- N publications (le résultat, un post par canal).
--
-- Principes structurants :
--   * Pas de table `users` maison : `profiles` prolonge `auth.users`.
--   * Aucun rôle global sur la personne. Le rôle vit sur le lien de
--     rattachement (network_members, store_members). Un même utilisateur peut
--     être commerçant ET consommateur.
--   * Pas de super admin dans les policies : le dashboard Supabase et la
--     service_role suffisent tant qu'il n'y a pas d'équipe support.
-- =============================================================================


-- =============================================================================
-- 1. ENUMS
-- =============================================================================

-- Le MVP ne crée que des `owner`. `admin` et `member` existent dès maintenant
-- pour ne pas avoir à réécrire les policies plus tard.
create type public.network_role as enum ('owner', 'admin', 'member');

create type public.store_role as enum ('owner', 'manager');

create type public.promotion_status as enum ('draft', 'scheduled', 'active', 'archived');

-- pending  : la centrale a poussé la promo, le PDV n'a pas encore répondu
-- active   : le PDV relaie
-- declined : le PDV a refusé (impossible si la promo est obligatoire)
create type public.store_promotion_status as enum ('pending', 'active', 'declined');

create type public.publication_channel as enum (
  'facebook', 'instagram', 'tiktok', 'whatsapp', 'google_business'
);

create type public.publication_status as enum ('pending', 'published', 'failed');


-- =============================================================================
-- 2. UTILITAIRE : updated_at
-- =============================================================================

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;


-- =============================================================================
-- 3. TABLES
-- =============================================================================

-- -----------------------------------------------------------------------------
-- profiles — prolonge auth.users
-- -----------------------------------------------------------------------------
create table public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  full_name   text,
  phone       text,
  avatar_url  text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

comment on table public.profiles is
  'Prolonge auth.users. Aucune colonne role : le rôle se déduit du rattachement.';

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();


-- Création automatique du profil à l'inscription.
-- SECURITY DEFINER : le trigger s'exécute dans le contexte de l'inscription,
-- où l'utilisateur n'a pas encore de session — il ne pourrait pas passer sa
-- propre policy d'INSERT.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, avatar_url)
  values (
    new.id,
    new.raw_user_meta_data ->> 'full_name',
    new.raw_user_meta_data ->> 'avatar_url'
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();


-- -----------------------------------------------------------------------------
-- networks — réseau de franchise ou groupement d'indépendants
-- -----------------------------------------------------------------------------
create table public.networks (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  slug        text not null unique,
  join_code   text not null unique,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

comment on column public.networks.join_code is
  'Code enseigne saisi par le PDV à l''onboarding. Aucune policy ne l''expose : '
  'le flux d''onboarding réseau n''est pas tranché (lien d''activation vs code '
  'saisi). À rouvrir en Phase 3.';

create trigger networks_set_updated_at
  before update on public.networks
  for each row execute function public.set_updated_at();


-- -----------------------------------------------------------------------------
-- network_members — le rôle vit sur le lien, pas sur la personne
-- -----------------------------------------------------------------------------
create table public.network_members (
  network_id  uuid not null references public.networks (id) on delete cascade,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  role        public.network_role not null default 'owner',
  created_at  timestamptz not null default now(),
  primary key (network_id, user_id)
);


-- -----------------------------------------------------------------------------
-- stores — un point de vente, indépendant OU rattaché à un réseau
-- -----------------------------------------------------------------------------
create table public.stores (
  id           uuid primary key default gen_random_uuid(),
  network_id   uuid references public.networks (id) on delete set null,
  slug         text not null unique,
  name         text not null,
  address      text,
  city         text,
  postal_code  text,
  lat          double precision,
  lng          double precision,
  category     text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

comment on column public.stores.network_id is
  'NULL = commerçant indépendant. Un magasin appartient à au plus un réseau, '
  'donc une FK nullable suffit — pas de table de jointure.';

comment on column public.stores.slug is
  'URL publique : vitriin.co/[slug].';

create trigger stores_set_updated_at
  before update on public.stores
  for each row execute function public.set_updated_at();


-- -----------------------------------------------------------------------------
-- store_members
-- -----------------------------------------------------------------------------
create table public.store_members (
  store_id    uuid not null references public.stores (id) on delete cascade,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  role        public.store_role not null default 'owner',
  created_at  timestamptz not null default now(),
  primary key (store_id, user_id)
);


-- -----------------------------------------------------------------------------
-- promotions — le CONTENU
-- -----------------------------------------------------------------------------
create table public.promotions (
  id                    uuid primary key default gen_random_uuid(),
  created_by_store_id   uuid references public.stores (id) on delete cascade,
  created_by_network_id uuid references public.networks (id) on delete cascade,
  title                 text not null,
  description           text,
  mechanic              text,
  media_url             text,
  starts_at             timestamptz not null,
  ends_at               timestamptz not null,
  is_mandatory          boolean not null default false,
  status                public.promotion_status not null default 'draft',
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),

  -- Une promo est créée par un magasin OU par une centrale, jamais les deux,
  -- jamais aucun des deux.
  constraint promotions_single_creator
    check (num_nonnulls(created_by_store_id, created_by_network_id) = 1),

  constraint promotions_valid_window
    check (ends_at > starts_at)
);

comment on column public.promotions.mechanic is
  'Texte libre : « -30% », « 1 acheté 1 offert ».';

comment on column public.promotions.is_mandatory is
  'Réglage PAR PROMO, pas règle globale. false → les store_promotions naissent '
  'en pending, le PDV active ou décline. true → elles naissent en active, le PDV '
  'ne peut pas décliner. Une franchise impose ses campagnes nationales, un '
  'groupement d''indépendants laisse le choix.';

create trigger promotions_set_updated_at
  before update on public.promotions
  for each row execute function public.set_updated_at();


-- -----------------------------------------------------------------------------
-- store_promotions — l'ACTIVATION
-- -----------------------------------------------------------------------------
create table public.store_promotions (
  id            uuid primary key default gen_random_uuid(),
  promotion_id  uuid not null references public.promotions (id) on delete cascade,
  store_id      uuid not null references public.stores (id) on delete cascade,
  status        public.store_promotion_status not null default 'pending',
  activated_at  timestamptz,
  created_at    timestamptz not null default now(),
  unique (promotion_id, store_id)
);

comment on table public.store_promotions is
  'Qui relaie quoi, avec quel statut. Alimente le dashboard Centrale : '
  '« qui a publié, qui n''a pas encore ». Une promo, N activations — la '
  'centrale ne duplique pas 300 lignes de promotions.';


-- -----------------------------------------------------------------------------
-- publications — le RÉSULTAT, un post par canal
-- -----------------------------------------------------------------------------
create table public.publications (
  id                 uuid primary key default gen_random_uuid(),
  store_promotion_id uuid not null references public.store_promotions (id) on delete cascade,
  channel            public.publication_channel not null,
  status             public.publication_status not null default 'pending',
  external_post_id   text,
  error_message      text,
  published_at       timestamptz,
  created_at         timestamptz not null default now()
);

comment on column public.publications.external_post_id is
  'ID retourné par l''API du canal (Meta, TikTok…).';


-- =============================================================================
-- 4. FONCTIONS D'APPARTENANCE (anti-récursion)
-- =============================================================================
-- Une policy sur `stores` qui interroge `store_members`, dont la policy
-- interrogerait `stores` → récursion infinie. Ces fonctions cassent le cycle :
-- SECURITY DEFINER les exécute avec les droits du propriétaire, donc SANS
-- déclencher RLS sur les tables qu'elles lisent.
--
-- Effet de bord bienvenu : le planner les traite comme un scalaire STABLE au
-- lieu d'inliner une sous-requête corrélée à chaque ligne.
--
-- `set search_path = ''` : sans ça, un search_path hostile pourrait détourner
-- un nom de table non qualifié vers une table piégée, exécutée avec les droits
-- du propriétaire. Tout est donc qualifié en public.*.
-- =============================================================================

create or replace function public.is_store_member(p_store_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.store_members sm
    where sm.store_id = p_store_id
      and sm.user_id = (select auth.uid())
  );
$$;

create or replace function public.is_store_owner(p_store_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.store_members sm
    where sm.store_id = p_store_id
      and sm.user_id = (select auth.uid())
      and sm.role = 'owner'
  );
$$;

create or replace function public.is_network_member(p_network_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.network_members nm
    where nm.network_id = p_network_id
      and nm.user_id = (select auth.uid())
  );
$$;

create or replace function public.is_network_admin(p_network_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.network_members nm
    where nm.network_id = p_network_id
      and nm.user_id = (select auth.uid())
      and nm.role in ('owner', 'admin')
  );
$$;

-- Membre du réseau PARENT d'un magasin : c'est ce qui permet à la centrale de
-- voir les activations et publications de ses PDV.
create or replace function public.is_store_network_member(p_store_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.stores s
    join public.network_members nm on nm.network_id = s.network_id
    where s.id = p_store_id
      and nm.user_id = (select auth.uid())
  );
$$;

-- Droit d'écriture sur une promo : membre du store créateur OU du network
-- créateur. Le CHECK promotions_single_creator garantit qu'un seul des deux
-- côtés est renseigné.
create or replace function public.can_write_promotion(p_promotion_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.promotions p
    where p.id = p_promotion_id
      and (
        exists (
          select 1 from public.store_members sm
          where sm.store_id = p.created_by_store_id
            and sm.user_id = (select auth.uid())
        )
        or exists (
          select 1 from public.network_members nm
          where nm.network_id = p.created_by_network_id
            and nm.user_id = (select auth.uid())
        )
      )
  );
$$;

create or replace function public.is_promotion_mandatory(p_promotion_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select p.is_mandatory from public.promotions p where p.id = p_promotion_id),
    false
  );
$$;


-- =============================================================================
-- 5. ONBOARDING : création atomique
-- =============================================================================
-- `stores` et `networks` n'ont PAS de GRANT INSERT, volontairement. Un INSERT
-- client serait doublement cassé :
--
--   * Rien à vérifier. À l'INSERT, aucun lien n'existe encore entre le magasin
--     et son créateur : le seul WITH CHECK exprimable est `true`. N'importe quel
--     compte pourrait créer des magasins en boucle et squatter les slugs — or le
--     slug EST l'URL publique.
--   * Fenêtre orpheline. Entre l'INSERT du magasin et celui de son
--     store_members(owner), le magasin n'a pas de propriétaire :
--     stores_update_members est faux pour TOUT LE MONDE, y compris son créateur.
--     La ligne devient irrécupérable côté client — il faut le dashboard Supabase
--     pour la nettoyer.
--
-- Ces fonctions sont donc l'unique porte d'entrée. SECURITY DEFINER pour écrire
-- les deux lignes dans la même transaction : soit le magasin naît avec son
-- propriétaire, soit il ne naît pas.
-- =============================================================================

create or replace function public.create_store(
  p_slug         text,
  p_name         text,
  p_address      text default null,
  p_city         text default null,
  p_postal_code  text default null,
  p_lat          double precision default null,
  p_lng          double precision default null,
  p_category     text default null
)
returns public.stores
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_store   public.stores;
begin
  -- SECURITY DEFINER contourne RLS : on vérifie l'authentification à la main,
  -- sinon la fonction est un INSERT anonyme déguisé.
  if v_user_id is null then
    raise exception 'Authentification requise pour créer un magasin.'
      using errcode = 'insufficient_privilege';
  end if;

  -- network_id n'est volontairement pas un paramètre : le rattachement à un
  -- réseau est une décision du réseau, pas du magasin. Un magasin naît
  -- indépendant. Voir le GRANT colonne sur stores, et l'onboarding réseau en
  -- Phase 3.
  insert into public.stores (slug, name, address, city, postal_code, lat, lng, category)
  values (p_slug, p_name, p_address, p_city, p_postal_code, p_lat, p_lng, p_category)
  returning * into v_store;

  insert into public.store_members (store_id, user_id, role)
  values (v_store.id, v_user_id, 'owner');

  return v_store;

exception
  when unique_violation then
    raise exception 'Ce nom d''URL est déjà pris : %', p_slug
      using errcode = 'unique_violation';
end;
$$;

comment on function public.create_store is
  'Unique chemin de création d''un magasin. Insère le store et son '
  'store_members(owner) dans la même transaction.';


create or replace function public.create_network(
  p_name  text,
  p_slug  text
)
returns public.networks
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id   uuid := (select auth.uid());
  v_network   public.networks;
  v_join_code text;
begin
  if v_user_id is null then
    raise exception 'Authentification requise pour créer un réseau.'
      using errcode = 'insufficient_privilege';
  end if;

  -- join_code généré côté serveur : c'est un secret d'enseigne, le client ne le
  -- choisit pas. gen_random_uuid() est cryptographiquement sûr et natif — pas
  -- besoin de pgcrypto.
  v_join_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));

  insert into public.networks (name, slug, join_code)
  values (p_name, p_slug, v_join_code)
  returning * into v_network;

  insert into public.network_members (network_id, user_id, role)
  values (v_network.id, v_user_id, 'owner');

  return v_network;

exception
  when unique_violation then
    raise exception 'Ce nom d''URL de réseau est déjà pris : %', p_slug
      using errcode = 'unique_violation';
end;
$$;

comment on function public.create_network is
  'Unique chemin de création d''un réseau. Insère le network et son '
  'network_members(owner) dans la même transaction. join_code généré côté '
  'serveur.';


-- =============================================================================
-- 6. RÈGLE MÉTIER : is_mandatory
-- =============================================================================
-- Portée par des triggers et pas seulement par RLS : les Edge Functions
-- tournent en service_role et contournent RLS. Seul un trigger tient
-- l'invariant quel que soit le chemin d'écriture. Le WITH CHECK RLS plus bas
-- est une défense secondaire, pour que le client reçoive un refus propre.
-- =============================================================================

create or replace function public.apply_mandatory_status()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if public.is_promotion_mandatory(new.promotion_id) then
    -- Campagne nationale imposée : le PDV relaie, sans arbitrage.
    new.status := 'active';
    new.activated_at := coalesce(new.activated_at, now());
  else
    new.status := 'pending';
    new.activated_at := null;
  end if;
  return new;
end;
$$;

create trigger store_promotions_apply_mandatory_status
  before insert on public.store_promotions
  for each row execute function public.apply_mandatory_status();


create or replace function public.guard_mandatory_decline()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'declined'
     and public.is_promotion_mandatory(new.promotion_id) then
    raise exception
      'Cette promotion est obligatoire : le point de vente ne peut pas la décliner.'
      using errcode = 'check_violation';
  end if;

  -- Horodatage de l'activation, sans écraser une valeur déjà posée.
  if new.status = 'active' and new.activated_at is null then
    new.activated_at := now();
  end if;

  return new;
end;
$$;

create trigger store_promotions_guard_mandatory_decline
  before update on public.store_promotions
  for each row execute function public.guard_mandatory_decline();


-- =============================================================================
-- 7. INDEX
-- =============================================================================
-- Postgres n'indexe pas automatiquement les FK. Sans ça, chaque lecture des
-- policies (qui traversent toutes ces FK) fait un seq scan.

create index network_members_user_id_idx        on public.network_members (user_id);
create index store_members_user_id_idx          on public.store_members (user_id);
create index stores_network_id_idx              on public.stores (network_id);
create index stores_city_idx                    on public.stores (city);
create index promotions_created_by_store_idx    on public.promotions (created_by_store_id);
create index promotions_created_by_network_idx  on public.promotions (created_by_network_id);
create index promotions_status_idx              on public.promotions (status);
create index store_promotions_promotion_id_idx  on public.store_promotions (promotion_id);
create index store_promotions_store_id_idx      on public.store_promotions (store_id);
create index store_promotions_status_idx        on public.store_promotions (status);
create index publications_store_promotion_idx   on public.publications (store_promotion_id);
create index publications_status_idx            on public.publications (status);

-- Index partiel taillé pour la policy de lecture publique : seules les promos
-- actives sont dans l'index, la fenêtre de dates s'y résout directement.
create index promotions_public_window_idx
  on public.promotions (starts_at, ends_at)
  where status = 'active';

-- stores.slug est déjà indexé par la contrainte UNIQUE — vitriin.co/[slug] tape
-- dedans à chaque visite.


-- =============================================================================
-- 8. RLS
-- =============================================================================
-- Le projet a « automatic RLS » activé : chaque table naît avec RLS ON. Les
-- ENABLE ci-dessous sont donc redondants mais explicites — la migration doit
-- rester lisible et rejouable hors de ce projet.
-- =============================================================================

alter table public.profiles          enable row level security;
alter table public.networks          enable row level security;
alter table public.network_members   enable row level security;
alter table public.stores            enable row level security;
alter table public.store_members     enable row level security;
alter table public.promotions        enable row level security;
alter table public.store_promotions  enable row level security;
alter table public.publications      enable row level security;


-- -----------------------------------------------------------------------------
-- profiles — chacun lit et modifie le sien
-- -----------------------------------------------------------------------------
create policy profiles_select_own on public.profiles
  for select to authenticated
  using ((select auth.uid()) = id);

create policy profiles_insert_own on public.profiles
  for insert to authenticated
  with check ((select auth.uid()) = id);

create policy profiles_update_own on public.profiles
  for update to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);


-- -----------------------------------------------------------------------------
-- networks
-- -----------------------------------------------------------------------------
create policy networks_select_members on public.networks
  for select to authenticated
  using (public.is_network_member(id));

create policy networks_update_admins on public.networks
  for update to authenticated
  using (public.is_network_admin(id))
  with check (public.is_network_admin(id));

-- Pas de policy INSERT : au moment de créer le réseau, le créateur n'en est pas
-- encore membre — aucun WITH CHECK ne peut passer. La création passe par
-- public.create_network(), qui insère le réseau et son owner atomiquement.


-- -----------------------------------------------------------------------------
-- network_members
-- -----------------------------------------------------------------------------
create policy network_members_select_members on public.network_members
  for select to authenticated
  using (public.is_network_member(network_id));

create policy network_members_insert_admins on public.network_members
  for insert to authenticated
  with check (public.is_network_admin(network_id));

create policy network_members_update_admins on public.network_members
  for update to authenticated
  using (public.is_network_admin(network_id))
  with check (public.is_network_admin(network_id));

create policy network_members_delete_admins on public.network_members
  for delete to authenticated
  using (public.is_network_admin(network_id));


-- -----------------------------------------------------------------------------
-- stores — LECTURE PUBLIQUE
-- -----------------------------------------------------------------------------
-- vitriin.co/[slug] est la vitrine publique, le point d'entrée de tous les
-- consommateurs qui n'ont pas l'app. anon doit pouvoir lire.
create policy stores_select_public on public.stores
  for select to anon, authenticated
  using (true);

create policy stores_update_members on public.stores
  for update to authenticated
  using (public.is_store_member(id))
  with check (public.is_store_member(id));

create policy stores_delete_owners on public.stores
  for delete to authenticated
  using (public.is_store_owner(id));

-- Pas de policy INSERT, même raison que networks : le créateur n'est pas encore
-- store_member de son magasin, le WITH CHECK ne peut pas passer. La création
-- passe par public.create_store(), qui insère le magasin et son owner
-- atomiquement.


-- -----------------------------------------------------------------------------
-- store_members
-- -----------------------------------------------------------------------------
-- La centrale doit voir l'équipe de ses PDV → is_store_network_member.
create policy store_members_select on public.store_members
  for select to authenticated
  using (
    public.is_store_member(store_id)
    or public.is_store_network_member(store_id)
  );

create policy store_members_insert_owners on public.store_members
  for insert to authenticated
  with check (public.is_store_owner(store_id));

create policy store_members_update_owners on public.store_members
  for update to authenticated
  using (public.is_store_owner(store_id))
  with check (public.is_store_owner(store_id));

create policy store_members_delete_owners on public.store_members
  for delete to authenticated
  using (public.is_store_owner(store_id));


-- -----------------------------------------------------------------------------
-- promotions — LECTURE PUBLIQUE, mais fenêtrée
-- -----------------------------------------------------------------------------
-- Un brouillon ne doit JAMAIS fuiter : status = 'active' ET dans la fenêtre.
create policy promotions_select_public on public.promotions
  for select to anon, authenticated
  using (
    status = 'active'
    and now() >= starts_at
    and now() <= ends_at
  );

-- Policy permissive séparée : les policies s'additionnent en OR. Les membres du
-- créateur voient donc aussi leurs brouillons et leurs promos archivées.
create policy promotions_select_authors on public.promotions
  for select to authenticated
  using (public.can_write_promotion(id));

-- À l'INSERT la ligne n'existe pas encore : on ne peut pas passer par
-- can_write_promotion(id), il faut tester les colonnes de NEW directement.
create policy promotions_insert_authors on public.promotions
  for insert to authenticated
  with check (
    (created_by_store_id is not null and public.is_store_member(created_by_store_id))
    or
    (created_by_network_id is not null and public.is_network_member(created_by_network_id))
  );

create policy promotions_update_authors on public.promotions
  for update to authenticated
  using (public.can_write_promotion(id))
  with check (
    (created_by_store_id is not null and public.is_store_member(created_by_store_id))
    or
    (created_by_network_id is not null and public.is_network_member(created_by_network_id))
  );

create policy promotions_delete_authors on public.promotions
  for delete to authenticated
  using (public.can_write_promotion(id));


-- -----------------------------------------------------------------------------
-- store_promotions
-- -----------------------------------------------------------------------------
-- Lecture publique des seules activations actives : sans ça, vitriin.co/[slug]
-- ne peut pas savoir QUELLES promos ce magasin relaie — anon verrait toutes les
-- promos actives sans pouvoir les rattacher à un PDV. Les 'pending' et
-- 'declined' restent privés : rien du dashboard Centrale ne fuite.
create policy store_promotions_select_public on public.store_promotions
  for select to anon, authenticated
  using (status = 'active');

-- Le PDV concerné, et la centrale parente (« qui a publié, qui n'a pas encore »).
create policy store_promotions_select_members on public.store_promotions
  for select to authenticated
  using (
    public.is_store_member(store_id)
    or public.is_store_network_member(store_id)
  );

create policy store_promotions_insert_members on public.store_promotions
  for insert to authenticated
  with check (public.is_store_member(store_id));

-- Défense secondaire du verrou is_mandatory. L'invariant réel est tenu par le
-- trigger guard_mandatory_decline ; ce WITH CHECK sert à renvoyer un refus RLS
-- lisible au client plutôt qu'une exception PL/pgSQL.
create policy store_promotions_update_members on public.store_promotions
  for update to authenticated
  using (public.is_store_member(store_id))
  with check (
    public.is_store_member(store_id)
    and not (
      status = 'declined'
      and public.is_promotion_mandatory(promotion_id)
    )
  );


-- -----------------------------------------------------------------------------
-- publications — lecture seule côté client
-- -----------------------------------------------------------------------------
-- Aucune policy d'écriture, volontairement : c'est une Edge Function en
-- service_role qui écrit, et service_role contourne RLS.
create policy publications_select_members on public.publications
  for select to authenticated
  using (
    exists (
      select 1
      from public.store_promotions sp
      where sp.id = publications.store_promotion_id
        and (
          public.is_store_member(sp.store_id)
          or public.is_store_network_member(sp.store_id)
        )
    )
  );


-- =============================================================================
-- 9. GRANTS
-- =============================================================================
-- « Automatically expose new tables » est DÉSACTIVÉ : sans GRANT explicite,
-- une table reste invisible via l'API PostgREST, policies ou pas. RLS filtre
-- les lignes ; le GRANT ouvre la porte. Il faut les deux.
-- =============================================================================

grant usage on schema public to anon, authenticated;

-- anon : strictement la vitrine publique.
grant select on public.stores            to anon;
grant select on public.promotions        to anon;
grant select on public.store_promotions  to anon;

grant select                         on public.profiles         to authenticated;
grant insert (id, full_name, phone, avatar_url)
                                     on public.profiles         to authenticated;
grant update (full_name, phone, avatar_url)
                                     on public.profiles         to authenticated;

-- GRANT colonne par colonne, comme sur profiles : une policy autorise ou refuse
-- une LIGNE, elle ne dit rien des colonnes. Sans cette énumération, tout membre
-- autorisé à modifier la ligne peut modifier n'importe quel champ — y compris
-- ceux qui déterminent qui a autorité sur elle.
grant select on public.networks to authenticated;
grant update (name, slug, join_code) on public.networks to authenticated;

grant select, insert, update, delete on public.network_members  to authenticated;

grant select on public.stores to authenticated;
-- network_id est délibérément absent : le rattachement à un réseau n'est pas une
-- donnée du magasin, c'est une décision du réseau. Client-writable, il
-- court-circuiterait entièrement le join_code (se rattacher à une centrale sans
-- connaître son code, en écrivant l'UUID) et permettrait à un franchisé de
-- sortir unilatéralement du réseau pour échapper aux promos is_mandatory.
-- Rattachement et détachement passent par service_role, avec l'onboarding
-- réseau en Phase 3.
grant update (slug, name, address, city, postal_code, lat, lng, category)
  on public.stores to authenticated;
grant delete on public.stores to authenticated;
grant select, insert, update, delete on public.store_members    to authenticated;
grant select, insert, update, delete on public.promotions       to authenticated;
grant select, insert, update         on public.store_promotions to authenticated;
grant select                         on public.publications     to authenticated;

-- Les fonctions d'appartenance sont appelées depuis les policies, donc
-- évaluées avec le rôle de l'appelant : il lui faut EXECUTE.
grant execute on function public.is_store_member(uuid)          to anon, authenticated;
grant execute on function public.is_store_owner(uuid)           to anon, authenticated;
grant execute on function public.is_network_member(uuid)        to anon, authenticated;
grant execute on function public.is_network_admin(uuid)         to anon, authenticated;
grant execute on function public.is_store_network_member(uuid)  to anon, authenticated;
grant execute on function public.can_write_promotion(uuid)      to anon, authenticated;
grant execute on function public.is_promotion_mandatory(uuid)   to anon, authenticated;

-- Onboarding : réservé à authenticated. Postgres accorde EXECUTE à PUBLIC par
-- défaut sur toute nouvelle fonction : ne pas nommer anon dans un GRANT ne
-- l'exclut PAS, il faut révoquer. Sans ce REVOKE, anon pourrait appeler une
-- fonction SECURITY DEFINER qui écrit. Le garde `auth.uid() is null` dans le
-- corps l'arrêterait, mais on ne fait pas reposer ça sur une seule ligne.
revoke execute on function public.create_store(
  text, text, text, text, text, double precision, double precision, text
) from public;
revoke execute on function public.create_network(text, text) from public;

grant execute on function public.create_store(
  text, text, text, text, text, double precision, double precision, text
) to authenticated;
grant execute on function public.create_network(text, text) to authenticated;
