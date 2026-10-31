-- MOD-049 : fiabilité des codes affichés.
-- Chaque affichage du code reçoit un indice de confiance calculé côté serveur :
--   probable  : position partagée, à moins de 200 m du magasin, entre 8 h et 21 h (heure de Paris) ;
--   incertain : position non partagée, entre 8 h et 21 h ;
--   distance  : loin du magasin, ou en dehors de ces heures.
-- Un nouvel affichage le même jour (code refloué au bout de 2 minutes, puis réaffiché en caisse) peut
-- seulement améliorer l'indice. used_at : le client confirme lui-même l'avoir utilisé (déclaratif).

alter table public.code_reveals
  add column if not exists distance_m integer,
  add column if not exists confidence text not null default 'incertain'
    check (confidence in ('probable', 'incertain', 'distance')),
  add column if not exists used_at timestamptz;

-- Historique : distance inconnue, les affichages déjà enregistrés restent « incertain ».

create or replace function public.reveal_rank(p text) returns int
language sql immutable set search_path to '' as $$
  select case p when 'probable' then 3 when 'incertain' then 2 else 1 end;
$$;

create or replace function public.record_code_reveal_at(p_store_promotion_id uuid, p_client_id text, p_lat double precision, p_lng double precision)
returns boolean language plpgsql security definer set search_path to '' as $$
declare
  v record;
  v_store uuid;
  v_dist double precision;
  v_hour numeric := extract(hour from (now() at time zone 'Europe/Paris')) + extract(minute from (now() at time zone 'Europe/Paris')) / 60;
  v_open boolean;
  v_conf text;
begin
  if p_client_id is null or p_client_id !~ '^[A-Za-z0-9_-]{8,64}$' then
    return false;
  end if;
  select sp.id, sp.store_id, sp.promotion_id, s.network_id, coalesce(n.is_demo, false) as demo
    into v
  from public.store_promotions sp
  join public.promotions p on p.id = sp.promotion_id
  join public.stores s on s.id = sp.store_id
  left join public.networks n on n.id = s.network_id
  where sp.id = p_store_promotion_id
    and sp.status = 'active' and not sp.hidden and not sp.suspended
    and now() between p.starts_at and p.ends_at;
  if not found then
    return false;
  end if;
  if auth.uid() is not null and public.is_store_member(v.store_id) and not v.demo then
    return false;
  end if;

  -- Magasin le plus proche du client, dans le même réseau (distance haversine, 10 km max).
  if p_lat between -90 and 90 and p_lng between -180 and 180 then
    select s.id, 2 * 6371000 * asin(sqrt(power(sin(radians(s.lat - p_lat) / 2), 2)
            + cos(radians(p_lat)) * cos(radians(s.lat)) * power(sin(radians(s.lng - p_lng) / 2), 2)))
      into v_store, v_dist
    from public.stores s
    where s.lat is not null and s.lng is not null
      and (s.id = v.store_id or (v.network_id is not null and s.network_id = v.network_id))
    order by power(s.lat - p_lat, 2) + power((s.lng - p_lng) * cos(radians(p_lat)), 2)
    limit 1;
    if v_dist > 10000 then v_store := null; end if;
  end if;

  v_open := v_hour >= 8 and v_hour < 21;
  v_conf := case
    when v_dist is not null and v_dist <= 200 and v_open then 'probable'
    when v_dist is null and v_open then 'incertain'
    else 'distance' end;

  insert into public.code_reveals (store_promotion_id, store_id, origin_store_id, promotion_id, client_id, located, distance_m, confidence)
  values (v.id, coalesce(v_store, v.store_id), v.store_id, v.promotion_id, p_client_id, v_store is not null,
          case when v_dist is not null then least(round(v_dist), 2000000000)::int end, v_conf)
  on conflict (store_promotion_id, client_id, revealed_on) do update set
    confidence = case when public.reveal_rank(excluded.confidence) > public.reveal_rank(public.code_reveals.confidence)
                      then excluded.confidence else public.code_reveals.confidence end,
    distance_m = case when excluded.distance_m is not null
                      and (public.code_reveals.distance_m is null or excluded.distance_m < public.code_reveals.distance_m)
                      then excluded.distance_m else public.code_reveals.distance_m end,
    store_id = case when public.reveal_rank(excluded.confidence) > public.reveal_rank(public.code_reveals.confidence)
                    then excluded.store_id else public.code_reveals.store_id end,
    located = public.code_reveals.located or excluded.located;
  return true;
end;
$$;

-- Le client confirme avoir utilisé le code (déclaratif). Uniquement sur un affichage de moins de 24 h
-- fait avec ce même identifiant d'appareil : pas de confirmation sans affichage préalable.
create or replace function public.vitrine_confirm_use(p_id uuid, p_client_id text)
returns boolean language plpgsql security definer set search_path to '' as $$
declare n int;
begin
  if p_client_id is null or p_client_id !~ '^[A-Za-z0-9_-]{8,64}$' then return false; end if;
  update public.code_reveals set used_at = coalesce(used_at, now()),
    user_id = coalesce(user_id, (select auth.uid()))
  where store_promotion_id = p_id and client_id = p_client_id and revealed_at > now() - interval '24 hours';
  get diagnostics n = row_count;
  return n > 0;
end;
$$;
revoke all on function public.vitrine_confirm_use(uuid, text) from public;
grant execute on function public.vitrine_confirm_use(uuid, text) to anon, authenticated;
revoke all on function public.reveal_rank(text) from public, anon, authenticated;

-- Villes qui ont des promos en cours : remplace l'écran vide quand la position est inconnue.
create or replace function public.vitrine_cities(p_demo boolean default false)
returns jsonb language sql stable security definer set search_path to '' as $$
  select coalesce(jsonb_agg(c order by (c->>'n')::int desc, c->>'city'), '[]'::jsonb) from (
    select jsonb_build_object('city', s.city, 'n', count(*), 'lat', avg(s.lat), 'lng', avg(s.lng)) c
    from public.vitrine_live() l join public.stores s on s.id = l.store_id
    left join public.networks n on n.id = s.network_id
    where s.lat is not null and nullif(btrim(s.city), '') is not null
      and (p_demo or not coalesce(n.is_demo, false))
    group by s.city order by count(*) desc limit 12) x;
$$;
revoke all on function public.vitrine_cities(boolean) from public;
grant execute on function public.vitrine_cities(boolean) to anon, authenticated;
