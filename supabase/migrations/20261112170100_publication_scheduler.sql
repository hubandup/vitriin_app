-- =============================================================================
-- Vitriin — Planificateur de publications et calendrier (12 novembre 2026, MOD-082)
-- =============================================================================
-- Décisions du 12/11 :
--   • calendrier ET vraie programmation dès le MVP ;
--   • une centrale peut imposer la date et l'heure de publication d'une promo
--     obligatoire, mais c'est le magasin qui valide : il publie sur SES comptes
--     (règle Meta : Centrale → Magasin → post, jamais la centrale en direct) ;
--   • la publication automatique tourne derrière un interrupteur
--     (secret SCHEDULER_ENABLED de la fonction publish-scheduled), coupé tant
--     que l'App Review Meta n'est pas validée.
--
-- Modèle : une publication programmée est une ligne de `publications` au statut
-- 'scheduled' avec `scheduled_at`. Même table, même contrainte « un post par
-- canal » : quand l'heure arrive, la fonction publish-scheduled la reprend
-- exactement comme meta-publish reprend une ligne 'failed'.
--
-- Retour arrière (migration inverse) :
--   select cron.unschedule('vitriin-publish-scheduled');
--   delete from public.publications where status = 'scheduled';
--   drop function public.schedule_publication(uuid, text[], timestamptz),
--     public.unschedule_publication(uuid),
--     public.scheduler_check_secret(text), public.publications_release_stuck();
--   drop trigger promotions_sync_imposed_publish_at on public.promotions;
--   drop function public.promotions_sync_imposed_publish_at();
--   alter table public.promotions drop column publish_at, drop column publish_at_locked;
--   alter table public.publications drop column scheduled_at, drop column claimed_at;
--   select vault... (supprimer le secret scheduler_cron_secret dans Vault)
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Colonnes
-- -----------------------------------------------------------------------------

alter table public.publications
  add column scheduled_at timestamptz,
  add column claimed_at   timestamptz;

comment on column public.publications.scheduled_at is
  'Date et heure de publication programmée (statut scheduled). Conservée après publication, pour l''historique.';
comment on column public.publications.claimed_at is
  'Début de la publication en cours (statut pending posé par meta-publish ou publish-scheduled). '
  'Sert à libérer une publication bloquée si la fonction s''est arrêtée en route.';

alter table public.publications
  add constraint publications_scheduled_has_date
  check (status <> 'scheduled' or scheduled_at is not null);

create index publications_due_idx
  on public.publications (scheduled_at)
  where status = 'scheduled';

alter table public.promotions
  add column publish_at        timestamptz,
  add column publish_at_locked boolean not null default false;

comment on column public.promotions.publish_at is
  'Date et heure de publication proposée par l''auteur (centrale). Pré-remplit la programmation du magasin.';
comment on column public.promotions.publish_at_locked is
  'Date imposée par la centrale (promo obligatoire seulement) : le magasin valide, sans pouvoir changer l''heure.';

alter table public.promotions
  add constraint promotions_publish_at_in_window
  check (publish_at is null or publish_at < ends_at);

alter table public.promotions
  add constraint promotions_publish_at_lock
  check (
    not publish_at_locked
    or (publish_at is not null and is_mandatory and created_by_network_id is not null)
  );

-- Les droits d'écriture de promotions sont accordés colonne par colonne.
grant insert (publish_at, publish_at_locked), update (publish_at, publish_at_locked)
  on public.promotions to authenticated;


-- -----------------------------------------------------------------------------
-- 2. Programmer / déprogrammer (magasin)
-- -----------------------------------------------------------------------------
-- Seule porte d'écriture du magasin sur les publications programmées : la table
-- publications reste fermée en écriture côté client.
--   • membre du magasin, activation non suspendue, non refusée ;
--   • une activation en attente passe à active (programmer = accepter) ;
--   • date imposée par la centrale : p_at est ignoré, on prend publish_at ;
--   • chaque canal doit être connecté et actif sur le magasin ;
--   • un canal déjà publié n'est pas touché (contrainte un post par canal).
-- Rend la date retenue.

create or replace function public.schedule_publication(
  p_store_promotion_id uuid,
  p_channels           text[],
  p_at                 timestamptz default null
)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sp public.store_promotions%rowtype;
  v_pr public.promotions%rowtype;
  v_at timestamptz;
  v_ch text;
begin
  select * into v_sp from public.store_promotions where id = p_store_promotion_id;
  if not found then
    raise exception 'Activation introuvable.' using errcode = 'no_data_found';
  end if;
  if not public.is_store_member(v_sp.store_id) then
    raise exception 'Action réservée aux membres du magasin.' using errcode = 'insufficient_privilege';
  end if;
  if public.is_demo_store(v_sp.store_id) then
    raise exception 'Réseau de démonstration : la programmation y est simulée.' using errcode = 'insufficient_privilege';
  end if;
  if v_sp.suspended or v_sp.hidden then
    raise exception 'Cette promotion est suspendue ou supprimée sur ce point de vente.';
  end if;
  if v_sp.status = 'declined' then
    raise exception 'Vous avez refusé cette promotion.';
  end if;

  select * into v_pr from public.promotions where id = v_sp.promotion_id;
  if v_pr.status in ('draft', 'archived') then
    raise exception 'Cette promotion ne peut pas être publiée.';
  end if;

  v_at := case when v_pr.publish_at_locked then v_pr.publish_at else p_at end;
  if v_at is null then
    raise exception 'Date de publication manquante.';
  end if;
  if v_at < now() + interval '1 minute' then
    if v_pr.publish_at_locked then
      raise exception 'La date imposée par votre centrale est passée : publiez maintenant.';
    end if;
    raise exception 'Choisissez une date à venir.';
  end if;
  if v_at >= v_pr.ends_at then
    raise exception 'La publication doit avoir lieu avant la fin de la promotion.';
  end if;

  if p_channels is null or cardinality(p_channels) = 0 then
    raise exception 'Choisissez au moins un réseau.';
  end if;
  foreach v_ch in array p_channels loop
    if v_ch not in ('facebook', 'instagram', 'google_business') then
      raise exception 'Réseau inconnu : %', v_ch;
    end if;
    if not exists (
      select 1 from public.social_accounts a
      where a.store_id = v_sp.store_id
        and a.channel = v_ch::public.publication_channel
        and a.status = 'active' and a.enabled
    ) then
      raise exception 'Réseau non connecté sur ce magasin : %', v_ch;
    end if;
  end loop;

  update public.store_promotions
  set status = 'active', activated_at = coalesce(activated_at, now())
  where id = v_sp.id and status = 'pending';

  -- Un canal retiré de la liste n'est plus programmé.
  delete from public.publications
  where store_promotion_id = v_sp.id
    and status = 'scheduled'
    and channel::text <> all (p_channels);

  insert into public.publications (store_promotion_id, channel, status, scheduled_at)
  select v_sp.id, c::public.publication_channel, 'scheduled', v_at
  from unnest(p_channels) as c
  on conflict (store_promotion_id, channel) do update
    set status = 'scheduled', scheduled_at = excluded.scheduled_at, error_message = null
    where public.publications.status in ('scheduled', 'failed');

  return v_at;
end;
$$;

revoke all on function public.schedule_publication(uuid, text[], timestamptz) from public, anon;
grant execute on function public.schedule_publication(uuid, text[], timestamptz) to authenticated;


-- Déprogrammer : toujours possible, même une date imposée. Le magasin garde la
-- main sur ses comptes ; la centrale le voit repasser « à valider ».
create or replace function public.unschedule_publication(p_store_promotion_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_store_id uuid;
  v_n        integer;
begin
  select store_id into v_store_id from public.store_promotions where id = p_store_promotion_id;
  if v_store_id is null then
    raise exception 'Activation introuvable.' using errcode = 'no_data_found';
  end if;
  if not public.is_store_member(v_store_id) then
    raise exception 'Action réservée aux membres du magasin.' using errcode = 'insufficient_privilege';
  end if;

  delete from public.publications
  where store_promotion_id = p_store_promotion_id and status = 'scheduled';
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

revoke all on function public.unschedule_publication(uuid) from public, anon;
grant execute on function public.unschedule_publication(uuid) to authenticated;


-- -----------------------------------------------------------------------------
-- 3. La centrale déplace une date imposée : les programmations suivent
-- -----------------------------------------------------------------------------

create or replace function public.promotions_sync_imposed_publish_at()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.publish_at_locked
     and new.publish_at > now()
     and (new.publish_at is distinct from old.publish_at or not old.publish_at_locked) then
    update public.publications pu
    set scheduled_at = new.publish_at
    from public.store_promotions sp
    where sp.id = pu.store_promotion_id
      and sp.promotion_id = new.id
      and pu.status = 'scheduled';
  end if;
  return new;
end;
$$;

revoke all on function public.promotions_sync_imposed_publish_at() from public, anon, authenticated;

create trigger promotions_sync_imposed_publish_at
  after update of publish_at, publish_at_locked on public.promotions
  for each row execute function public.promotions_sync_imposed_publish_at();


-- -----------------------------------------------------------------------------
-- 4. Plomberie du planificateur (service uniquement)
-- -----------------------------------------------------------------------------

-- Secret partagé entre pg_cron et la fonction publish-scheduled. Il vit dans
-- Vault ; la fonction le vérifie par cette RPC, sans jamais le lire.
select vault.create_secret(
  encode(extensions.gen_random_bytes(32), 'hex'),
  'scheduler_cron_secret',
  'Appel pg_cron → Edge Function publish-scheduled (MOD-082)'
)
where not exists (select 1 from vault.secrets where name = 'scheduler_cron_secret');

create or replace function public.scheduler_check_secret(p_secret text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select ds.decrypted_secret = p_secret
     from vault.decrypted_secrets ds
     where ds.name = 'scheduler_cron_secret'),
    false
  );
$$;

revoke all on function public.scheduler_check_secret(text) from public, anon, authenticated;
grant execute on function public.scheduler_check_secret(text) to service_role;


-- Une publication restée « pending » plus de 15 minutes : la fonction s'est
-- arrêtée en route. On la passe en échec pour qu'elle puisse être reprise.
create or replace function public.publications_release_stuck()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_n integer;
begin
  update public.publications
  set status = 'failed',
      error_message = 'Publication interrompue : réessayez.'
  where status = 'pending'
    and claimed_at is not null
    and claimed_at < now() - interval '15 minutes';
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

revoke all on function public.publications_release_stuck() from public, anon, authenticated;
grant execute on function public.publications_release_stuck() to service_role;


-- Déclenchement : chaque minute. La fonction ne publie rien tant que
-- SCHEDULER_ENABLED n'est pas posé à "true" dans ses secrets.
create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;

select cron.schedule(
  'vitriin-publish-scheduled',
  '* * * * *',
  $cron$
  select net.http_post(
    url := 'https://zjugauidrijghesgsmap.supabase.co/functions/v1/publish-scheduled',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-scheduler-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'scheduler_cron_secret')
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 140000
  );
  $cron$
);
