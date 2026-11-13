-- =============================================================================
-- Vitriin — Campagnes : étaler un temps fort sur sa période (12 novembre 2026, MOD-083)
-- =============================================================================
-- Une campagne regroupe les promos d'un temps fort (ex. Black Friday, 80 promos
-- sur 15 jours) et étale leurs publications sur la période.
--   • la centrale crée la campagne en trois gestes : nom + dates, promos, « Répartir » ;
--   • « Répartir » calcule une date de publication par promo (promotions.publish_at)
--     à partir des réglages Paramètres › Diffusion (networks.settings.diffusion) ;
--   • la centrale PROPOSE le planning, elle n'impose rien : chaque magasin
--     l'accepte d'un geste (campaign_accept) ou décale une promo à la main ;
--   • la centrale voit qui a accepté, qui a ajusté, qui n'a pas répondu.
--
-- Réglages networks.settings.diffusion (tous facultatifs) :
--   max_per_day int (1-24, défaut 6) · slots ["09:00","12:00","18:00"]
--   off_days [7] (ISO : 1 = lundi … 7 = dimanche) · order "featured" | "date" | "mix"
--
-- Retour arrière (migration inverse) :
--   drop function public.campaign_spread(uuid), public.campaign_propose(uuid),
--     public.campaign_accept(uuid, uuid), public.campaign_withdraw(uuid, uuid),
--     public.campaign_tracking(uuid), public.is_network_store_member(uuid),
--     public.promotions_campaign_guard();
--   drop table public.campaign_acceptances, ... ;
--   alter table public.promotions drop column campaign_id, drop column is_featured;
--   drop table public.campaigns;
--   puis recréer promotions_sync_imposed_publish_at() dans sa version MOD-082.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Tables
-- -----------------------------------------------------------------------------

create table public.campaigns (
  id          uuid primary key default gen_random_uuid(),
  network_id  uuid not null references public.networks (id) on delete cascade,
  name        text not null check (char_length(btrim(name)) between 1 and 80),
  starts_on   date not null,
  ends_on     date not null,
  status      text not null default 'draft' check (status in ('draft', 'proposed')),
  spread_at   timestamptz,
  proposed_at timestamptz,
  created_by  uuid default auth.uid() references auth.users (id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint campaigns_dates check (ends_on >= starts_on and ends_on - starts_on <= 92)
);

comment on table public.campaigns is
  'Temps fort d''une centrale (ex. Black Friday) : regroupe des promos et étale leurs publications sur la période. MOD-083.';

create index campaigns_network_idx on public.campaigns (network_id, starts_on desc);

create trigger campaigns_updated_at
  before update on public.campaigns
  for each row execute function public.set_updated_at();

alter table public.promotions
  add column campaign_id uuid references public.campaigns (id) on delete set null,
  add column is_featured boolean not null default false;

comment on column public.promotions.campaign_id is 'Campagne (temps fort) à laquelle appartient la promo.';
comment on column public.promotions.is_featured is 'Promo phare : part en premier quand l''ordre de passage le demande.';

create index promotions_campaign_idx on public.promotions (campaign_id) where campaign_id is not null;

-- Les droits sur promotions sont accordés colonne par colonne.
grant select (campaign_id, is_featured), insert (campaign_id, is_featured), update (campaign_id, is_featured)
  on public.promotions to authenticated;

create table public.campaign_acceptances (
  campaign_id uuid not null references public.campaigns (id) on delete cascade,
  store_id    uuid not null references public.stores (id) on delete cascade,
  accepted_at timestamptz not null default now(),
  accepted_by uuid references auth.users (id) on delete set null,
  primary key (campaign_id, store_id)
);

comment on table public.campaign_acceptances is
  'Magasins qui ont accepté le planning d''une campagne. Écrit uniquement par campaign_accept / campaign_withdraw.';

create index campaign_acceptances_store_idx on public.campaign_acceptances (store_id);


-- -----------------------------------------------------------------------------
-- 2. Droits (RLS)
-- -----------------------------------------------------------------------------

-- Membre d'un magasin de ce réseau.
create or replace function public.is_network_store_member(p_network_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.stores s
    join public.store_members sm on sm.store_id = s.id
    where s.network_id = p_network_id
      and sm.user_id = (select auth.uid())
  );
$$;

revoke all on function public.is_network_store_member(uuid) from public, anon;
grant execute on function public.is_network_store_member(uuid) to authenticated;

alter table public.campaigns enable row level security;
alter table public.campaign_acceptances enable row level security;

revoke all on public.campaigns from anon, authenticated;
revoke all on public.campaign_acceptances from anon, authenticated;

-- La centrale lit, crée, renomme et supprime ses campagnes. Le statut ne bouge
-- que par les fonctions campaign_spread / campaign_propose.
grant select, delete on public.campaigns to authenticated;
grant insert (network_id, name, starts_on, ends_on) on public.campaigns to authenticated;
grant update (name, starts_on, ends_on) on public.campaigns to authenticated;
grant select on public.campaign_acceptances to authenticated;

create policy campaigns_select_network on public.campaigns
  for select to authenticated
  using (public.is_network_member(network_id));

-- Les magasins du réseau ne voient une campagne qu'une fois proposée.
create policy campaigns_select_stores on public.campaigns
  for select to authenticated
  using (status = 'proposed' and public.is_network_store_member(network_id));

create policy campaigns_insert_network on public.campaigns
  for insert to authenticated
  with check (public.is_network_member(network_id));

create policy campaigns_update_network on public.campaigns
  for update to authenticated
  using (public.is_network_member(network_id))
  with check (public.is_network_member(network_id));

create policy campaigns_delete_network on public.campaigns
  for delete to authenticated
  using (public.is_network_member(network_id));

create policy campaign_acceptances_select on public.campaign_acceptances
  for select to authenticated
  using (
    public.is_store_member(store_id)
    or exists (select 1 from public.campaigns c where c.id = campaign_id and public.is_network_member(c.network_id))
  );


-- Une promo ne rejoint qu'une campagne de la centrale qui l'a créée.
create or replace function public.promotions_campaign_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.campaign_id is not null and not exists (
    select 1 from public.campaigns c
    where c.id = new.campaign_id and c.network_id = new.created_by_network_id
  ) then
    raise exception 'Cette campagne n''appartient pas à votre centrale.' using errcode = 'insufficient_privilege';
  end if;
  return new;
end;
$$;

revoke all on function public.promotions_campaign_guard() from public, anon, authenticated;

create trigger promotions_campaign_guard
  before insert or update of campaign_id on public.promotions
  for each row execute function public.promotions_campaign_guard();


-- -----------------------------------------------------------------------------
-- 3. Répartir (centrale)
-- -----------------------------------------------------------------------------
-- Étale les promos de la campagne sur ses jours de diffusion :
--   • jours : de max(début, demain) à la fin, sans les jours exclus ;
--   • ordre de passage : phares d'abord, par date de début, ou mélangé ;
--   • une promo par jour à tour de rôle, au plus max_per_day par jour, les
--     créneaux pris dans l'ordre (9h, 12h, 18h, 9h…) ;
--   • chaque promo reste dans sa propre période (début ≤ jour, publication < fin) ;
--   • une date imposée (promo obligatoire verrouillée) n'est pas touchée.
-- Si un jour doit dépasser le maximum faute de place, il le dépasse et le
-- résultat le dit (overflow). Heures en heure de Paris.

create or replace function public.campaign_spread(p_campaign_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  c        public.campaigns%rowtype;
  v_set    jsonb;
  v_max    int;
  v_slots  text[];
  v_off    int[];
  v_order  text;
  v_days   date[];
  v_load   int[];
  v_n      int;
  v_k      int := 0;
  v_placed int := 0;
  v_out    int := 0;
  v_over   int := 0;
  r        record;
  v_pick   int;
  v_i      int;
  v_j      int;
  v_from   date;
  v_at     timestamptz;
  v_try    timestamptz;
begin
  select * into c from public.campaigns where id = p_campaign_id;
  if not found then
    raise exception 'Campagne introuvable.' using errcode = 'no_data_found';
  end if;
  if not public.is_network_member(c.network_id) then
    raise exception 'Action réservée à l''équipe de la centrale.' using errcode = 'insufficient_privilege';
  end if;

  select coalesce(n.settings -> 'diffusion', '{}'::jsonb) into v_set from public.networks n where n.id = c.network_id;

  v_max := least(greatest(coalesce(case when jsonb_typeof(v_set -> 'max_per_day') = 'number' then (v_set ->> 'max_per_day')::int end, 6), 1), 24);
  v_slots := array(
    select s from jsonb_array_elements_text(case when jsonb_typeof(v_set -> 'slots') = 'array' then v_set -> 'slots' else '[]'::jsonb end) s
    where s ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' order by s
  );
  if cardinality(v_slots) = 0 then v_slots := array['09:00', '12:00', '18:00']; end if;
  v_off := array(
    select x::int from jsonb_array_elements_text(case when jsonb_typeof(v_set -> 'off_days') = 'array' then v_set -> 'off_days' else '[7]'::jsonb end) x
    where x ~ '^[1-7]$'
  );
  v_order := coalesce(v_set ->> 'order', 'featured');

  v_from := greatest(c.starts_on, (now() at time zone 'Europe/Paris')::date + 1);
  v_days := array(
    select g::date from generate_series(v_from, c.ends_on, interval '1 day') g
    where extract(isodow from g)::int <> all (v_off)
    order by g
  );
  v_n := coalesce(cardinality(v_days), 0);
  if v_n = 0 then
    raise exception 'Aucun jour de diffusion à venir sur cette période. Vérifiez les dates et les jours exclus (Paramètres › Diffusion).';
  end if;
  v_load := array_fill(0, array[v_n]);

  for r in
    select p.id, p.starts_at, p.ends_at
    from public.promotions p
    where p.campaign_id = c.id
      and p.status <> 'archived'
      and p.ends_at > now()
      and not p.publish_at_locked
    order by
      case when v_order = 'featured' and p.is_featured then 0 else 1 end,
      case when v_order = 'mix' then md5(p.id::text) end,
      p.starts_at, p.title, p.id
  loop
    v_pick := null;
    -- 1er passage : le prochain jour à tour de rôle, dans la période de la promo, pas plein.
    -- 2e passage : le jour le moins chargé de sa période (dépassement assumé).
    for v_j in 0 .. v_n - 1 loop
      v_i := ((v_k + v_j) % v_n) + 1;
      v_try := (v_days[v_i] + v_slots[(v_load[v_i] % cardinality(v_slots)) + 1]::time) at time zone 'Europe/Paris';
      if v_days[v_i] >= (r.starts_at at time zone 'Europe/Paris')::date and v_try < r.ends_at and v_load[v_i] < v_max then
        v_pick := v_i; v_at := v_try; exit;
      end if;
    end loop;
    if v_pick is null then
      for v_j in 1 .. v_n loop
        v_try := (v_days[v_j] + v_slots[(v_load[v_j] % cardinality(v_slots)) + 1]::time) at time zone 'Europe/Paris';
        if v_days[v_j] >= (r.starts_at at time zone 'Europe/Paris')::date and v_try < r.ends_at
           and (v_pick is null or v_load[v_j] < v_load[v_pick]) then
          v_pick := v_j; v_at := v_try;
        end if;
      end loop;
      if v_pick is not null then v_over := v_over + 1; end if;
    end if;

    if v_pick is null then
      v_out := v_out + 1;  -- la promo ne croise aucun jour de diffusion : sa date ne bouge pas
      continue;
    end if;

    update public.promotions set publish_at = v_at where id = r.id;
    v_load[v_pick] := v_load[v_pick] + 1;
    v_k := v_k + 1;
    v_placed := v_placed + 1;
  end loop;

  update public.campaigns set spread_at = now() where id = c.id;

  return jsonb_build_object(
    'placed', v_placed, 'unplaced', v_out, 'overflow', v_over,
    'days', v_n, 'max_per_day', v_max,
    'busiest', (select coalesce(max(x), 0) from unnest(v_load) x)
  );
end;
$$;

revoke all on function public.campaign_spread(uuid) from public, anon;
grant execute on function public.campaign_spread(uuid) to authenticated;


-- -----------------------------------------------------------------------------
-- 4. Proposer aux magasins (centrale)
-- -----------------------------------------------------------------------------
-- Envoie chaque promo de la campagne à tous les magasins du réseau (send_promotion)
-- et marque la campagne « proposée ». Rejouable : ajoute les promos et les
-- magasins arrivés depuis, sans doublon.

create or replace function public.campaign_propose(p_campaign_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  c       public.campaigns%rowtype;
  r       record;
  v_n     int := 0;
  v_sent  int := 0;
begin
  select * into c from public.campaigns where id = p_campaign_id;
  if not found then
    raise exception 'Campagne introuvable.' using errcode = 'no_data_found';
  end if;
  if not public.is_network_member(c.network_id) then
    raise exception 'Action réservée à l''équipe de la centrale.' using errcode = 'insufficient_privilege';
  end if;
  if not exists (select 1 from public.promotions where campaign_id = c.id and status <> 'archived') then
    raise exception 'Ajoutez d''abord des promos à la campagne.';
  end if;
  if exists (select 1 from public.promotions where campaign_id = c.id and status <> 'archived' and ends_at > now() and publish_at is null) then
    raise exception 'Cliquez d''abord sur « Répartir » : certaines promos n''ont pas de date de publication.';
  end if;

  for r in select id from public.promotions where campaign_id = c.id and status <> 'archived' and ends_at > now() loop
    v_sent := v_sent + public.send_promotion(r.id, null);
    v_n := v_n + 1;
  end loop;

  update public.campaigns
  set status = 'proposed', proposed_at = coalesce(proposed_at, now())
  where id = c.id;

  return jsonb_build_object('promos', v_n, 'new_activations', v_sent,
    'stores', (select count(*) from public.stores where network_id = c.network_id));
end;
$$;

revoke all on function public.campaign_propose(uuid) from public, anon;
grant execute on function public.campaign_propose(uuid) to authenticated;


-- -----------------------------------------------------------------------------
-- 5. Accepter le planning / revenir dessus (magasin)
-- -----------------------------------------------------------------------------
-- Programme d'un geste chaque promo de la campagne à la date proposée, sur les
-- réseaux connectés du magasin (Facebook, Instagram), via schedule_publication
-- (ou demo_publish en démonstration). Une promo déjà programmée ou publiée par
-- le magasin garde sa date : c'est son ajustement. Une promo qui échoue (date
-- passée, promo refusée…) est comptée et sautée, sans bloquer les autres.

create or replace function public.campaign_accept(p_campaign_id uuid, p_store_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  c        public.campaigns%rowtype;
  v_demo   boolean;
  v_ch     text[];
  r        record;
  v_ok     int := 0;
  v_skip   int := 0;
  v_kept   int := 0;
begin
  select * into c from public.campaigns where id = p_campaign_id;
  if not found or c.status <> 'proposed' then
    raise exception 'Cette campagne n''est pas proposée.' using errcode = 'no_data_found';
  end if;
  if not public.is_store_member(p_store_id) then
    raise exception 'Action réservée aux membres du magasin.' using errcode = 'insufficient_privilege';
  end if;
  if not exists (select 1 from public.stores where id = p_store_id and network_id = c.network_id) then
    raise exception 'Ce magasin ne fait pas partie de ce réseau.' using errcode = 'insufficient_privilege';
  end if;

  v_demo := public.is_demo_store(p_store_id);
  v_ch := array(
    select a.channel::text from public.social_accounts a
    where a.store_id = p_store_id and a.status = 'active' and a.enabled
      and a.channel::text in ('facebook', 'instagram')
    order by 1
  );
  if cardinality(v_ch) = 0 then
    raise exception 'Connectez d''abord Facebook ou Instagram (onglet Magasin).';
  end if;

  for r in
    select sp.id as sp_id, p.publish_at,
           exists (select 1 from public.publications pu
                   where pu.store_promotion_id = sp.id
                     and (pu.status in ('scheduled', 'published')
                          or (pu.status = 'pending' and pu.published_at > now()))) as taken
    from public.store_promotions sp
    join public.promotions p on p.id = sp.promotion_id
    where p.campaign_id = c.id
      and sp.store_id = p_store_id
      and not sp.hidden and not sp.suspended and sp.status <> 'declined'
      and p.status not in ('draft', 'archived')
    order by p.publish_at
  loop
    if r.taken then v_kept := v_kept + 1; continue; end if;
    if r.publish_at is null or r.publish_at <= now() + interval '1 minute' then v_skip := v_skip + 1; continue; end if;
    begin
      if v_demo then
        perform public.demo_publish(r.sp_id, v_ch, r.publish_at);
      else
        perform public.schedule_publication(r.sp_id, v_ch, r.publish_at);
      end if;
      v_ok := v_ok + 1;
    exception when others then
      v_skip := v_skip + 1;
    end;
  end loop;

  insert into public.campaign_acceptances (campaign_id, store_id, accepted_by)
  values (c.id, p_store_id, auth.uid())
  on conflict (campaign_id, store_id) do update set accepted_at = now(), accepted_by = excluded.accepted_by;

  return jsonb_build_object('scheduled', v_ok, 'kept', v_kept, 'skipped', v_skip);
end;
$$;

revoke all on function public.campaign_accept(uuid, uuid) from public, anon;
grant execute on function public.campaign_accept(uuid, uuid) to authenticated;


-- Annuler l'acceptation : déprogramme ce qui n'est pas encore parti.
create or replace function public.campaign_withdraw(p_campaign_id uuid, p_store_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_n int;
begin
  if not public.is_store_member(p_store_id) then
    raise exception 'Action réservée aux membres du magasin.' using errcode = 'insufficient_privilege';
  end if;

  delete from public.publications pu
  using public.store_promotions sp, public.promotions p
  where sp.id = pu.store_promotion_id
    and p.id = sp.promotion_id
    and p.campaign_id = p_campaign_id
    and sp.store_id = p_store_id
    and (pu.status = 'scheduled' or (pu.status = 'pending' and pu.published_at > now() and public.is_demo_store(p_store_id)));
  get diagnostics v_n = row_count;

  delete from public.campaign_acceptances where campaign_id = p_campaign_id and store_id = p_store_id;
  return v_n;
end;
$$;

revoke all on function public.campaign_withdraw(uuid, uuid) from public, anon;
grant execute on function public.campaign_withdraw(uuid, uuid) to authenticated;


-- -----------------------------------------------------------------------------
-- 6. Suivi (centrale) : qui a accepté, qui a ajusté, qui n'a pas répondu
-- -----------------------------------------------------------------------------
-- Ajusté : au moins une publication de la campagne à une autre date que celle
-- proposée (à la minute près). Programmer sans passer par « Accepter » compte
-- aussi comme une réponse.

create or replace function public.campaign_tracking(p_campaign_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  c public.campaigns%rowtype;
begin
  select * into c from public.campaigns where id = p_campaign_id;
  if not found then
    raise exception 'Campagne introuvable.' using errcode = 'no_data_found';
  end if;
  if not public.is_network_member(c.network_id) then
    raise exception 'Action réservée à l''équipe de la centrale.' using errcode = 'insufficient_privilege';
  end if;

  return (
    with st as (
      select s.id, s.name, s.city,
             exists (select 1 from public.social_accounts a where a.store_id = s.id and a.status = 'active' and a.enabled
                       and a.channel::text in ('facebook', 'instagram')) as connected,
             (select ca.accepted_at from public.campaign_acceptances ca where ca.campaign_id = c.id and ca.store_id = s.id) as accepted_at,
             (select count(*) from public.store_promotions sp join public.promotions p on p.id = sp.promotion_id
               where p.campaign_id = c.id and sp.store_id = s.id) as total,
             (select count(distinct sp.id) from public.store_promotions sp
               join public.promotions p on p.id = sp.promotion_id
               join public.publications pu on pu.store_promotion_id = sp.id
               where p.campaign_id = c.id and sp.store_id = s.id
                 and (pu.status in ('scheduled', 'published') or (pu.status = 'pending' and pu.published_at > now()))) as planned,
             (select count(distinct sp.id) from public.store_promotions sp
               join public.promotions p on p.id = sp.promotion_id
               join public.publications pu on pu.store_promotion_id = sp.id
               where p.campaign_id = c.id and sp.store_id = s.id and p.publish_at is not null
                 and date_trunc('minute', coalesce(pu.scheduled_at, case when pu.status = 'pending' then pu.published_at end))
                     is distinct from date_trunc('minute', p.publish_at)
                 and coalesce(pu.scheduled_at, case when pu.status = 'pending' then pu.published_at end) is not null) as moved
      from public.stores s
      where s.network_id = c.network_id
    ),
    lab as (
      select st.*,
             case when moved > 0 then 'adjusted'
                  when accepted_at is not null or (planned > 0 and planned >= total) then 'accepted'
                  else 'pending' end as state
      from st
    )
    select jsonb_build_object(
      'accepted', count(*) filter (where state = 'accepted'),
      'adjusted', count(*) filter (where state = 'adjusted'),
      'pending',  count(*) filter (where state = 'pending'),
      'stores', coalesce(jsonb_agg(jsonb_build_object(
          'id', id, 'name', name, 'city', city, 'state', state, 'connected', connected,
          'total', total, 'planned', planned, 'moved', moved, 'accepted_at', accepted_at)
        order by case state when 'pending' then 0 when 'adjusted' then 1 else 2 end, name), '[]'::jsonb)
    )
    from lab
  );
end;
$$;

revoke all on function public.campaign_tracking(uuid) from public, anon;
grant execute on function public.campaign_tracking(uuid) to authenticated;


-- -----------------------------------------------------------------------------
-- 7. La centrale déplace une date : les programmations suivent
-- -----------------------------------------------------------------------------
-- Remplace la version MOD-082. Deux cas :
--   • date imposée (promo obligatoire verrouillée) : toutes les programmations suivent ;
--   • promo de campagne : suivent les magasins qui ont accepté le planning, et
--     seulement les publications restées à la date proposée (un ajustement du
--     magasin n'est jamais écrasé).

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
  elsif new.campaign_id is not null
     and old.publish_at is not null
     and new.publish_at is not null
     and new.publish_at is distinct from old.publish_at
     and new.publish_at > now() + interval '1 minute' then
    update public.publications pu
    set scheduled_at = new.publish_at
    from public.store_promotions sp
    where sp.id = pu.store_promotion_id
      and sp.promotion_id = new.id
      and pu.status = 'scheduled'
      and date_trunc('minute', pu.scheduled_at) = date_trunc('minute', old.publish_at)
      and exists (select 1 from public.campaign_acceptances ca
                  where ca.campaign_id = new.campaign_id and ca.store_id = sp.store_id);
  end if;
  return new;
end;
$$;

revoke all on function public.promotions_sync_imposed_publish_at() from public, anon, authenticated;
