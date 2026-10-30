-- Liste d'attente des commerçants indépendants (formulaire de vitriin.fr).
-- Table fermée ; écriture publique uniquement via join_waitlist, lecture via manager_waitlist.

create table if not exists public.waitlist_signups (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  email text not null,
  business text,
  city text,
  activity text,
  source text,
  contacted_at timestamptz
);
create unique index if not exists waitlist_signups_email_key on public.waitlist_signups (lower(email));
alter table public.waitlist_signups enable row level security;
revoke all on public.waitlist_signups from anon, authenticated;

create or replace function public.join_waitlist(p_email text, p_business text default null, p_city text default null,
  p_activity text default null, p_source text default null)
returns text language plpgsql security definer set search_path to '' as $$
declare v_email text := lower(btrim(coalesce(p_email, '')));
begin
  if length(v_email) > 200 or v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Adresse email invalide.';
  end if;
  -- anti-abus : plafond global horaire
  if (select count(*) from public.waitlist_signups where created_at > now() - interval '1 hour') >= 200 then
    raise exception 'Trop de demandes, réessayez plus tard.';
  end if;
  insert into public.waitlist_signups (email, business, city, activity, source)
  values (v_email,
    left(nullif(btrim(p_business), ''), 120),
    left(nullif(btrim(p_city), ''), 80),
    left(nullif(btrim(p_activity), ''), 80),
    left(nullif(lower(btrim(p_source)), ''), 60))
  on conflict (lower(email)) do nothing;
  return 'ok'; -- même réponse si déjà inscrit : ne révèle pas qui est inscrit
end;
$$;
revoke all on function public.join_waitlist(text, text, text, text, text) from public;
grant execute on function public.join_waitlist(text, text, text, text, text) to anon, authenticated;

create or replace function public.manager_waitlist()
returns jsonb language plpgsql stable security definer set search_path to '' as $$
begin
  perform public.manager_guard();
  return jsonb_build_object(
    'total', (select count(*) from public.waitlist_signups),
    'week', (select count(*) from public.waitlist_signups where created_at > now() - interval '7 days'),
    'rows', coalesce((select jsonb_agg(to_jsonb(w) order by w.created_at desc)
      from (select id, created_at, email, business, city, activity, source, contacted_at
            from public.waitlist_signups order by created_at desc limit 200) w), '[]'::jsonb));
end;
$$;
revoke all on function public.manager_waitlist() from public, anon;
grant execute on function public.manager_waitlist() to authenticated;

create or replace function public.manager_waitlist_contacted(p_id bigint, p_done boolean)
returns void language plpgsql security definer set search_path to '' as $$
begin
  perform public.manager_guard();
  update public.waitlist_signups set contacted_at = case when p_done then now() end where id = p_id;
end;
$$;
revoke all on function public.manager_waitlist_contacted(bigint, boolean) from public, anon;
grant execute on function public.manager_waitlist_contacted(bigint, boolean) to authenticated;
