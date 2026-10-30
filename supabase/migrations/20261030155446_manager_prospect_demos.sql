-- Démos au nom d'un prospect : même générateur que les démos sectorielles,
-- avec le nom et le logo du prospect. Marquées settings.prospect = true.

-- 1. Générateur interne, dérivé de manager_build_demo (sans suppression ni bascule).
do $do$
declare d text;
begin
  d := pg_get_functiondef('public.manager_build_demo(text)'::regprocedure);
  d := replace(d, 'FUNCTION public.manager_build_demo(p_sector text)',
                  'FUNCTION public.demo_build_network(p_sector text, p_brand text, p_logo text, p_prospect boolean)');
  -- pas de remplacement d'une démo existante : on retire le bloc v_old
  d := regexp_replace(d, '  select n\.id into v_old from public\.networks n.*?perform public\.demo_drop_network\(v_old\);\n  end if;\n', '', 's');
  d := replace(d, 'sec.brand', 'coalesce(nullif(btrim(p_brand), ''''), sec.brand)');
  d := replace(d, 'set logo_url = sec.logo_url', 'set logo_url = coalesce(p_logo, sec.logo_url)');
  d := replace(d, '''discount_code'', true)', '''discount_code'', true, ''prospect'', p_prospect)');
  if position('v_old' in d) > 0 and position('demo_drop_network(v_old)' in d) > 0 then
    raise exception 'Transformation incomplète du générateur.';
  end if;
  execute d;
end
$do$;
revoke all on function public.demo_build_network(text, text, text, boolean) from public, anon, authenticated;

-- 2. Les démos sectorielles ne remplacent jamais une démo prospect.
do $do$
declare d text;
begin
  d := pg_get_functiondef('public.manager_build_demo(text)'::regprocedure);
  d := replace(d, 'where n.is_demo and n.demo_sector = p_sector limit 1',
                  'where n.is_demo and n.demo_sector = p_sector and not coalesce((n.settings->>''prospect'')::boolean, false) limit 1');
  execute d;
  d := pg_get_functiondef('public.manager_overview()'::regprocedure);
  d := replace(d, 'select n.id, n.name, n.is_demo, n.demo_sector, n.logo_url, n.created_at,',
                  'select n.id, n.name, n.is_demo, n.demo_sector, coalesce((n.settings->>''prospect'')::boolean, false) prospect, n.logo_url, n.created_at,');
  execute d;
end
$do$;

-- 3. Créer / supprimer une démo prospect.
create or replace function public.manager_prospect_demo(p_sector text, p_brand text, p_logo text default null)
returns uuid language plpgsql security definer set search_path to '' as $$
begin
  perform public.manager_guard();
  if length(btrim(coalesce(p_brand, ''))) < 2 or length(p_brand) > 60 then raise exception 'Nom de l''enseigne : 2 à 60 caractères.'; end if;
  if p_logo is not null and p_logo !~ '^https://' then raise exception 'Le logo doit être une adresse https.'; end if;
  if not exists (select 1 from public.demo_sectors where key = p_sector and generated) then raise exception 'Secteur inconnu.'; end if;
  if (select count(*) from public.networks where is_demo and (settings->>'prospect')::boolean) >= 30 then
    raise exception 'Trop de démos prospects : supprimez-en avant d''en créer.';
  end if;
  return public.demo_build_network(p_sector, btrim(p_brand), p_logo, true);
end;
$$;
revoke all on function public.manager_prospect_demo(text, text, text) from public, anon;
grant execute on function public.manager_prospect_demo(text, text, text) to authenticated;

create or replace function public.manager_delete_demo(p_id uuid)
returns void language plpgsql security definer set search_path to '' as $$
begin
  perform public.manager_guard();
  if not exists (select 1 from public.networks where id = p_id and is_demo and (settings->>'prospect')::boolean) then
    raise exception 'Seule une démo prospect peut être supprimée.';
  end if;
  if exists (select 1 from public.network_members where network_id = p_id and user_id = (select auth.uid())) then
    perform public.manager_activate_demo(coalesce(
      (select id from public.networks where is_demo and demo_sector = 'retail' limit 1),
      (select id from public.networks where is_demo and id <> p_id limit 1)));
  end if;
  perform public.demo_drop_network(p_id);
end;
$$;
revoke all on function public.manager_delete_demo(uuid) from public, anon;
grant execute on function public.manager_delete_demo(uuid) to authenticated;

-- 4. Logos des démos : dossier demo/ du stockage, réservé à l'équipe Vitriin.
create policy promo_media_insert_platform_admin on storage.objects for insert to authenticated
  with check (bucket_id = 'promo-media' and (storage.foldername(name))[1] = 'demo' and public.is_platform_admin());
