-- Le code est rattaché au magasin où le client se trouve (le plus proche du
-- réseau, à 10 km au plus), sinon au magasin qui a publié la promo.
-- Les coordonnées du client ne sont jamais enregistrées.
alter table public.code_reveals
  add column if not exists origin_store_id uuid references public.stores(id) on delete set null,
  add column if not exists located boolean not null default false;

create or replace function public.record_code_reveal_at(p_store_promotion_id uuid, p_client_id text,
                                                        p_lat double precision, p_lng double precision)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v record;
  v_store uuid;
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
    select s.id into v_store
    from public.stores s
    where s.lat is not null and s.lng is not null
      and (s.id = v.store_id or (v.network_id is not null and s.network_id = v.network_id))
      and 2 * 6371 * asin(sqrt(power(sin(radians(s.lat - p_lat) / 2), 2)
            + cos(radians(p_lat)) * cos(radians(s.lat)) * power(sin(radians(s.lng - p_lng) / 2), 2))) <= 10
    order by power(s.lat - p_lat, 2) + power((s.lng - p_lng) * cos(radians(p_lat)), 2)
    limit 1;
  end if;

  insert into public.code_reveals (store_promotion_id, store_id, origin_store_id, promotion_id, client_id, located)
  values (v.id, coalesce(v_store, v.store_id), v.store_id, v.promotion_id, p_client_id, v_store is not null)
  on conflict (store_promotion_id, client_id, revealed_on) do nothing;
  return true;
end;
$$;
revoke execute on function public.record_code_reveal_at(uuid, text, double precision, double precision) from public;
grant execute on function public.record_code_reveal_at(uuid, text, double precision, double precision) to anon, authenticated;

-- Ancienne entrée (sans position) : passe par la nouvelle.
create or replace function public.record_code_reveal(p_store_promotion_id uuid, p_client_id text)
returns boolean
language sql
security definer
set search_path = ''
as $$ select public.record_code_reveal_at(p_store_promotion_id, p_client_id, null, null); $$;
