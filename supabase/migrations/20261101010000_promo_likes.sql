-- MOD-067 : « J'aime » sur les promos (app particulier), sans compte, une fois par appareil.
create table if not exists public.promo_likes (
  store_promotion_id uuid not null references public.store_promotions(id) on delete cascade,
  store_id uuid not null references public.stores(id) on delete cascade,
  promotion_id uuid not null references public.promotions(id) on delete cascade,
  client_id text not null check (client_id ~ '^[A-Za-z0-9_-]{8,64}$'),
  created_at timestamptz not null default now(),
  primary key (store_promotion_id, client_id)
);
create index if not exists promo_likes_store on public.promo_likes (store_id);
create index if not exists promo_likes_promotion on public.promo_likes (promotion_id);
alter table public.promo_likes enable row level security;
revoke all on public.promo_likes from anon, authenticated;
grant select on public.promo_likes to authenticated;
create policy promo_likes_select_members on public.promo_likes
  for select to authenticated using (public.is_store_member(store_id) or public.is_store_network_member(store_id));

-- Seule porte d'écriture : promo visible uniquement, renvoie le total à jour.
create or replace function public.vitrine_like(p_id uuid, p_client_id text, p_on boolean)
returns integer language plpgsql security definer set search_path to '' as $$
declare v record;
begin
  if p_client_id is null or p_client_id !~ '^[A-Za-z0-9_-]{8,64}$' then raise exception 'Appareil non reconnu.'; end if;
  select sp.id, sp.store_id, sp.promotion_id into v
  from public.store_promotions sp join public.promotions p on p.id = sp.promotion_id
  where sp.id = p_id and sp.status = 'active' and not sp.hidden and not sp.suspended
    and p.status = 'active' and now() between p.starts_at and p.ends_at;
  if not found then raise exception 'Cette promo n''est plus disponible.'; end if;
  if p_on then
    insert into public.promo_likes (store_promotion_id, store_id, promotion_id, client_id)
    values (v.id, v.store_id, v.promotion_id, p_client_id) on conflict do nothing;
  else
    delete from public.promo_likes where store_promotion_id = v.id and client_id = p_client_id;
  end if;
  return (select count(*) from public.promo_likes where store_promotion_id = v.id);
end;
$$;
revoke all on function public.vitrine_like(uuid, text, boolean) from public;
grant execute on function public.vitrine_like(uuid, text, boolean) to anon, authenticated;

-- Le total de « J'aime » voyage avec chaque promo affichée.
create or replace function public.vitrine_live(p_store_id uuid default null)
returns table (sp_id uuid, store_id uuid, promo jsonb) language sql stable security definer set search_path to '' as $$
  select sp.id, sp.store_id, jsonb_build_object(
      'id', sp.id, 'store_id', sp.store_id,
      'title', coalesce(nullif(sp.overrides->>'title', ''), p.title),
      'text', coalesce(nullif(sp.overrides->>'text', ''), p.description, ''),
      'img', coalesce(nullif(sp.overrides->>'media_url', ''), p.media_url),
      'type', p.promo_type, 'mechanic', p.mechanic,
      'orig', p.details->'orig', 'val', p.details->'val', 'xy', p.details->'xy', 'sub', p.details->>'sub',
      'starts_at', p.starts_at, 'ends_at', p.ends_at, 'has_code', (p.discount_code is not null or p.ean_code is not null),
      'likes', (select count(*) from public.promo_likes l where l.store_promotion_id = sp.id))
  from public.store_promotions sp join public.promotions p on p.id = sp.promotion_id
  where sp.status = 'active' and not sp.hidden and not sp.suspended
    and p.status = 'active' and p.promo_type is not null and now() between p.starts_at and p.ends_at
    and (p_store_id is null or sp.store_id = p_store_id);
$$;
revoke all on function public.vitrine_live(uuid) from public, anon, authenticated;

-- Centrale : « J'aime » et codes affichés sur Vitriin, par magasin et par campagne.
create or replace function public.network_vitrine_stats(p_network_id uuid)
returns jsonb language plpgsql stable security definer set search_path to '' as $$
begin
  if not public.is_network_member(p_network_id) then raise exception 'Accès réservé à la centrale.'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('store_id', x.store_id, 'promotion_id', x.promotion_id, 'likes', x.likes, 'codes', x.codes))
    from (
      select sp.store_id, sp.promotion_id,
        (select count(*) from public.promo_likes l where l.store_promotion_id = sp.id) likes,
        (select count(*) from public.code_reveals r where r.store_promotion_id = sp.id and (r.confidence <> 'distance' or r.used_at is not null)) codes
      from public.store_promotions sp join public.stores s on s.id = sp.store_id
      where s.network_id = p_network_id
    ) x where x.likes > 0 or x.codes > 0), '[]'::jsonb);
end;
$$;
revoke all on function public.network_vitrine_stats(uuid) from public, anon;
grant execute on function public.network_vitrine_stats(uuid) to authenticated;
