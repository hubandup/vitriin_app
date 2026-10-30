-- Vitrine publique (app.vitriin.co/v) et comptes clients.
--
-- 1. Sécurité : la lecture directe publique des tables stores / promotions /
--    store_promotions exposait les coordonnées des gérants (contact_*) et les
--    codes promo à tout le monde, y compris aux futurs comptes clients.
--    On ferme ces lectures : la vitrine passe par des fonctions qui ne
--    renvoient que les champs publics.
-- 2. Fonctions vitrine_* (anon + authenticated) : magasin, promo, autour de moi,
--    révélation du code (compte l'utilisation puis renvoie le code).
-- 3. Comptes clients : magasins suivis, promos enregistrées (RLS : ses lignes seulement).

-- ---------------------------------------------------------------------------
-- 1. Fermeture des lectures publiques
-- ---------------------------------------------------------------------------
drop policy if exists stores_select_public on public.stores;
create policy stores_select_members on public.stores for select to authenticated
  using (public.is_store_member(id) or public.is_store_network_member(id) or public.is_platform_admin());

drop policy if exists promotions_select_public on public.promotions;
drop policy if exists store_promotions_select_public on public.store_promotions;

revoke select on public.stores, public.promotions, public.store_promotions from anon;

-- ---------------------------------------------------------------------------
-- 2. Vitrine
-- ---------------------------------------------------------------------------
create or replace function public.vitrine_store_json(p_store_id uuid)
returns jsonb language sql stable security definer set search_path to '' as $$
  select jsonb_build_object('id', s.id, 'slug', s.slug, 'name', s.name, 'address', s.address,
    'city', s.city, 'postal_code', s.postal_code, 'lat', s.lat, 'lng', s.lng, 'category', s.category,
    'logo_url', s.logo_url, 'website', s.website, 'network', n.name, 'network_logo', n.logo_url,
    'demo', coalesce(n.is_demo, false))
  from public.stores s left join public.networks n on n.id = s.network_id where s.id = p_store_id;
$$;

-- Promos visibles : activées, ni masquées ni suspendues, en cours, de type promo.
create or replace function public.vitrine_live(p_store_id uuid default null)
returns table (sp_id uuid, store_id uuid, promo jsonb) language sql stable security definer set search_path to '' as $$
  select sp.id, sp.store_id, jsonb_build_object(
      'id', sp.id, 'store_id', sp.store_id,
      'title', coalesce(nullif(sp.overrides->>'title', ''), p.title),
      'text', coalesce(nullif(sp.overrides->>'text', ''), p.description, ''),
      'img', coalesce(nullif(sp.overrides->>'media_url', ''), p.media_url),
      'type', p.promo_type, 'mechanic', p.mechanic,
      'orig', p.details->'orig', 'val', p.details->'val', 'xy', p.details->'xy', 'sub', p.details->>'sub',
      'starts_at', p.starts_at, 'ends_at', p.ends_at, 'has_code', (p.discount_code is not null or p.ean_code is not null))
  from public.store_promotions sp join public.promotions p on p.id = sp.promotion_id
  where sp.status = 'active' and not sp.hidden and not sp.suspended
    and p.status = 'active' and p.promo_type is not null and now() between p.starts_at and p.ends_at
    and (p_store_id is null or sp.store_id = p_store_id);
$$;

create or replace function public.vitrine_store(p_slug text)
returns jsonb language plpgsql stable security definer set search_path to '' as $$
declare v_id uuid;
begin
  select id into v_id from public.stores where slug = lower(btrim(p_slug));
  if v_id is null then return null; end if;
  return jsonb_build_object('store', public.vitrine_store_json(v_id),
    'promos', coalesce((select jsonb_agg(l.promo order by l.promo->>'ends_at') from public.vitrine_live(v_id) l), '[]'::jsonb));
end;
$$;

create or replace function public.vitrine_promo(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path to '' as $$
declare v record;
begin
  select * into v from public.vitrine_live() l where l.sp_id = p_id;
  if not found then return null; end if;
  return jsonb_build_object('promo', v.promo, 'store', public.vitrine_store_json(v.store_id));
end;
$$;

-- Promos autour d'un point (rayon 1 à 100 km). Les réseaux de démo sont exclus sauf demande.
create or replace function public.vitrine_nearby(p_lat double precision, p_lng double precision,
  p_km double precision default 15, p_demo boolean default false)
returns jsonb language plpgsql stable security definer set search_path to '' as $$
declare v_km double precision := least(greatest(coalesce(p_km, 15), 1), 100);
begin
  if p_lat is null or p_lng is null or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    raise exception 'Position invalide.';
  end if;
  return coalesce((select jsonb_agg(x.j order by x.d, x.j->'promo'->>'ends_at') from (
    select l.promo, s.id,
      2 * 6371 * asin(sqrt(power(sin(radians(s.lat - p_lat) / 2), 2)
        + cos(radians(p_lat)) * cos(radians(s.lat)) * power(sin(radians(s.lng - p_lng) / 2), 2))) d,
      jsonb_build_object('promo', l.promo, 'store', public.vitrine_store_json(s.id)) j
    from public.vitrine_live() l join public.stores s on s.id = l.store_id
    left join public.networks n on n.id = s.network_id
    where s.lat is not null and s.lng is not null
      and (p_demo or not coalesce(n.is_demo, false))
  ) x where x.d <= v_km limit 60), '[]'::jsonb);
end;
$$;

-- Recherche par ville ou nom de magasin (sans géolocalisation).
create or replace function public.vitrine_search(p_q text, p_demo boolean default false)
returns jsonb language plpgsql stable security definer set search_path to '' as $$
declare v_q text := lower(public.unaccent_simple(btrim(coalesce(p_q, ''))));
begin
  if length(v_q) < 2 then return '[]'::jsonb; end if;
  v_q := left(v_q, 60);
  return coalesce((select jsonb_agg(public.vitrine_store_json(s.id) || jsonb_build_object('live',
      (select count(*) from public.vitrine_live(s.id))) order by s.name)
    from (select s.* from public.stores s left join public.networks n on n.id = s.network_id
          where (p_demo or not coalesce(n.is_demo, false))
            and (lower(public.unaccent_simple(coalesce(s.city, ''))) like v_q || '%'
              or lower(public.unaccent_simple(s.name)) like '%' || v_q || '%'
              or coalesce(s.postal_code, '') like v_q || '%')
          order by s.name limit 40) s), '[]'::jsonb);
end;
$$;

-- Révéler le code : compte l'utilisation (une fois par client, promo et jour) puis renvoie le code.
create or replace function public.vitrine_reveal(p_id uuid, p_client_id text, p_lat double precision default null, p_lng double precision default null)
returns jsonb language plpgsql security definer set search_path to '' as $$
declare v record;
begin
  select p.discount_code, p.ean_code into v
  from public.vitrine_live() l join public.store_promotions sp on sp.id = l.sp_id join public.promotions p on p.id = sp.promotion_id
  where l.sp_id = p_id;
  if not found then raise exception 'Cette promotion n''est plus disponible.'; end if;
  perform public.record_code_reveal_at(p_id, p_client_id, p_lat, p_lng);
  return jsonb_build_object('code', v.discount_code, 'ean', v.ean_code);
end;
$$;

revoke all on function public.vitrine_store_json(uuid) from public, anon, authenticated;
revoke all on function public.vitrine_live(uuid) from public, anon, authenticated;
do $$ declare f text; begin
  foreach f in array array['public.vitrine_store(text)', 'public.vitrine_promo(uuid)',
    'public.vitrine_nearby(double precision, double precision, double precision, boolean)',
    'public.vitrine_search(text, boolean)', 'public.vitrine_reveal(uuid, text, double precision, double precision)'] loop
    execute format('revoke all on function %s from public', f);
    execute format('grant execute on function %s to anon, authenticated', f);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- 3. Comptes clients
-- ---------------------------------------------------------------------------
create table if not exists public.customer_follows (
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  store_id uuid not null references public.stores(id) on delete cascade,
  alerts boolean not null default true,
  created_at timestamptz not null default now(),
  primary key (user_id, store_id)
);
create table if not exists public.customer_saves (
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  store_promotion_id uuid not null references public.store_promotions(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, store_promotion_id)
);
alter table public.customer_follows enable row level security;
alter table public.customer_saves enable row level security;
revoke all on public.customer_follows, public.customer_saves from anon, authenticated;
grant select, insert, update, delete on public.customer_follows, public.customer_saves to authenticated;
create policy customer_follows_own on public.customer_follows for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy customer_saves_own on public.customer_saves for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- Espace client : magasins suivis, promos enregistrées encore valables, fil des magasins suivis.
create or replace function public.customer_me()
returns jsonb language plpgsql stable security definer set search_path to '' as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'Connexion requise.'; end if;
  return jsonb_build_object(
    'email', (select email from auth.users where id = v_uid),
    'follows', coalesce((select jsonb_agg(public.vitrine_store_json(f.store_id) || jsonb_build_object('alerts', f.alerts,
        'live', (select count(*) from public.vitrine_live(f.store_id))) order by f.created_at desc)
      from public.customer_follows f where f.user_id = v_uid), '[]'::jsonb),
    'saves', coalesce((select jsonb_agg(jsonb_build_object('promo', l.promo, 'store', public.vitrine_store_json(l.store_id)) order by c.created_at desc)
      from public.customer_saves c join public.vitrine_live() l on l.sp_id = c.store_promotion_id where c.user_id = v_uid), '[]'::jsonb),
    'feed', coalesce((select jsonb_agg(jsonb_build_object('promo', l.promo, 'store', public.vitrine_store_json(l.store_id)) order by l.promo->>'starts_at' desc)
      from public.customer_follows f join public.vitrine_live() l on l.store_id = f.store_id where f.user_id = v_uid), '[]'::jsonb));
end;
$$;
revoke all on function public.customer_me() from public, anon;
grant execute on function public.customer_me() to authenticated;

-- Suppression du compte client (RGPD). Refusée pour un compte magasin ou centrale.
create or replace function public.customer_delete_account()
returns void language plpgsql security definer set search_path to '' as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'Connexion requise.'; end if;
  if exists (select 1 from public.store_members where user_id = v_uid)
     or exists (select 1 from public.network_members where user_id = v_uid)
     or exists (select 1 from public.platform_admins where user_id = v_uid) then
    raise exception 'Ce compte est lié à un magasin ou une centrale : contactez le support.';
  end if;
  delete from auth.users where id = v_uid;
end;
$$;
revoke all on function public.customer_delete_account() from public, anon;
grant execute on function public.customer_delete_account() to authenticated;
