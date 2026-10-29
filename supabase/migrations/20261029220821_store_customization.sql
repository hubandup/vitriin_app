-- Personnalisation et retrait des promos de la centrale par le magasin,
-- seulement si la centrale l'autorise (networks.settings.store_edit / store_delete).
alter table public.store_promotions
  add column if not exists overrides jsonb not null default '{}'::jsonb,
  add column if not exists hidden boolean not null default false;
alter table public.store_promotions
  add constraint store_promotions_overrides_object check (jsonb_typeof(overrides) = 'object');
grant update (overrides, hidden) on public.store_promotions to authenticated;

create or replace function public.guard_store_customization()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_net uuid;
  v_mand boolean;
  v_settings jsonb;
  k text;
begin
  select p.created_by_network_id, p.is_mandatory into v_net, v_mand
  from public.promotions p where p.id = new.promotion_id;
  if v_net is not null then
    select n.settings into v_settings from public.networks n where n.id = v_net;
  end if;

  if new.overrides is distinct from old.overrides then
    for k in select jsonb_object_keys(new.overrides) loop
      if k not in ('title', 'text', 'media_url') then
        raise exception 'Champ non modifiable : %', k using errcode = '22023';
      end if;
    end loop;
    if length(coalesce(new.overrides->>'title', '')) > 90
       or length(coalesce(new.overrides->>'text', '')) > 1500
       or (new.overrides ? 'media_url' and coalesce(new.overrides->>'media_url', '') !~ '^https://') then
      raise exception 'Personnalisation invalide.' using errcode = '22023';
    end if;
    if v_net is not null and coalesce((v_settings->>'store_edit')::boolean, false) is not true then
      raise exception 'Votre centrale ne permet pas de modifier ses promos.' using errcode = '42501';
    end if;
  end if;

  if new.hidden and not old.hidden and v_net is not null then
    if coalesce(v_mand, false) then
      raise exception 'Une promo obligatoire ne peut pas être supprimée.' using errcode = '42501';
    end if;
    if coalesce((v_settings->>'store_delete')::boolean, false) is not true then
      raise exception 'Votre centrale ne permet pas de supprimer ses promos.' using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;
revoke execute on function public.guard_store_customization() from public, anon, authenticated;

drop trigger if exists store_promotions_guard_customization on public.store_promotions;
create trigger store_promotions_guard_customization
  before update of overrides, hidden on public.store_promotions
  for each row execute function public.guard_store_customization();

-- L'app magasin a besoin de savoir ce que la centrale autorise.
drop function if exists public.get_store_network(uuid);
create function public.get_store_network(p_store_id uuid)
returns table(network_id uuid, network_name text, logo_url text, support_email text, phone text, cgv_url text,
              store_edit boolean, store_delete boolean)
language sql stable security definer set search_path = ''
as $$
  select n.id, n.name, n.logo_url, n.support_email, n.phone, n.cgv_url,
         coalesce((n.settings->>'store_edit')::boolean, false),
         coalesce((n.settings->>'store_delete')::boolean, false)
  from public.stores s
  join public.networks n on n.id = s.network_id
  where s.id = p_store_id
    and public.is_store_member(p_store_id);
$$;
revoke execute on function public.get_store_network(uuid) from public, anon;
grant execute on function public.get_store_network(uuid) to authenticated;
