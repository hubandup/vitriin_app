-- Import des points de vente : RPC appelée par l'Espace Centrale.
-- Admin du réseau vérifié côté serveur ; doublons (nom + code postal) ignorés ;
-- téléphone illisible ignoré ; adresse web générée et unique.
create or replace function public.import_network_stores(p_network_id uuid, p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  r jsonb;
  i int := 0;
  v_name text; v_city text; v_pc text; v_addr text; v_email text; v_first text; v_last text; v_phone text;
  v_slug text; v_base text; v_n int;
  created jsonb := '[]'::jsonb; skipped jsonb := '[]'::jsonb; errors jsonb := '[]'::jsonb;
  v_id uuid;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentification requise.' using errcode = 'insufficient_privilege';
  end if;
  if not public.is_network_admin(p_network_id) then
    raise exception 'Seuls les administrateurs de la centrale peuvent importer des magasins.' using errcode = 'insufficient_privilege';
  end if;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then
    raise exception 'Aucune ligne à importer.';
  end if;
  if jsonb_array_length(p_rows) > 1000 then
    raise exception 'Import limité à 1000 lignes par fichier.';
  end if;

  for r in select * from jsonb_array_elements(p_rows) loop
    i := i + 1;
    v_name  := left(nullif(btrim(r->>'name'), ''), 120);
    v_city  := left(nullif(btrim(r->>'city'), ''), 80);
    v_pc    := left(nullif(regexp_replace(coalesce(r->>'postal_code', ''), '\s', '', 'g'), ''), 10);
    v_addr  := left(nullif(btrim(r->>'address'), ''), 200);
    v_email := lower(left(nullif(btrim(r->>'email'), ''), 200));
    v_first := left(nullif(btrim(r->>'first_name'), ''), 60);
    v_last  := left(nullif(btrim(r->>'last_name'), ''), 60);
    v_phone := nullif(btrim(r->>'phone'), '');
    if v_phone !~ '^[0-9 +().-]{6,25}$' then v_phone := null; end if; -- téléphone illisible : ignoré

    if v_name is null then
      errors := errors || jsonb_build_object('line', i, 'error', 'Nom du magasin manquant');
      continue;
    end if;
    if v_email is not null and v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
      errors := errors || jsonb_build_object('line', i, 'name', v_name, 'error', 'Email invalide');
      continue;
    end if;

    -- Doublon : même nom et même code postal dans ce réseau.
    if exists (select 1 from public.stores s where s.network_id = p_network_id
               and lower(s.name) = lower(v_name) and coalesce(s.postal_code, '') = coalesce(v_pc, '')) then
      skipped := skipped || jsonb_build_object('line', i, 'name', v_name, 'reason', 'Déjà dans le réseau');
      continue;
    end if;

    -- Adresse web du magasin : le nom, plus la ville si le nom ne la contient pas.
    v_base := v_name || case when v_city is not null and position(lower(v_city) in lower(v_name)) = 0 then '-' || v_city else '' end;
    v_base := trim(both '-' from regexp_replace(lower(public.unaccent_simple(v_base)), '[^a-z0-9]+', '-', 'g'));
    if v_base = '' then v_base := 'magasin'; end if;
    v_base := left(v_base, 60);
    v_slug := v_base; v_n := 1;
    while exists (select 1 from public.stores s where s.slug = v_slug) loop
      v_n := v_n + 1; v_slug := v_base || '-' || v_n;
    end loop;

    insert into public.stores (slug, name, address, city, postal_code, network_id,
                               contact_email, contact_first_name, contact_last_name, contact_phone)
    values (v_slug, v_name, v_addr, v_city, v_pc, p_network_id, v_email, v_first, v_last, v_phone)
    returning id into v_id;
    created := created || jsonb_build_object('line', i, 'id', v_id, 'name', v_name, 'email', v_email);
  end loop;

  return jsonb_build_object('created', created, 'skipped', skipped, 'errors', errors);
end;
$$;
revoke all on function public.import_network_stores(uuid, jsonb) from public, anon;
grant execute on function public.import_network_stores(uuid, jsonb) to authenticated;
