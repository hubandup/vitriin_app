-- Drive to store : chaque fois qu'un client révèle le code-barre d'une promo
-- (« Utiliser cette promotion »), on enregistre l'événement.
create table if not exists public.code_reveals (
  id bigint generated always as identity primary key,
  store_promotion_id uuid not null references public.store_promotions(id) on delete cascade,
  store_id uuid not null references public.stores(id) on delete cascade,
  promotion_id uuid not null references public.promotions(id) on delete cascade,
  client_id text not null check (client_id ~ '^[A-Za-z0-9_-]{8,64}$'),
  revealed_on date not null default current_date,
  revealed_at timestamptz not null default now(),
  source text not null default 'vitrine' check (source in ('vitrine', 'demo')),
  unique (store_promotion_id, client_id, revealed_on) -- un client compte une fois par promo et par jour
);
create index if not exists code_reveals_store_time on public.code_reveals (store_id, revealed_at desc);
alter table public.code_reveals enable row level security;
revoke all on public.code_reveals from anon, authenticated;
grant select on public.code_reveals to authenticated;
create policy code_reveals_select_members on public.code_reveals
  for select to authenticated using (public.is_store_member(store_id) or public.is_store_network_member(store_id));

-- Seule porte d'entrée en écriture. Ne compte que les promos réellement visibles
-- (activée, ni suspendue ni supprimée, en cours). Les membres du magasin qui
-- testent leur propre vue client ne comptent pas, sauf sur un réseau de démo.
create or replace function public.record_code_reveal(p_store_promotion_id uuid, p_client_id text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v record;
begin
  if p_client_id is null or p_client_id !~ '^[A-Za-z0-9_-]{8,64}$' then
    return false;
  end if;
  select sp.id, sp.store_id, sp.promotion_id, coalesce(n.is_demo, false) as demo
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
  insert into public.code_reveals (store_promotion_id, store_id, promotion_id, client_id)
  values (v.id, v.store_id, v.promotion_id, p_client_id)
  on conflict (store_promotion_id, client_id, revealed_on) do nothing;
  return true;
end;
$$;
revoke execute on function public.record_code_reveal(uuid, text) from public;
grant execute on function public.record_code_reveal(uuid, text) to anon, authenticated;
