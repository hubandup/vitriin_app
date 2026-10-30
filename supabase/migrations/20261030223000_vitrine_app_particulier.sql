-- App particulier (maquette Claude Design « Vitriin ») : promos utilisées et économies,
-- préférences du compte (rayon, centres d'intérêt, alertes, prénom).

-- 1. Une utilisation faite connecté est rattachée au compte (pour « Utilisées »).
alter table public.code_reveals add column if not exists user_id uuid references auth.users(id) on delete set null;
create index if not exists code_reveals_user_idx on public.code_reveals (user_id, revealed_at desc) where user_id is not null;

create or replace function public.vitrine_reveal(p_id uuid, p_client_id text, p_lat double precision default null, p_lng double precision default null)
returns jsonb language plpgsql security definer set search_path to '' as $$
declare v record; v_uid uuid := auth.uid();
begin
  select p.discount_code, p.ean_code into v
  from public.vitrine_live() l join public.store_promotions sp on sp.id = l.sp_id join public.promotions p on p.id = sp.promotion_id
  where l.sp_id = p_id;
  if not found then raise exception 'Cette promotion n''est plus disponible.'; end if;
  perform public.record_code_reveal_at(p_id, p_client_id, p_lat, p_lng);
  if v_uid is not null then
    update public.code_reveals set user_id = v_uid
    where store_promotion_id = p_id and client_id = p_client_id and revealed_on = current_date and user_id is null;
  end if;
  return jsonb_build_object('code', v.discount_code, 'ean', v.ean_code);
end;
$$;

-- 2. Préférences du compte client.
create table if not exists public.customer_prefs (
  user_id uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  first_name text check (first_name is null or length(first_name) <= 40),
  radius_km int not null default 5 check (radius_km between 1 and 50),
  interests text[] not null default '{}' check (cardinality(interests) <= 20),
  alerts boolean not null default true,
  updated_at timestamptz not null default now()
);
alter table public.customer_prefs enable row level security;
revoke all on public.customer_prefs from anon, authenticated;
grant select, insert, update, delete on public.customer_prefs to authenticated;
create policy customer_prefs_own on public.customer_prefs for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- 3. Espace client complet.
create or replace function public.customer_me()
returns jsonb language plpgsql stable security definer set search_path to '' as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'Connexion requise.'; end if;
  return jsonb_build_object(
    'email', (select email from auth.users where id = v_uid),
    'created_at', (select created_at from auth.users where id = v_uid),
    'prefs', coalesce((select to_jsonb(p) - 'user_id' from public.customer_prefs p where p.user_id = v_uid),
      jsonb_build_object('first_name', null, 'radius_km', 5, 'interests', '[]'::jsonb, 'alerts', true)),
    'follows', coalesce((select jsonb_agg(public.vitrine_store_json(f.store_id) || jsonb_build_object('alerts', f.alerts,
        'live', (select count(*) from public.vitrine_live(f.store_id))) order by f.created_at desc)
      from public.customer_follows f where f.user_id = v_uid), '[]'::jsonb),
    'saves', coalesce((select jsonb_agg(jsonb_build_object('promo', l.promo, 'store', public.vitrine_store_json(l.store_id)) order by c.created_at desc)
      from public.customer_saves c join public.vitrine_live() l on l.sp_id = c.store_promotion_id where c.user_id = v_uid), '[]'::jsonb),
    'feed', coalesce((select jsonb_agg(jsonb_build_object('promo', l.promo, 'store', public.vitrine_store_json(l.store_id)) order by l.promo->>'starts_at' desc)
      from public.customer_follows f join public.vitrine_live() l on l.store_id = f.store_id where f.user_id = v_uid), '[]'::jsonb),
    -- Promos utilisées (même terminées) : titre, magasin, date, montants pour calculer l'économie.
    'uses', coalesce((select jsonb_agg(u.j order by u.at desc) from (
      select max(r.revealed_at) at, jsonb_build_object('id', r.store_promotion_id, 'at', max(r.revealed_at),
        'title', coalesce(nullif(min(sp.overrides->>'title'), ''), min(p.title)),
        'img', coalesce(nullif(min(sp.overrides->>'media_url'), ''), min(p.media_url)),
        'type', min(p.promo_type::text), 'orig', min(p.details->>'orig'), 'val', min(p.details->>'val'),
        'store', min(s.name)) j
      from public.code_reveals r join public.store_promotions sp on sp.id = r.store_promotion_id
      join public.promotions p on p.id = sp.promotion_id join public.stores s on s.id = sp.store_id
      where r.user_id = v_uid group by r.store_promotion_id limit 100) u), '[]'::jsonb));
end;
$$;
revoke all on function public.customer_me() from public, anon;
grant execute on function public.customer_me() to authenticated;
