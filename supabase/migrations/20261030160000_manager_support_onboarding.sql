-- Manager : « À traiter » marquable comme lu, tickets de support, checklist d'intégration.
-- Tables sans policy : tout passe par des fonctions SECURITY DEFINER qui vérifient
-- les droits côté serveur (is_platform_admin pour l'équipe Vitriin, appartenance
-- au magasin ou à la centrale pour les clients).

-- ---------------------------------------------------------------------------
-- 1. « À traiter » : éléments marqués comme lus.
-- ---------------------------------------------------------------------------
create table if not exists public.manager_dismissed (
  key text primary key,
  dismissed_at timestamptz not null default now(),
  dismissed_by uuid references public.profiles(id) on delete set null
);
alter table public.manager_dismissed enable row level security;
revoke all on public.manager_dismissed from anon, authenticated;

create or replace function public.manager_dismiss(p_keys text[], p_undo boolean default false)
returns int language plpgsql security definer set search_path to '' as $$
declare n int;
begin
  perform public.manager_guard();
  if coalesce(array_length(p_keys, 1), 0) = 0 or array_length(p_keys, 1) > 500 then return 0; end if;
  if p_undo then
    delete from public.manager_dismissed where key = any (p_keys);
  else
    insert into public.manager_dismissed (key, dismissed_by)
    select left(k, 200), (select auth.uid()) from unnest(p_keys) k
    on conflict (key) do nothing;
  end if;
  get diagnostics n = row_count;
  return n;
end;
$$;
revoke all on function public.manager_dismiss(text[], boolean) from public, anon;
grant execute on function public.manager_dismiss(text[], boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Tickets de support.
-- ---------------------------------------------------------------------------
create table if not exists public.support_tickets (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  status text not null default 'new' check (status in ('new', 'open', 'waiting', 'resolved')),
  priority text not null default 'normal' check (priority in ('normal', 'high')),
  topic text not null default 'other' check (topic in ('social', 'publication', 'promo', 'account', 'billing', 'other')),
  subject text not null check (length(subject) between 3 and 140),
  source text not null check (source in ('magasin', 'centrale')),
  store_id uuid references public.stores(id) on delete set null,
  network_id uuid references public.networks(id) on delete set null,
  created_by uuid references public.profiles(id) on delete set null,
  created_by_email text,
  context jsonb not null default '{}',
  client_seen_at timestamptz,
  staff_seen_at timestamptz,
  last_client_at timestamptz,
  last_staff_at timestamptz
);
create index if not exists support_tickets_status_idx on public.support_tickets (status, updated_at desc);
create index if not exists support_tickets_creator_idx on public.support_tickets (created_by);

create table if not exists public.support_messages (
  id bigint generated always as identity primary key,
  ticket_id uuid not null references public.support_tickets(id) on delete cascade,
  created_at timestamptz not null default now(),
  author uuid references public.profiles(id) on delete set null,
  author_kind text not null check (author_kind in ('client', 'staff')),
  body text not null check (length(body) between 1 and 5000),
  internal boolean not null default false
);
create index if not exists support_messages_ticket_idx on public.support_messages (ticket_id, created_at);

alter table public.support_tickets enable row level security;
alter table public.support_messages enable row level security;
revoke all on public.support_tickets, public.support_messages from anon, authenticated;

-- Photographie de la situation au moment de la demande : comptes, dernier échec.
create or replace function public.support_snapshot(p_store uuid, p_network uuid)
returns jsonb language sql stable security definer set search_path to '' as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'store', (select jsonb_build_object('name', s.name, 'city', s.city, 'contact_email', s.contact_email) from public.stores s where s.id = p_store),
    'network', (select n.name from public.networks n where n.id = coalesce(p_network, (select network_id from public.stores where id = p_store))),
    'channels', (select jsonb_object_agg(a.channel, jsonb_build_object('status', case when not a.enabled then 'off' else a.status::text end,
                   'name', a.display_name, 'error', a.last_error)) from public.social_accounts a where a.store_id = p_store),
    'lastFailure', (select jsonb_build_object('channel', pu.channel, 'error', pu.error_message, 'at', pu.created_at, 'promo', pr.title)
                    from public.publications pu join public.store_promotions sp on sp.id = pu.store_promotion_id
                    join public.promotions pr on pr.id = sp.promotion_id
                    where sp.store_id = p_store and pu.status = 'failed' order by pu.created_at desc limit 1),
    'stores', (select count(*) from public.stores s where s.network_id = p_network)
  ));
$$;
revoke all on function public.support_snapshot(uuid, uuid) from public, anon, authenticated;

-- Côté client : créer une demande (magasin ou centrale dont on est membre).
create or replace function public.support_create(p_subject text, p_body text, p_topic text default 'other',
  p_store_id uuid default null, p_network_id uuid default null, p_client jsonb default '{}')
returns uuid language plpgsql security definer set search_path to '' as $$
declare v_me uuid := (select auth.uid()); v_id uuid; v_src text;
begin
  if v_me is null then raise exception 'Connexion requise.' using errcode = '42501'; end if;
  if p_store_id is not null then
    if not public.is_store_member(p_store_id) then raise exception 'Magasin inconnu.' using errcode = '42501'; end if;
    v_src := 'magasin';
  elsif p_network_id is not null then
    if not public.is_network_member(p_network_id) then raise exception 'Centrale inconnue.' using errcode = '42501'; end if;
    v_src := 'centrale';
  else
    raise exception 'Précisez le magasin ou la centrale.';
  end if;
  if length(btrim(coalesce(p_body, ''))) < 5 then raise exception 'Décrivez le problème en quelques mots.'; end if;
  -- Garde-fou : 10 demandes par heure et par personne.
  if (select count(*) from public.support_tickets where created_by = v_me and created_at > now() - interval '1 hour') >= 10 then
    raise exception 'Trop de demandes en peu de temps. Réessayez dans un moment.';
  end if;
  insert into public.support_tickets (subject, topic, source, store_id, network_id, created_by, created_by_email, context, last_client_at, client_seen_at)
  values (left(btrim(coalesce(nullif(p_subject, ''), 'Demande de support')), 140),
    case when p_topic in ('social', 'publication', 'promo', 'account', 'billing', 'other') then p_topic else 'other' end,
    v_src, p_store_id,
    coalesce(p_network_id, (select network_id from public.stores where id = p_store_id)),
    v_me, (select email from auth.users where id = v_me),
    public.support_snapshot(p_store_id, coalesce(p_network_id, (select network_id from public.stores where id = p_store_id)))
      || jsonb_build_object('client', jsonb_build_object('ua', left(coalesce(p_client->>'ua', ''), 300), 'app', left(coalesce(p_client->>'app', ''), 40))),
    now(), now())
  returning id into v_id;
  insert into public.support_messages (ticket_id, author, author_kind, body) values (v_id, v_me, 'client', left(btrim(p_body), 5000));
  return v_id;
end;
$$;
revoke all on function public.support_create(text, text, text, uuid, uuid, jsonb) from public, anon;
grant execute on function public.support_create(text, text, text, uuid, uuid, jsonb) to authenticated;

-- Côté client : mes demandes (sans les notes internes).
create or replace function public.support_mine()
returns jsonb language sql stable security definer set search_path to '' as $$
  select coalesce(jsonb_agg(x order by x.updated_at desc), '[]') from (
    select t.id, t.subject, t.topic, t.status, t.created_at, t.updated_at,
      (t.last_staff_at is not null and t.last_staff_at > coalesce(t.client_seen_at, 'epoch')) as unread
    from public.support_tickets t where t.created_by = (select auth.uid()) limit 100) x;
$$;
revoke all on function public.support_mine() from public, anon;
grant execute on function public.support_mine() to authenticated;

create or replace function public.support_thread(p_id uuid)
returns jsonb language plpgsql security definer set search_path to '' as $$
declare r jsonb;
begin
  if not exists (select 1 from public.support_tickets where id = p_id and created_by = (select auth.uid())) then
    raise exception 'Demande introuvable.' using errcode = '42501';
  end if;
  update public.support_tickets set client_seen_at = now() where id = p_id;
  select jsonb_build_object('ticket', (select to_jsonb(x) from (select id, subject, topic, status, created_at from public.support_tickets where id = p_id) x),
    'messages', coalesce((select jsonb_agg(jsonb_build_object('at', m.created_at, 'kind', m.author_kind, 'body', m.body) order by m.created_at)
      from public.support_messages m where m.ticket_id = p_id and not m.internal), '[]')) into r;
  return r;
end;
$$;
revoke all on function public.support_thread(uuid) from public, anon;
grant execute on function public.support_thread(uuid) to authenticated;

create or replace function public.support_reply(p_id uuid, p_body text)
returns void language plpgsql security definer set search_path to '' as $$
declare v_me uuid := (select auth.uid());
begin
  if not exists (select 1 from public.support_tickets where id = p_id and created_by = v_me) then
    raise exception 'Demande introuvable.' using errcode = '42501';
  end if;
  if length(btrim(coalesce(p_body, ''))) < 1 then raise exception 'Message vide.'; end if;
  if (select count(*) from public.support_messages where author = v_me and created_at > now() - interval '1 hour') >= 40 then
    raise exception 'Trop de messages en peu de temps.';
  end if;
  insert into public.support_messages (ticket_id, author, author_kind, body) values (p_id, v_me, 'client', left(btrim(p_body), 5000));
  update public.support_tickets set last_client_at = now(), client_seen_at = now(), updated_at = now(),
    status = case when status in ('waiting', 'resolved') then 'open' else status end where id = p_id;
end;
$$;
revoke all on function public.support_reply(uuid, text) from public, anon;
grant execute on function public.support_reply(uuid, text) to authenticated;

-- Côté équipe Vitriin.
create or replace function public.manager_tickets(p_status text default 'active')
returns jsonb language plpgsql stable security definer set search_path to '' as $$
begin
  perform public.manager_guard();
  return coalesce((select jsonb_agg(x order by x.priority desc, x.updated_at desc) from (
    select t.id, t.subject, t.topic, t.status, t.priority, t.source, t.created_at, t.updated_at, t.created_by_email,
      s.name store, n.name network, t.network_id,
      (t.status = 'new' or (t.last_client_at is not null and t.last_client_at > coalesce(t.staff_seen_at, 'epoch'))) unread,
      (select count(*) from public.support_messages m where m.ticket_id = t.id and not m.internal) messages
    from public.support_tickets t left join public.stores s on s.id = t.store_id left join public.networks n on n.id = t.network_id
    where case p_status when 'active' then t.status <> 'resolved' when 'all' then true else t.status = p_status end
    limit 500) x), '[]');
end;
$$;
revoke all on function public.manager_tickets(text) from public, anon;
grant execute on function public.manager_tickets(text) to authenticated;

create or replace function public.manager_ticket(p_id uuid)
returns jsonb language plpgsql security definer set search_path to '' as $$
declare r jsonb; t public.support_tickets;
begin
  perform public.manager_guard();
  select * into t from public.support_tickets where id = p_id;
  if t.id is null then raise exception 'Ticket introuvable.'; end if;
  update public.support_tickets set staff_seen_at = now(), status = case when status = 'new' then 'open' else status end where id = p_id;
  select jsonb_build_object(
    'ticket', (select to_jsonb(x) from (select tt.*, s.name store, n.name network from public.support_tickets tt
       left join public.stores s on s.id = tt.store_id left join public.networks n on n.id = tt.network_id where tt.id = p_id) x),
    'now', public.support_snapshot(t.store_id, t.network_id),
    'messages', coalesce((select jsonb_agg(jsonb_build_object('at', m.created_at, 'kind', m.author_kind, 'body', m.body, 'internal', m.internal,
        'author', (select email from auth.users where id = m.author)) order by m.created_at)
      from public.support_messages m where m.ticket_id = p_id), '[]'),
    'others', coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'subject', o.subject, 'status', o.status, 'created_at', o.created_at) order by o.created_at desc)
      from public.support_tickets o where o.id <> p_id and (o.store_id = t.store_id or (t.store_id is null and o.network_id = t.network_id))), '[]')
  ) into r;
  return r;
end;
$$;
revoke all on function public.manager_ticket(uuid) from public, anon;
grant execute on function public.manager_ticket(uuid) to authenticated;

create or replace function public.manager_ticket_reply(p_id uuid, p_body text, p_internal boolean default false, p_status text default null)
returns void language plpgsql security definer set search_path to '' as $$
begin
  perform public.manager_guard();
  if not exists (select 1 from public.support_tickets where id = p_id) then raise exception 'Ticket introuvable.'; end if;
  if length(btrim(coalesce(p_body, ''))) > 0 then
    insert into public.support_messages (ticket_id, author, author_kind, body, internal)
    values (p_id, (select auth.uid()), 'staff', left(btrim(p_body), 5000), p_internal);
  end if;
  update public.support_tickets set updated_at = now(), staff_seen_at = now(),
    last_staff_at = case when length(btrim(coalesce(p_body, ''))) > 0 and not p_internal then now() else last_staff_at end,
    status = case when p_status in ('new', 'open', 'waiting', 'resolved') then p_status
                  when length(btrim(coalesce(p_body, ''))) > 0 and not p_internal then 'waiting' else status end
  where id = p_id;
end;
$$;
revoke all on function public.manager_ticket_reply(uuid, text, boolean, text) from public, anon;
grant execute on function public.manager_ticket_reply(uuid, text, boolean, text) to authenticated;

create or replace function public.manager_ticket_set(p_id uuid, p_status text default null, p_priority text default null)
returns void language plpgsql security definer set search_path to '' as $$
begin
  perform public.manager_guard();
  update public.support_tickets set
    status = case when p_status in ('new', 'open', 'waiting', 'resolved') then p_status else status end,
    priority = case when p_priority in ('normal', 'high') then p_priority else priority end,
    updated_at = now()
  where id = p_id;
end;
$$;
revoke all on function public.manager_ticket_set(uuid, text, text) from public, anon;
grant execute on function public.manager_ticket_set(uuid, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Checklist d'intégration d'une centrale.
-- ---------------------------------------------------------------------------
create table if not exists public.network_onboarding (
  network_id uuid not null references public.networks(id) on delete cascade,
  step text not null check (step in ('contract', 'sepa', 'training_hq', 'training_stores')),
  done_at timestamptz not null default now(),
  done_by uuid references public.profiles(id) on delete set null,
  primary key (network_id, step)
);
alter table public.network_onboarding enable row level security;
revoke all on public.network_onboarding from anon, authenticated;

create or replace function public.network_onboarding_steps(p_net uuid)
returns jsonb language sql stable security definer set search_path to '' as $$
  with st as (select s.id, s.contact_email, s.invited_at,
      exists (select 1 from public.store_members m where m.store_id = s.id) act,
      exists (select 1 from public.social_accounts a where a.store_id = s.id and a.status = 'active' and a.enabled) con
    from public.stores s where s.network_id = p_net),
  k as (select count(*) n, count(*) filter (where act) act, count(*) filter (where con) con,
      count(*) filter (where act or invited_at is not null) inv from st),
  man as (select step, done_at from public.network_onboarding where network_id = p_net)
  select jsonb_build_array(
    jsonb_build_object('k', 'contract', 'l', 'Contrat signé', 'manual', true, 'done', exists (select 1 from man where step = 'contract')),
    jsonb_build_object('k', 'sepa', 'l', 'Mandat SEPA reçu', 'manual', true, 'done', exists (select 1 from man where step = 'sepa')),
    jsonb_build_object('k', 'brand', 'l', 'Logo et coordonnées de l''enseigne', 'done',
      (select logo_url is not null and support_email is not null from public.networks where id = p_net)),
    jsonb_build_object('k', 'training_hq', 'l', 'Formation de l''équipe centrale', 'manual', true, 'done', exists (select 1 from man where step = 'training_hq')),
    jsonb_build_object('k', 'stores', 'l', 'Magasins importés', 'done', (select n > 0 from k), 'info', (select n || ' magasin(s)' from k)),
    jsonb_build_object('k', 'invited', 'l', 'Invitations envoyées à tous les magasins', 'done', (select n > 0 and inv = n from k), 'info', (select inv || ' / ' || n from k)),
    jsonb_build_object('k', 'activated', 'l', '80 % des magasins ont activé leur compte', 'done', (select n > 0 and act >= 0.8 * n from k), 'info', (select act || ' / ' || n from k)),
    jsonb_build_object('k', 'connected', 'l', '80 % des magasins connectés à Facebook ou Instagram', 'done', (select n > 0 and con >= 0.8 * n from k), 'info', (select con || ' / ' || n from k)),
    jsonb_build_object('k', 'training_stores', 'l', 'Formation des magasins (webinaire, guide)', 'manual', true, 'done', exists (select 1 from man where step = 'training_stores')),
    jsonb_build_object('k', 'promo', 'l', 'Première promo envoyée', 'done', exists (select 1 from public.promotions where created_by_network_id = p_net)),
    jsonb_build_object('k', 'pub', 'l', 'Première publication sur les réseaux', 'done', exists (select 1 from public.publications pu
       join public.store_promotions sp on sp.id = pu.store_promotion_id join public.stores s on s.id = sp.store_id
       where s.network_id = p_net and pu.status = 'published'))
  );
$$;
revoke all on function public.network_onboarding_steps(uuid) from public, anon, authenticated;

create or replace function public.manager_onboarding(p_net uuid)
returns jsonb language plpgsql stable security definer set search_path to '' as $$
begin
  perform public.manager_guard();
  return public.network_onboarding_steps(p_net);
end;
$$;
revoke all on function public.manager_onboarding(uuid) from public, anon;
grant execute on function public.manager_onboarding(uuid) to authenticated;

create or replace function public.manager_onboarding_toggle(p_net uuid, p_step text, p_done boolean)
returns jsonb language plpgsql security definer set search_path to '' as $$
begin
  perform public.manager_guard();
  if p_step not in ('contract', 'sepa', 'training_hq', 'training_stores') then raise exception 'Étape inconnue.'; end if;
  if p_done then
    insert into public.network_onboarding (network_id, step, done_by) values (p_net, p_step, (select auth.uid())) on conflict do nothing;
  else
    delete from public.network_onboarding where network_id = p_net and step = p_step;
  end if;
  return public.network_onboarding_steps(p_net);
end;
$$;
revoke all on function public.manager_onboarding_toggle(uuid, text, boolean) from public, anon;
grant execute on function public.manager_onboarding_toggle(uuid, text, boolean) to authenticated;

-- Avancement de toutes les centrales (liste Clients).
create or replace function public.manager_onboarding_all()
returns jsonb language plpgsql stable security definer set search_path to '' as $$
begin
  perform public.manager_guard();
  return coalesce((select jsonb_object_agg(n.id, (select jsonb_build_object('done', count(*) filter (where (e->>'done')::boolean), 'total', count(*))
      from jsonb_array_elements(public.network_onboarding_steps(n.id)) e)) from public.networks n), '{}');
end;
$$;
revoke all on function public.manager_onboarding_all() from public, anon;
grant execute on function public.manager_onboarding_all() to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Accueil : « À traiter » avec clés stables, contacts, tickets ; filtrage des lus.
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
  days as (select generate_series(date_trunc('day', now()) - interval '29 days', date_trunc('day', now()), interval '1 day')::date d),
  owners as (select distinct on (sm.store_id) sm.store_id, u.email from public.store_members sm join auth.users u on u.id = sm.user_id order by sm.store_id, sm.created_at),
  todo_acc as (
    select 'acc:' || a.id || ':' || a.status || ':' || coalesce(a.last_error_at, a.updated_at)::date as key,
      a.id, a.channel, a.status, a.last_error, s.id store_id, s.name store, s.network_id, n.name network, s.contact_email, o.email owner
    from public.social_accounts a join public.stores s on s.id = a.store_id left join public.networks n on n.id = s.network_id
    left join owners o on o.store_id = s.id
    where a.status <> 'active' and a.store_id in (select store_id from sc)),
  todo_fail as (
    select 'fail:' || p.id as key, p.id, p.channel, p.error_message, p.created_at, s.id store_id, s.name store, s.network_id, n.name network,
      pr.title promo, s.contact_email, o.email owner,
      exists (select 1 from public.social_accounts a where a.store_id = s.id and a.channel = p.channel and a.status <> 'active') account_issue
    from pubs p join public.stores s on s.id = p.store_id left join public.networks n on n.id = s.network_id
    join public.store_promotions sp on sp.id = p.store_promotion_id join public.promotions pr on pr.id = sp.promotion_id
    left join owners o on o.store_id = s.id
    where p.status = 'failed' and p.created_at > now() - interval '7 days'),
  todo_inv as (
    select 'inv:' || s.id || ':' || s.invited_at::date as key, s.id store_id, s.name store, s.network_id, n.name network, s.contact_email, s.invited_at,
      exists (select 1 from public.store_members m where m.store_id = s.id) activated, o.email owner
    from public.stores s left join public.networks n on n.id = s.network_id left join owners o on o.store_id = s.id
    where s.id in (select store_id from sc) and s.invited_at < now() - interval '3 days'
      and not exists (select 1 from public.social_accounts a where a.store_id = s.id)),
  todo_idle as (
    select 'idle:' || n.id || ':' || coalesce(max(u.last_sign_in_at), n.created_at)::date as key, n.id network_id, n.name network,
      max(u.last_sign_in_at) last_seen, jsonb_agg(u.email) emails
    from public.networks n join public.network_members m on m.network_id = n.id join auth.users u on u.id = m.user_id
    where (p_demo or not n.is_demo)
    group by n.id, n.name, n.created_at having coalesce(max(u.last_sign_in_at), 'epoch') < now() - interval '15 days'),
  todo_tk as (
    select 'tk:' || t.id || ':' || coalesce(t.last_client_at, t.created_at) as key, t.id, t.subject, t.status, t.priority, t.created_at,
      t.created_by_email, s.name store, n.name network
    from public.support_tickets t left join public.stores s on s.id = t.store_id left join public.networks n on n.id = t.network_id
    where t.status <> 'resolved' and (t.status = 'new' or t.last_client_at > coalesce(t.staff_seen_at, 'epoch'))),
  dis as (select key from public.manager_dismissed)
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
    'tickets', (select count(*) from public.support_tickets where status <> 'resolved'),
    'ticketsUnread', (select count(*) from todo_tk),
    'series', (select jsonb_agg(jsonb_build_object('d', d,
        'pub', (select count(*) from pubs where status = 'published' and published_at::date = d),
        'visits', (select count(*) from public.site_visits v where v.event = 'view' and v.at::date = d)) order by d) from days),
    'dismissed', (select count(*) from (select key from todo_acc union all select key from todo_fail union all select key from todo_inv
        union all select key from todo_idle union all select key from todo_tk) a where key in (select key from dis)),
    'todo', jsonb_build_object(
      'tickets', coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (select * from todo_tk where key not in (select key from dis) limit 50) x), '[]'),
      'accounts', coalesce((select jsonb_agg(to_jsonb(x) order by x.store) from (select * from todo_acc where key not in (select key from dis) limit 50) x), '[]'),
      'failures', coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (select * from todo_fail where key not in (select key from dis) order by created_at desc limit 50) x), '[]'),
      'invites', coalesce((select jsonb_agg(to_jsonb(x) order by x.invited_at) from (select * from todo_inv where key not in (select key from dis) limit 50) x), '[]'),
      'idle', coalesce((select jsonb_agg(to_jsonb(x)) from (select * from todo_idle where key not in (select key from dis)) x), '[]'))
  ) into r;
  return r;
end;
$$;
revoke all on function public.manager_dashboard(boolean) from public, anon;
grant execute on function public.manager_dashboard(boolean) to authenticated;
