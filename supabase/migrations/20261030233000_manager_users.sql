-- Manager > fiche client > Utilisateurs : voir et gérer les comptes d'une centrale et de ses magasins.
-- Toutes les fonctions vérifient manager_guard() (équipe Vitriin) côté serveur.
-- L'invitation (création de compte + email) passe par la fonction Edge manager-invite.

-- L'équipe Vitriin peut changer ou retirer un propriétaire depuis le Manager
-- (les fonctions garantissent qu'il reste toujours au moins un propriétaire).
create or replace function public.guard_network_owner()
returns trigger language plpgsql security definer set search_path to '' as $$
begin
  if (select auth.uid()) is null or public.is_platform_admin() then
    return coalesce(new, old);
  end if;
  if tg_op = 'DELETE' and old.role = 'owner' then
    raise exception 'Le propriétaire du réseau ne peut pas être retiré.' using errcode = 'check_violation';
  end if;
  if tg_op = 'UPDATE' and (old.role = 'owner' or new.role = 'owner') and old.role is distinct from new.role then
    raise exception 'Le rôle de propriétaire ne se modifie pas depuis l''application.' using errcode = 'check_violation';
  end if;
  return coalesce(new, old);
end;
$$;

create or replace function public.manager_user_json(p_user uuid)
returns jsonb language sql stable security definer set search_path to '' as $$
  select jsonb_build_object('user_id', u.id, 'email', u.email, 'created_at', u.created_at,
    'last_sign_in_at', u.last_sign_in_at, 'invited_at', u.invited_at,
    'confirmed', u.email_confirmed_at is not null or u.last_sign_in_at is not null,
    'blocked', u.banned_until is not null and u.banned_until > now(),
    'staff', exists (select 1 from public.platform_admins pa where pa.user_id = u.id))
  from auth.users u where u.id = p_user;
$$;
revoke all on function public.manager_user_json(uuid) from public, anon, authenticated;

create or replace function public.manager_network_users(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path to '' as $$
begin
  perform public.manager_guard();
  return jsonb_build_object(
    'network', coalesce((select jsonb_agg(public.manager_user_json(m.user_id) || jsonb_build_object('role', m.role)
        order by case m.role when 'owner' then 0 when 'admin' then 1 else 2 end, m.created_at)
      from public.network_members m where m.network_id = p_id), '[]'::jsonb),
    'stores', coalesce((select jsonb_agg(jsonb_build_object('store_id', s.id, 'store', s.name, 'city', s.city,
        'contact_email', s.contact_email, 'invited_at', s.invited_at,
        'users', coalesce((select jsonb_agg(public.manager_user_json(sm.user_id) || jsonb_build_object('role', sm.role) order by sm.created_at)
          from public.store_members sm where sm.store_id = s.id), '[]'::jsonb)) order by s.name)
      from public.stores s where s.network_id = p_id), '[]'::jsonb));
end;
$$;

create or replace function public.manager_user_set_role(p_net uuid, p_user uuid, p_role text)
returns void language plpgsql security definer set search_path to '' as $$
begin
  perform public.manager_guard();
  if p_role not in ('owner', 'admin', 'member') then raise exception 'Rôle inconnu.'; end if;
  if not exists (select 1 from public.network_members where network_id = p_net and user_id = p_user) then
    raise exception 'Cet utilisateur ne fait pas partie de la centrale.';
  end if;
  if p_role <> 'owner' and (select role from public.network_members where network_id = p_net and user_id = p_user) = 'owner'
     and (select count(*) from public.network_members where network_id = p_net and role = 'owner') = 1 then
    raise exception 'Il faut au moins un propriétaire : nommez-en un autre avant.';
  end if;
  update public.network_members set role = p_role::public.network_role where network_id = p_net and user_id = p_user;
end;
$$;

-- Retire un utilisateur de la centrale (p_store null) ou d'un magasin de cette centrale.
create or replace function public.manager_user_remove(p_net uuid, p_user uuid, p_store uuid default null)
returns void language plpgsql security definer set search_path to '' as $$
begin
  perform public.manager_guard();
  if p_store is null then
    if (select role from public.network_members where network_id = p_net and user_id = p_user) = 'owner'
       and (select count(*) from public.network_members where network_id = p_net and role = 'owner') = 1 then
      raise exception 'C''est le seul propriétaire : nommez-en un autre avant de le retirer.';
    end if;
    delete from public.network_members where network_id = p_net and user_id = p_user;
  else
    if not exists (select 1 from public.stores where id = p_store and network_id = p_net) then
      raise exception 'Ce magasin n''appartient pas à cette centrale.';
    end if;
    delete from public.store_members where store_id = p_store and user_id = p_user;
  end if;
end;
$$;

-- Bloque ou débloque un compte (connexion impossible partout, sessions coupées).
create or replace function public.manager_user_block(p_user uuid, p_block boolean)
returns void language plpgsql security definer set search_path to '' as $$
begin
  perform public.manager_guard();
  if p_user = auth.uid() then raise exception 'Vous ne pouvez pas bloquer votre propre compte.'; end if;
  if exists (select 1 from public.platform_admins where user_id = p_user) then
    raise exception 'Un compte de l''équipe Vitriin ne se bloque pas d''ici.';
  end if;
  update auth.users set banned_until = case when p_block then 'infinity'::timestamptz end, updated_at = now() where id = p_user;
  if p_block then
    delete from auth.refresh_tokens where user_id = p_user::text;
    delete from auth.sessions where user_id = p_user;
  end if;
end;
$$;

do $$ declare f text; begin
  foreach f in array array['public.manager_network_users(uuid)', 'public.manager_user_set_role(uuid, uuid, text)',
    'public.manager_user_remove(uuid, uuid, uuid)', 'public.manager_user_block(uuid, boolean)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
