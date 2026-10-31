-- MOD-059 : profil particulier complet (nom, téléphone, newsletter, localisation) et promos à venir.

-- 1. Préférences : nom, téléphone, newsletter (opt-in, désactivée par défaut), localisation.
alter table public.customer_prefs
  add column if not exists last_name text check (last_name is null or length(last_name) <= 60),
  add column if not exists phone text check (phone is null or phone ~ '^[0-9 +().-]{6,20}$'),
  add column if not exists newsletter boolean not null default false,
  add column if not exists geo boolean not null default true;

-- 2. Promos qui commencent dans les 21 prochains jours (sans code : il n'est jamais exposé ici).
create or replace function public.vitrine_soon(p_lat double precision default null, p_lng double precision default null, p_demo boolean default false)
returns jsonb language sql stable security definer set search_path to '' as $$
  with c as (
    select distinct on (sp.promotion_id) p.starts_at st, s.id store_id,
      jsonb_build_object('id', sp.id, 'store_id', sp.store_id,
        'title', coalesce(nullif(sp.overrides->>'title', ''), p.title),
        'text', coalesce(nullif(sp.overrides->>'text', ''), p.description, ''),
        'img', coalesce(nullif(sp.overrides->>'media_url', ''), p.media_url),
        'type', p.promo_type, 'mechanic', p.mechanic,
        'orig', p.details->'orig', 'val', p.details->'val', 'xy', p.details->'xy', 'sub', p.details->>'sub',
        'starts_at', p.starts_at, 'ends_at', p.ends_at, 'soon', true) promo,
      case when p_lat between -90 and 90 and p_lng between -180 and 180 and s.lat is not null then
        2 * 6371 * asin(sqrt(power(sin(radians(s.lat - p_lat) / 2), 2)
          + cos(radians(p_lat)) * cos(radians(s.lat)) * power(sin(radians(s.lng - p_lng) / 2), 2))) end d
    from public.store_promotions sp
    join public.promotions p on p.id = sp.promotion_id
    join public.stores s on s.id = sp.store_id
    left join public.networks n on n.id = s.network_id
    where sp.status = 'active' and not sp.hidden and not sp.suspended
      and p.status = 'active' and p.promo_type is not null
      and p.starts_at > now() and p.starts_at < now() + interval '21 days'
      and (p_demo or not coalesce(n.is_demo, false))
    order by sp.promotion_id, d nulls last, s.id
  )
  select coalesce(jsonb_agg(jsonb_build_object('promo', c.promo, 'store', public.vitrine_store_json(c.store_id)) order by c.st), '[]'::jsonb)
  from (select * from c order by st, d nulls last limit 30) c;
$$;
revoke all on function public.vitrine_soon(double precision, double precision, boolean) from public;
grant execute on function public.vitrine_soon(double precision, double precision, boolean) to anon, authenticated;

-- 3. Photo de profil : bucket public « avatars », chaque compte n'écrit que dans son dossier <uid>/.
alter table public.customer_prefs add column if not exists avatar_url text
  check (avatar_url is null or avatar_url like 'https://zjugauidrijghesgsmap.supabase.co/storage/v1/object/public/avatars/%');
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 1048576, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set public = true, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;
create policy avatars_insert_own on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy avatars_select_own on storage.objects for select to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy avatars_delete_own on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
