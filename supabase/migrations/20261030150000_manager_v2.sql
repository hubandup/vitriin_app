-- Manager V2 : tableau de bord, fiches clients, magasins, santé, visites du site.
-- Toutes les fonctions manager_* vérifient is_platform_admin() côté serveur.

-- ---------------------------------------------------------------------------
-- Visites de vitriin.fr : sans cookie, sans IP. Un identifiant de visiteur
-- aléatoire tiré par le navigateur (renouvelé chaque jour) sert seulement à
-- compter les visiteurs uniques.
-- ---------------------------------------------------------------------------
create table if not exists public.site_visits (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  site text not null default 'vitriin.fr',
  event text not null default 'view' check (event in ('view', 'demo_click', 'signup_click')),
  path text not null,
  referrer_host text,
  source text,
  device text check (device in ('mobile', 'tablet', 'desktop')),
  visitor text
);
create index if not exists site_visits_at_idx on public.site_visits (at desc);
alter table public.site_visits enable row level security;
revoke all on public.site_visits from anon, authenticated;

-- Seule porte d'entrée publique : valeurs bornées, débit limité par visiteur.
create or replace function public.track_visit(p_path text, p_ref text default null, p_source text default null,
  p_device text default null, p_visitor text default null, p_event text default 'view', p_site text default 'vitriin.fr')
returns void language plpgsql security definer set search_path to '' as $$
declare v_vis text := left(nullif(regexp_replace(coalesce(p_visitor, ''), '[^a-zA-Z0-9-]', '', 'g'), ''), 40);
begin
  if p_event not in ('view', 'demo_click', 'signup_click') then return; end if;
  if p_site not in ('vitriin.fr', 'www.vitriin.fr') then return; end if;
  if v_vis is not null and (select count(*) from public.site_visits
      where visitor = v_vis and at > now() - interval '1 minute') >= 30 then return; end if;
  insert into public.site_visits (site, event, path, referrer_host, source, device, visitor)
  values ('vitriin.fr', p_event,
    left(coalesce(nullif(split_part(split_part(p_path, '?', 1), '#', 1), ''), '/'), 200),
    left(nullif(lower(regexp_replace(coalesce(p_ref, ''), '^www\.', '')), ''), 100),
    left(nullif(lower(coalesce(p_source, '')), ''), 60),
    case when p_device in ('mobile', 'tablet', 'desktop') then p_device end,
    v_vis);
end;
$$;
revoke all on function public.track_visit(text, text, text, text, text, text, text) from public;
grant execute on function public.track_visit(text, text, text, text, text, text, text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Périmètre : magasins des centrales clientes + indépendants, démos en option.
-- ---------------------------------------------------------------------------
create or replace function public.manager_scope_stores(p_demo boolean)
returns table (store_id uuid) language sql stable security definer set search_path to '' as $$
  select s.id from public.stores s left join public.networks n on n.id = s.network_id
  where p_demo or not coalesce(n.is_demo, false);
$$;
revoke all on function public.manager_scope_stores(boolean) from public, anon, authenticated;

create or replace function public.manager_guard()
returns void language plpgsql stable security definer set search_path to '' as $$
begin
  if not public.is_platform_admin() then raise exception 'Accès réservé à l''équipe Vitriin.' using errcode = '42501'; end if;
end;
$$;
revoke all on function public.manager_guard() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Accueil : chiffres globaux, courbe 30 jours, « À traiter ».
-- ---------------------------------------------------------------------------
create or replace function public.manager_dashboard(p_demo boolean default false)
returns jsonb language plpgsql stable security definer set search_path to '' as $$
declare r jsonb;
begin
  perform public.manager_guard();
  with sc as (select store_id from public.manager_scope_stores(p_demo)),
  pubs as (
    select pu.*, sp.store_id from public.publications pu
    join public.store_promotions sp on sp.id = pu.store_promotion_id
    where sp.store_id in (select store_id from sc)),
  days as (select generate_series(date_trunc('day', now()) - interval '29 days', date_trunc('day', now()), interval '1 day')::date d)
  select jsonb_build_object(
    'networks', (select count(*) from public.networks n where p_demo or not n.is_demo),
    'stores', (select count(*) from sc),
    'independent', (select count(*) from public.stores s where s.network_id is null),
    'connected', (select count(distinct a.store_id) from public.social_accounts a where a.status = 'active' and a.enabled and a.store_id in (select store_id from sc)),
    'activated', (select count(distinct m.store_id) from public.store_members m where m.store_id in (select store_id from sc)),
    'pub7', (select count(*) from pubs where status = 'published' and published_at > now() - interval '7 days'),
    'pub30', (select count(*) from pubs where status = 'published' and published_at > now() - interval '30 days'),
    'pubPrev30', (select count(*) from pubs where status = 'published' and published_at between now() - interval '60 days' and now() - interval '30 days'),
    'reach30', (select coalesce(sum((metrics->>'reach')::numeric), 0) from pubs where status = 'published' and published_at > now() - interval '30 days'),
    'views30', (select coalesce(sum((metrics->>'views')::numeric), 0) from pubs where status = 'published' and published_at > now() - interval '30 days'),
    'codes30', (select count(*) from public.code_reveals c where c.store_id in (select store_id from sc) and c.revealed_at > now() - interval '30 days'),
    'fail7', (select count(*) from pubs where status = 'failed' and created_at > now() - interval '7 days'),
    'visits30', (select count(*) from public.site_visits where event = 'view' and at > now() - interval '30 days'),
    'series', (select jsonb_agg(jsonb_build_object('d', d,
        'pub', (select count(*) from pubs where status = 'published' and published_at::date = d),
        'visits', (select count(*) from public.site_visits v where v.event = 'view' and v.at::date = d)) order by d) from days),
    'todo', jsonb_build_object(
      'accounts', coalesce((select jsonb_agg(x) from (
        select a.channel, a.status, a.last_error, s.id store_id, s.name store, n.name network
        from public.social_accounts a join public.stores s on s.id = a.store_id left join public.networks n on n.id = s.network_id
        where a.status <> 'active' and a.store_id in (select store_id from sc) order by s.name limit 50) x), '[]'),
      'failures', coalesce((select jsonb_agg(x) from (
        select p.channel, p.error_message, p.created_at, s.name store, n.name network, pr.title promo
        from pubs p join public.stores s on s.id = p.store_id left join public.networks n on n.id = s.network_id
        join public.store_promotions sp on sp.id = p.store_promotion_id join public.promotions pr on pr.id = sp.promotion_id
        where p.status = 'failed' and p.created_at > now() - interval '7 days' order by p.created_at desc limit 50) x), '[]'),
      'invites', coalesce((select jsonb_agg(x) from (
        select s.id store_id, s.name store, n.name network, s.contact_email, s.invited_at
        from public.stores s left join public.networks n on n.id = s.network_id
        where s.id in (select store_id from sc) and s.invited_at < now() - interval '3 days'
          and not exists (select 1 from public.social_accounts a where a.store_id = s.id)
        order by s.invited_at limit 50) x), '[]'),
      'idle', coalesce((select jsonb_agg(x) from (
        select n.id, n.name, max(u.last_sign_in_at) last_seen
        from public.networks n join public.network_members m on m.network_id = n.id join auth.users u on u.id = m.user_id
        where (p_demo or not n.is_demo)
        group by n.id, n.name having coalesce(max(u.last_sign_in_at), 'epoch') < now() - interval '15 days') x), '[]'))
  ) into r;
  return r;
end;
$$;
revoke all on function public.manager_dashboard(boolean) from public, anon;
grant execute on function public.manager_dashboard(boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- Fiche client.
-- ---------------------------------------------------------------------------
create or replace function public.manager_network(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path to '' as $$
declare r jsonb;
begin
  perform public.manager_guard();
  select jsonb_build_object(
    'network', (select to_jsonb(x) from (select id, name, is_demo, demo_sector, logo_url, legal_name, address, support_email, phone,
                 siret, created_at, join_code, settings from public.networks where id = p_id) x),
    'members', coalesce((select jsonb_agg(x order by x.role, x.email) from (
        select u.email, m.role, u.last_sign_in_at, m.created_at from public.network_members m join auth.users u on u.id = m.user_id
        where m.network_id = p_id) x), '[]'),
    'stores', coalesce((select jsonb_agg(x order by x.name) from (
        select s.id, s.name, s.city, s.postal_code, s.contact_email, s.invited_at, s.created_at,
          exists (select 1 from public.store_members sm where sm.store_id = s.id) activated,
          (select max(u.last_sign_in_at) from public.store_members sm join auth.users u on u.id = sm.user_id where sm.store_id = s.id) last_seen,
          (select jsonb_object_agg(a.channel, case when not a.enabled then 'off' else a.status::text end) from public.social_accounts a where a.store_id = s.id) channels,
          (select count(*) from public.publications pu join public.store_promotions sp on sp.id = pu.store_promotion_id
             where sp.store_id = s.id and pu.status = 'published' and pu.published_at > now() - interval '30 days') pub30,
          (select count(*) from public.store_promotions sp where sp.store_id = s.id and sp.status = 'pending') pending
        from public.stores s where s.network_id = p_id) x), '[]'),
    'promos', coalesce((select jsonb_agg(x order by x.starts_at desc) from (
        select p.id, p.title, p.starts_at, p.ends_at, p.is_mandatory, p.status,
          (select count(*) from public.store_promotions sp where sp.promotion_id = p.id) sent,
          (select count(*) from public.store_promotions sp where sp.promotion_id = p.id and sp.status = 'active') active,
          (select count(distinct sp.store_id) from public.store_promotions sp join public.publications pu on pu.store_promotion_id = sp.id
             where sp.promotion_id = p.id and pu.status = 'published') relayed,
          (select coalesce(sum((pu.metrics->>'views')::numeric), 0) from public.store_promotions sp join public.publications pu on pu.store_promotion_id = sp.id
             where sp.promotion_id = p.id) views
        from public.promotions p where p.created_by_network_id = p_id limit 100) x), '[]')
  ) into r;
  if r->'network' is null or r->'network' = 'null'::jsonb then raise exception 'Centrale introuvable.'; end if;
  return r;
end;
$$;
revoke all on function public.manager_network(uuid) from public, anon;
grant execute on function public.manager_network(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Tous les magasins.
-- ---------------------------------------------------------------------------
create or replace function public.manager_stores(p_demo boolean default false)
returns jsonb language plpgsql stable security definer set search_path to '' as $$
begin
  perform public.manager_guard();
  return coalesce((select jsonb_agg(x order by x.network nulls first, x.name) from (
    select s.id, s.name, s.city, s.postal_code, s.contact_email, s.invited_at, s.created_at, n.id network_id, n.name network,
      exists (select 1 from public.store_members sm where sm.store_id = s.id) activated,
      (select u.email from public.store_members sm join auth.users u on u.id = sm.user_id where sm.store_id = s.id order by sm.created_at limit 1) owner,
      (select max(u.last_sign_in_at) from public.store_members sm join auth.users u on u.id = sm.user_id where sm.store_id = s.id) last_seen,
      (select jsonb_object_agg(a.channel, case when not a.enabled then 'off' else a.status::text end) from public.social_accounts a where a.store_id = s.id) channels,
      (select max(pu.published_at) from public.publications pu join public.store_promotions sp on sp.id = pu.store_promotion_id
         where sp.store_id = s.id and pu.status = 'published') last_pub
    from public.stores s left join public.networks n on n.id = s.network_id
    where s.id in (select store_id from public.manager_scope_stores(p_demo)) limit 3000) x), '[]');
end;
$$;
revoke all on function public.manager_stores(boolean) from public, anon;
grant execute on function public.manager_stores(boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- Santé technique : échecs par cause, comptes, tâches de fond.
-- ---------------------------------------------------------------------------
create or replace function public.manager_health(p_demo boolean default false)
returns jsonb language plpgsql stable security definer set search_path to '' as $$
begin
  perform public.manager_guard();
  return jsonb_build_object(
    'failByCause', coalesce((select jsonb_agg(x order by x.n desc) from (
        select pu.channel, coalesce(left(pu.error_message, 140), 'Cause inconnue') cause, count(*) n, max(pu.created_at) last
        from public.publications pu join public.store_promotions sp on sp.id = pu.store_promotion_id
        where pu.status = 'failed' and pu.created_at > now() - interval '30 days'
          and sp.store_id in (select store_id from public.manager_scope_stores(p_demo))
        group by 1, 2 limit 30) x), '[]'),
    'accounts', (select jsonb_object_agg(k, n) from (
        select case when not a.enabled then 'off' else a.status::text end k, count(*) n from public.social_accounts a
        where a.store_id in (select store_id from public.manager_scope_stores(p_demo)) group by 1) x),
    'pubStatus', (select jsonb_object_agg(k, n) from (
        select pu.status::text k, count(*) n from public.publications pu join public.store_promotions sp on sp.id = pu.store_promotion_id
        where pu.created_at > now() - interval '30 days' and sp.store_id in (select store_id from public.manager_scope_stores(p_demo)) group by 1) x),
    'users', jsonb_build_object(
        'total', (select count(*) from auth.users),
        'unconfirmed', (select count(*) from auth.users where email_confirmed_at is null),
        'invitedPending', (select count(*) from auth.users where invited_at is not null and last_sign_in_at is null)),
    'lastMetrics', (select max(metrics_fetched_at) from public.publications pu join public.store_promotions sp on sp.id = pu.store_promotion_id
        where pu.metrics->>'demo' is null)
  );
end;
$$;
revoke all on function public.manager_health(boolean) from public, anon;
grant execute on function public.manager_health(boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- Visites du site.
-- ---------------------------------------------------------------------------
create or replace function public.manager_site(p_days int default 30)
returns jsonb language plpgsql stable security definer set search_path to '' as $$
declare v_from timestamptz := now() - make_interval(days => least(greatest(p_days, 1), 365));
begin
  perform public.manager_guard();
  return jsonb_build_object(
    'views', (select count(*) from public.site_visits where event = 'view' and at > v_from),
    'visitors', (select count(distinct visitor) from public.site_visits where event = 'view' and at > v_from),
    'demo', (select count(*) from public.site_visits where event = 'demo_click' and at > v_from),
    'signup', (select count(*) from public.site_visits where event = 'signup_click' and at > v_from),
    'pages', coalesce((select jsonb_agg(x order by x.n desc) from (select path, count(*) n from public.site_visits
        where event = 'view' and at > v_from group by 1 order by 2 desc limit 15) x), '[]'),
    'sources', coalesce((select jsonb_agg(x order by x.n desc) from (select coalesce(source, referrer_host, 'Accès direct') src, count(*) n
        from public.site_visits where event = 'view' and at > v_from group by 1 order by 2 desc limit 15) x), '[]'),
    'devices', (select jsonb_object_agg(coalesce(device, 'inconnu'), n) from (select device, count(*) n from public.site_visits
        where event = 'view' and at > v_from group by 1) x),
    'series', (select jsonb_agg(jsonb_build_object('d', d::date, 'n', (select count(*) from public.site_visits v where v.event = 'view' and v.at::date = d::date)) order by d)
        from generate_series(v_from::date, now()::date, interval '1 day') d),
    'last', (select max(at) from public.site_visits)
  );
end;
$$;
revoke all on function public.manager_site(int) from public, anon;
grant execute on function public.manager_site(int) to authenticated;
