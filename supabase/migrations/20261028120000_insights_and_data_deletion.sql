-- =============================================================================
-- Statistiques des publications et suppression des données à la demande de Meta
-- =============================================================================
--
-- Trois ajouts, tous additifs :
--
--   1. social_accounts.meta_user_id
--      L'identifiant Facebook (propre à l'app) de la personne qui a connecté le
--      compte. Meta n'envoie QUE cet identifiant quand quelqu'un retire Vitriin
--      de son compte ou demande la suppression de ses données : sans lui, on ne
--      saurait pas quoi effacer.
--
--   2. publications.metrics / metrics_fetched_at
--      Les statistiques Meta d'un post, relues par meta-insights. Stockées pour
--      que l'app affiche les derniers chiffres connus sans rappeler Meta à
--      chaque ouverture d'écran.
--
--   3. private.data_deletion_requests
--      Le registre des demandes de suppression, consulté par l'URL de suivi que
--      Meta transmet à la personne. Hors PostgREST, comme les secrets.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Identifiant Facebook de la personne qui connecte
-- -----------------------------------------------------------------------------
alter table public.social_accounts
  add column meta_user_id text;

comment on column public.social_accounts.meta_user_id is
  'Identifiant Facebook propre à l''app (ASID) de la personne qui a autorisé '
  'la connexion. Seule clé fournie par Meta dans les demandes de suppression '
  'et de désautorisation.';

create index social_accounts_meta_user_idx
  on public.social_accounts (meta_user_id)
  where meta_user_id is not null;

-- Lisible par les membres du magasin, comme le reste de la ligne : c'est un
-- identifiant propre à Vitriin, inutilisable hors de l'app, et un REVOKE
-- colonne n'aurait aucun effet face au GRANT SELECT de table de la migration
-- précédente. L'écriture reste réservée à service_role.


-- -----------------------------------------------------------------------------
-- 2. Statistiques des publications
-- -----------------------------------------------------------------------------
alter table public.publications
  add column metrics            jsonb,
  add column metrics_fetched_at timestamptz;

comment on column public.publications.metrics is
  'Statistiques Meta du post, normalisées : reach, views, reactions, comments, '
  'shares, saved, interactions. Écrites par meta-insights. NULL tant qu''elles '
  'n''ont pas été relues.';


-- -----------------------------------------------------------------------------
-- 3. Registre des demandes de suppression
-- -----------------------------------------------------------------------------
create table private.data_deletion_requests (
  confirmation_code  text primary key,
  meta_user_id       text not null,
  source             text not null check (source in ('deletion', 'deauthorize')),
  accounts_deleted   integer not null default 0,
  requested_at       timestamptz not null default now(),
  completed_at       timestamptz
);

comment on table private.data_deletion_requests is
  'Demandes de suppression reçues de Meta. Conservées pour répondre à l''URL de '
  'suivi transmise à la personne. Ne contient aucune donnée personnelle hormis '
  'l''identifiant Facebook propre à l''app.';


-- Effacement : supprime les comptes connectés par cette personne (le chiffré
-- part avec, par la cascade sur private.social_account_secrets) et inscrit la
-- demande au registre, dans la même transaction.
--
-- Ce qui n'est PAS supprimé, volontairement : promotions et publications. Ce
-- sont les données du magasin, pas des données obtenues de Facebook. Leur
-- suppression relève de la procédure de suppression du compte Vitriin.
create or replace function public.data_deletion_execute(
  p_confirmation_code text,
  p_meta_user_id      text,
  p_source            text
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deleted integer;
begin
  if p_meta_user_id is null or length(p_meta_user_id) = 0 then
    raise exception 'meta_user_id manquant';
  end if;

  delete from public.social_accounts
  where meta_user_id = p_meta_user_id;
  get diagnostics v_deleted = row_count;

  insert into private.data_deletion_requests
    (confirmation_code, meta_user_id, source, accounts_deleted, completed_at)
  values
    (p_confirmation_code, p_meta_user_id, p_source, v_deleted, now());

  return v_deleted;
end;
$$;

comment on function public.data_deletion_execute is
  'Supprime les comptes sociaux connectés par une personne Facebook et inscrit '
  'la demande au registre. service_role uniquement.';


-- Lecture du statut, pour l'URL de suivi. Ne rend ni l'identifiant Facebook ni
-- rien qui permette de relier le code à une personne.
create or replace function public.data_deletion_status(p_confirmation_code text)
returns table (requested_at timestamptz, completed_at timestamptz, accounts_deleted integer)
language sql
stable
security definer
set search_path = ''
as $$
  select r.requested_at, r.completed_at, r.accounts_deleted
  from private.data_deletion_requests r
  where r.confirmation_code = p_confirmation_code;
$$;


-- -----------------------------------------------------------------------------
-- Grants
-- -----------------------------------------------------------------------------
grant select, insert, delete on private.data_deletion_requests to service_role;

revoke execute on function public.data_deletion_execute(text, text, text) from public;
revoke execute on function public.data_deletion_status(text)              from public;

grant execute on function public.data_deletion_execute(text, text, text) to service_role;
grant execute on function public.data_deletion_status(text)              to service_role;
