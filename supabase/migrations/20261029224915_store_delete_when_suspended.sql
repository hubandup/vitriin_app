-- Règle unique : une promo en cours se suspend d'abord ; une fois suspendue
-- (ou terminée), elle peut être supprimée.
create or replace function public.guard_store_customization()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_net uuid;
  v_mand boolean;
  v_end timestamptz;
  v_settings jsonb;
  k text;
begin
  select p.created_by_network_id, p.is_mandatory, p.ends_at into v_net, v_mand, v_end
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

  -- Suspendre une promo de la centrale : autorisée par elle, jamais une obligatoire.
  if new.suspended and not old.suspended and v_net is not null then
    if coalesce(v_mand, false) then
      raise exception 'Une promo obligatoire ne peut pas être suspendue.' using errcode = '42501';
    end if;
    if coalesce((v_settings->>'store_delete')::boolean, false) is not true then
      raise exception 'Votre centrale ne permet pas de suspendre ses promos.' using errcode = '42501';
    end if;
  end if;

  -- Supprimer une promo de la centrale : seulement suspendue ou terminée.
  if new.hidden and not old.hidden and v_net is not null and v_end > now() and not old.suspended then
    raise exception 'Suspendez d''abord la promo : une promo en cours ne se supprime pas directement.' using errcode = '42501';
  end if;
  return new;
end;
$$;
revoke execute on function public.guard_store_customization() from public, anon, authenticated;
