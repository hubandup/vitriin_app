-- Manager Vitriin : super admins, secteurs de démo, générateur et bascule de démo.
-- Tout passe par des fonctions SECURITY DEFINER qui vérifient is_platform_admin()
-- côté serveur. Les tables platform_admins et demo_sectors n'ont aucune policy :
-- illisibles depuis le navigateur.

create table if not exists public.platform_admins (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.platform_admins enable row level security;
revoke all on public.platform_admins from anon, authenticated;

create or replace function public.is_platform_admin()
returns boolean language sql stable security definer set search_path to '' as $$
  select exists (select 1 from public.platform_admins a where a.user_id = (select auth.uid()));
$$;
revoke all on function public.is_platform_admin() from public, anon;
grant execute on function public.is_platform_admin() to authenticated;

insert into public.platform_admins (user_id)
select id from auth.users where lower(email) = 'charles@hubandup.com'
on conflict do nothing;

alter table public.networks add column if not exists demo_sector text;

create table if not exists public.demo_sectors (
  key text primary key,
  label text not null,
  brand text not null,
  category text not null,
  generated boolean not null default true,
  promos jsonb not null default '[]',
  own_promos jsonb not null default '[]',
  sort int not null default 0
);
alter table public.demo_sectors enable row level security;
revoke all on public.demo_sectors from anon, authenticated;

-- Chausselandia : démo retail construite à la main, conservée telle quelle.
insert into public.demo_sectors (key, label, brand, category, generated, sort)
values ('retail', 'Retail · chaussures', 'Chausselandia', 'chaussures', false, 0)
on conflict (key) do nothing;
update public.networks
set demo_sector = 'retail',
    settings = settings || jsonb_build_object('demo_store_id', 'ed369195-38af-4d8b-9449-be05d218ee32')
where id = 'a9888a31-6335-475b-8cc0-f8ccfb2a7c80';

-- Image Unsplash au format de l'app.
create or replace function public.demo_img(p_id text)
returns text language sql immutable set search_path to '' as $$
  select 'https://images.unsplash.com/photo-' || p_id || '?auto=format&fit=crop&w=1080&q=80';
$$;

insert into public.demo_sectors (key, label, brand, category, sort, promos, own_promos) values
('cheminees', 'Cheminées et poêles', 'Flamme & Foyer', 'cheminees', 1,
 '[
  {"title":"Poêles à granulés : l''offre d''automne","mech":"-15 %","type":"percent","val":15,"orig":2490,"desc":"-15 % sur toute la gamme de poêles à granulés, pose comprise. Étude gratuite à domicile.","code":"GRANULE15","img":"1580033151115-bc4e13704bb6","start":-6,"days":25},
  {"title":"Ramonage offert","mech":"Ramonage offert dès 1 500 € d''achat","type":"free_with_condition","desc":"Pour l''achat d''un poêle ou d''un insert dès 1 500 €, le premier ramonage est offert.","code":"RAMONAGE","img":"1543393470-b2c833b98dce","start":-3,"days":30,"mand":true},
  {"title":"Inserts bois : prix choc","mech":"1 290 € au lieu de 1 690 €","type":"new_price","val":1290,"orig":1690,"desc":"Notre insert bois best-seller à prix exceptionnel. Installation par nos poseurs certifiés.","code":"INSERT400","img":"1586299576722-e14abcdcfcb3","start":-10,"days":20},
  {"title":"Bois de chauffage : le 3e stère offert","mech":"2 achetés, le 3e offert","type":"x_plus_y","desc":"Bois sec de qualité, livré chez vous. Pour 2 stères achetés, le 3e est offert.","code":"BOIS3","img":"1485965089147-0f655dcf01b0","start":-2,"days":14},
  {"title":"Portes ouvertes de la flamme","mech":"-10 %","type":"percent","val":10,"desc":"Trois jours pour découvrir nos foyers en fonctionnement, avec -10 % sur tout le magasin.","code":"PORTES10","img":"1773847408152-4e06dec54cf4","start":5,"days":3},
  {"title":"Cheminées design","mech":"-20 %","type":"percent","val":20,"orig":4900,"desc":"Nos cheminées contemporaines à -20 % : foyers vitrés, double face, suspendues.","code":"DESIGN20","img":"1529337466672-5b3653da4c9a","start":-40,"days":21},
  {"title":"Black Friday du chauffage","mech":"-25 %","type":"percent","val":25,"desc":"Quatre jours de prix exceptionnels sur les poêles, inserts et accessoires.","code":"BLACK25","img":"1774204834734-b3f799062993","start":28,"days":4}
 ]',
 '[
  {"title":"Diagnostic de votre poêle offert","mech":"Diagnostic offert","type":"free_with_condition","desc":"Nos techniciens vérifient gratuitement votre appareil avant l''hiver. Sur rendez-vous en magasin.","img":"1631630259742-c0f0b17c6c10","start":-1,"days":10},
  {"title":"Accessoires de cheminée","mech":"-30 %","type":"percent","val":30,"desc":"Serviteurs, pare-feux et paniers à bûches à -30 % dans votre magasin.","code":"ACCESS30","img":"1496347315686-5f274d046ccc","start":-4,"days":12}
 ]'),
('jardinerie', 'Jardinerie', 'Jardins & Saisons', 'jardinerie', 2,
 '[
  {"title":"Fête des plantes d''automne","mech":"-20 %","type":"percent","val":20,"desc":"-20 % sur les arbustes, vivaces et plantes de saison. C''est le moment de planter !","code":"AUTOMNE20","img":"1601985705806-5b9a71f6004f","start":-5,"days":16},
  {"title":"Bulbes de printemps","mech":"3 achetés, le 4e offert","type":"x_plus_y","desc":"Tulipes, narcisses, jacinthes : préparez le printemps, le 4e sachet est offert.","code":"BULBES4","img":"1703846670348-acc8c77980ee","start":-8,"days":30,"mand":true},
  {"title":"Plantes d''intérieur","mech":"-30 % sur la 2e plante","type":"percent","val":30,"desc":"Monstera, ficus, pothos : -30 % sur la deuxième plante d''intérieur achetée.","code":"INTERIEUR","img":"1641816482997-515cdf9bb054","start":-2,"days":14},
  {"title":"Rosiers en pot","mech":"9,90 € au lieu de 14,90 €","type":"new_price","val":9.9,"orig":14.9,"desc":"Rosiers buissons en pot de 4 litres, plus de 20 variétés en magasin.","code":"ROSIER","img":"1618389013014-04d08547bd7f","start":-12,"days":20},
  {"title":"Cactus et succulentes","mech":"-15 %","type":"percent","val":15,"desc":"Toute la collection de cactus et succulentes à -15 %.","code":"CACTUS15","img":"1602080243654-17600ddb9bbf","start":4,"days":10},
  {"title":"Chrysanthèmes de la Toussaint","mech":"2 achetés, le 3e offert","type":"x_plus_y","desc":"Pour la Toussaint, le 3e chrysanthème est offert.","code":"TOUSSAINT","img":"1568531630267-69d89f364e6c","start":-20,"days":12},
  {"title":"Noël au jardin : les sapins arrivent","mech":"-10 %","type":"percent","val":10,"desc":"Nordmann, épicéas et décorations : -10 % pour l''ouverture de la saison de Noël.","code":"SAPIN10","img":"1525033842647-a956848705f0","start":25,"days":30}
 ]',
 '[
  {"title":"Atelier rempotage gratuit","mech":"Atelier offert samedi","type":"free_with_condition","desc":"Apportez votre plante, on la rempote avec vous. Samedi de 10 h à 12 h.","img":"1647550232391-f758832be5c2","start":-1,"days":6},
  {"title":"Pots et jardinières","mech":"-25 %","type":"percent","val":25,"desc":"Terre cuite, résine, céramique : -25 % sur tous les contenants.","code":"POTS25","img":"1560107379-95e9ca7803e0","start":-3,"days":12}
 ]')
on conflict (key) do update set label = excluded.label, brand = excluded.brand, category = excluded.category,
  promos = excluded.promos, own_promos = excluded.own_promos, sort = excluded.sort;

-- Une promo de démo : la promotion, puis (si p_store est null) son envoi au réseau.
create or replace function public.demo_make_promo(p_net uuid, p_store uuid, x jsonb)
returns uuid language plpgsql security definer set search_path to '' as $$
declare
  v_id uuid; v_start timestamptz; v_end timestamptz; v_code text := nullif(x->>'code', '');
  v_url text := public.demo_img(x->>'img');
begin
  v_start := date_trunc('day', now()) + make_interval(days => (x->>'start')::int);
  v_end := v_start + make_interval(days => (x->>'days')::int) - interval '1 minute';
  insert into public.promotions (created_by_network_id, created_by_store_id, title, description, mechanic, media_url,
    starts_at, ends_at, is_mandatory, status, created_at, promo_type, discount_code, details)
  values (case when p_store is null then p_net end, p_store, x->>'title',
    concat_ws(e'\n\n', x->>'desc', case when v_code is not null then 'Code en caisse : ' || v_code end),
    x->>'mech', v_url, v_start, v_end, coalesce((x->>'mand')::boolean, false), 'active',
    least(now(), v_start - interval '3 days'), x->>'type', v_code,
    jsonb_strip_nulls(jsonb_build_object('val', x->'val', 'orig', x->'orig', 'kind', 'promo',
      'media', jsonb_build_array(v_url), 'formats', jsonb_build_array('instagram:feed', 'facebook:photo'))))
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.demo_make_promo(uuid, uuid, jsonb) from public, anon, authenticated;

-- Publications et codes utilisés simulés pour une activation.
create or replace function public.demo_fill_activation(p_sp uuid, p_boost int default 0)
returns void language plpgsql security definer set search_path to '' as $$
declare
  sp record; ac record; v_at timestamptz; r numeric; v numeric; re numeric; co numeric; f numeric; live boolean;
  n int; k int; v_from timestamptz;
begin
  select s.id, s.store_id, s.promotion_id, s.activated_at, p.starts_at, p.ends_at, p.discount_code
    into sp from public.store_promotions s join public.promotions p on p.id = s.promotion_id where s.id = p_sp;
  for ac in select channel, status from public.social_accounts where store_id = sp.store_id loop
    v_at := greatest(sp.starts_at, coalesce(sp.activated_at, sp.starts_at)) + make_interval(mins => (30 + random() * 600)::int);
    if ac.status <> 'active' then
      if v_at <= now() then
        insert into public.publications (store_promotion_id, channel, status, error_message, created_at)
        values (p_sp, ac.channel, 'failed', 'Compte à reconnecter : la connexion à Instagram a expiré.', v_at);
      end if;
      continue;
    end if;
    r := (case when ac.channel = 'facebook' then 160 else 120 end) + random() * 560;
    v := r * (1.6 + random() * 2); re := r * (0.025 + random() * 0.05); co := re * (0.1 + random() * 0.2);
    live := v_at > now() - interval '2 days';
    f := case when v_at > now() then 0 when live then least(1, extract(epoch from now() - v_at) / 86400) else 1 end;
    insert into public.publications (store_promotion_id, channel, status, published_at, created_at, metrics, metrics_fetched_at)
    values (p_sp, ac.channel, case when v_at <= now() then 'published' else 'pending' end::public.publication_status, v_at, least(v_at, now()),
      jsonb_build_object('demo', true, 'live', live or v_at > now(),
        'target_reach', round(r), 'target_views', round(v), 'target_reactions', round(re), 'target_comments', round(co),
        'reach', round(r * f), 'views', round(v * f), 'reactions', round(re * f), 'comments', round(co * f)),
      case when v_at <= now() then now() end);
  end loop;

  -- Codes révélés en vitrine (drive to store), promos commencées avec un code.
  if sp.discount_code is not null and sp.starts_at < now() then
    v_from := greatest(sp.starts_at, now() - interval '14 days');
    n := floor(random() * 6)::int + p_boost;
    for k in 1..n loop
      v_at := v_from + random() * (least(now(), sp.ends_at) - v_from);
      insert into public.code_reveals (store_promotion_id, store_id, promotion_id, client_id, revealed_on, revealed_at, source)
      values (p_sp, sp.store_id, sp.promotion_id, 'demo-' || md5(random()::text), v_at::date, v_at, 'demo');
    end loop;
  end if;
end;
$$;
revoke all on function public.demo_fill_activation(uuid, int) from public, anon, authenticated;

-- Supprime un réseau de démo et tout son contenu.
create or replace function public.demo_drop_network(p_net uuid)
returns void language plpgsql security definer set search_path to '' as $$
begin
  if not exists (select 1 from public.networks where id = p_net and is_demo) then
    raise exception 'Seul un réseau de démonstration peut être supprimé ici.';
  end if;
  delete from public.promotions where created_by_store_id in (select id from public.stores where network_id = p_net);
  delete from public.promotions where created_by_network_id = p_net;
  delete from public.stores where network_id = p_net;
  delete from public.networks where id = p_net;
end;
$$;
revoke all on function public.demo_drop_network(uuid) from public, anon, authenticated;

-- Fait pointer les comptes de démo (centrale : l'admin qui appelle ; magasin :
-- magasin.demo@vitriin.co) vers ce réseau de démo.
create or replace function public.manager_activate_demo(p_network_id uuid)
returns void language plpgsql security definer set search_path to '' as $$
declare v_me uuid := (select auth.uid()); v_store uuid; v_demo_user uuid;
begin
  if not public.is_platform_admin() then raise exception 'Accès réservé à l''équipe Vitriin.' using errcode = '42501'; end if;
  if not exists (select 1 from public.networks where id = p_network_id and is_demo) then
    raise exception 'Ce réseau n''est pas une démo.';
  end if;

  -- Centrale : une seule appartenance de démo à la fois (mise à jour, pas suppression).
  if exists (select 1 from public.network_members where network_id = p_network_id and user_id = v_me) then
    null; -- déjà sur cette démo
  elsif exists (select 1 from public.network_members m join public.networks n on n.id = m.network_id
             where m.user_id = v_me and n.is_demo) then
    update public.network_members m set network_id = p_network_id
      from public.networks n
      where n.id = m.network_id and n.is_demo and m.user_id = v_me;
  else
    insert into public.network_members (network_id, user_id, role) values (p_network_id, v_me, 'owner')
    on conflict do nothing;
  end if;

  -- Magasin : le compte de démonstration va sur le magasin vitrine du réseau.
  select id into v_demo_user from auth.users where lower(email) = 'magasin.demo@vitriin.co';
  select coalesce((select (settings->>'demo_store_id')::uuid from public.networks where id = p_network_id),
                  (select id from public.stores where network_id = p_network_id order by name limit 1)) into v_store;
  if v_demo_user is not null and v_store is not null then
    delete from public.store_members m using public.stores s, public.networks n
      where s.id = m.store_id and n.id = s.network_id and n.is_demo and m.user_id = v_demo_user;
    insert into public.store_members (store_id, user_id, role) values (v_store, v_demo_user, 'owner')
    on conflict do nothing;
  end if;
end;
$$;
revoke all on function public.manager_activate_demo(uuid) from public, anon;
grant execute on function public.manager_activate_demo(uuid) to authenticated;

-- Construit (ou reconstruit) la démo d'un secteur. Rend l'id du réseau.
create or replace function public.manager_build_demo(p_sector text)
returns uuid language plpgsql security definer set search_path to '' as $$
declare
  sec public.demo_sectors; v_old uuid; v_was_active boolean := false; v_net uuid; v_store uuid; v_store0 uuid;
  v_tag text := substr(md5(random()::text), 1, 5); i int; c jsonb; x jsonb; v_p uuid; sp record;
  cities jsonb := '[
    ["Lyon","69003",45.7597,4.8422],["Paris 15e","75015",48.8417,2.3000],["Marseille","13008",43.2410,5.3870],
    ["Toulouse","31500",43.6110,1.4600],["Bordeaux","33300",44.8640,-0.5650],["Nantes","44300",47.2500,-1.5300],
    ["Lille","59160",50.6330,2.9800],["Strasbourg","67200",48.5830,7.7100],["Montpellier","34070",43.5900,3.8600],
    ["Rennes","35200",48.0900,-1.6700],["Grenoble","38100",45.1700,5.7200],["Dijon","21000",47.3220,5.0410],
    ["Annecy","74000",45.8990,6.1290],["Clermont-Ferrand","63100",45.7900,3.0900],["Tours","37100",47.4100,0.6900],
    ["Angers","49000",47.4700,-0.5500],["Reims","51100",49.2500,4.0300],["Nice","06200",43.6800,7.2200],
    ["Rouen","76100",49.4200,1.0800],["Metz","57050",49.1300,6.1700]]';
begin
  if not public.is_platform_admin() then raise exception 'Accès réservé à l''équipe Vitriin.' using errcode = '42501'; end if;
  select * into sec from public.demo_sectors where key = p_sector and generated;
  if sec.key is null then raise exception 'Secteur de démo inconnu.'; end if;

  select n.id into v_old from public.networks n where n.is_demo and n.demo_sector = p_sector limit 1;
  if v_old is not null then
    v_was_active := exists (select 1 from public.network_members where network_id = v_old and user_id = (select auth.uid()));
    -- La démo active est d'abord rendue à Chausselandia, le temps de reconstruire.
    if v_was_active then
      perform public.manager_activate_demo(coalesce(
        (select id from public.networks where is_demo and demo_sector = 'retail' limit 1),
        (select id from public.networks where is_demo and id <> v_old limit 1)));
    end if;
    perform public.demo_drop_network(v_old);
  end if;

  insert into public.networks (name, slug, join_code, is_demo, demo_sector, legal_name, address, support_email, phone, settings, created_at)
  values (sec.brand, 'demo-' || p_sector || '-' || v_tag, upper(substr(md5(random()::text), 1, 8)), true, p_sector,
    sec.brand || ' SAS', '12 avenue de la République, 69003 Lyon',
    'contact@' || regexp_replace(lower(public.unaccent_simple(sec.brand)), '[^a-z0-9]+', '', 'g') || '.fr', '04 78 00 00 00',
    jsonb_build_object('ean_code', false, 'store_edit', true, 'auto_accept', false, 'store_delete', true, 'discount_code', true),
    now() - interval '120 days')
  returning id into v_net;

  for i in 0 .. jsonb_array_length(cities) - 1 loop
    c := cities->i;
    insert into public.stores (network_id, slug, name, address, city, postal_code, lat, lng, category, created_at, auto_accept)
    values (v_net, 'demo-' || p_sector || '-' || v_tag || '-' || i, sec.brand || ' ' || (c->>0),
      (10 + i * 7) || ' rue du Commerce, ' || (c->>1) || ' ' || (c->>0), c->>0, c->>1, (c->>2)::float8, (c->>3)::float8,
      sec.category, now() - make_interval(days => 40 + (random() * 60)::int), true)
    returning id into v_store;
    if i = 0 then v_store0 := v_store; end if;
    -- Comptes sociaux : la plupart complets, quelques partiels, un à reconnecter, deux sans rien.
    if i not in (17, 18) then
      insert into public.social_accounts (store_id, channel, external_account_id, display_name, status, connected_at)
      values (v_store, 'facebook', 'demo-fb-' || v_store, sec.brand || ' ' || (c->>0), 'active', now() - interval '35 days');
    end if;
    if i not in (14, 15, 16, 17, 18) then
      insert into public.social_accounts (store_id, channel, external_account_id, display_name, status, connected_at, last_error)
      values (v_store, 'instagram', 'demo-ig-' || v_store,
        lower(regexp_replace(public.unaccent_simple(sec.brand || '.' || (c->>0)), '[^A-Za-z0-9.]+', '', 'g')),
        case when i = 13 then 'error' else 'active' end::public.social_account_status, now() - interval '35 days',
        case when i = 13 then 'Session expirée' end);
    end if;
  end loop;
  update public.networks set settings = settings || jsonb_build_object('demo_store_id', v_store0) where id = v_net;

  -- Promos de la centrale, envoyées à tout le réseau.
  for x in select * from jsonb_array_elements(sec.promos) loop
    v_p := public.demo_make_promo(v_net, null, x);
    insert into public.store_promotions (promotion_id, store_id, created_at)
    select v_p, s.id, least(now(), (select starts_at from public.promotions where id = v_p) - interval '2 days')
    from public.stores s where s.network_id = v_net;
    -- La plupart des magasins activent ; quelques-uns n'ont pas encore répondu.
    update public.store_promotions spx set status = 'active'
    where spx.promotion_id = v_p and spx.status = 'pending'
      and (random() < 0.85 or spx.store_id = v_store0);
    update public.store_promotions spx
      set activated_at = least(now(), spx.created_at + make_interval(hours => (2 + random() * 40)::int))
    where spx.promotion_id = v_p and spx.status = 'active';
    for sp in select id, store_id from public.store_promotions where promotion_id = v_p and status = 'active' loop
      perform public.demo_fill_activation(sp.id, case when sp.store_id = v_store0 then 4 else 0 end);
    end loop;
  end loop;

  -- Promos créées par le magasin vitrine.
  for x in select * from jsonb_array_elements(sec.own_promos) loop
    v_p := public.demo_make_promo(v_net, v_store0, x);
    insert into public.store_promotions (promotion_id, store_id, created_at)
    values (v_p, v_store0, least(now(), (select starts_at from public.promotions where id = v_p) - interval '1 day'));
    update public.store_promotions set status = 'active', activated_at = created_at where promotion_id = v_p;
    perform public.demo_fill_activation((select id from public.store_promotions where promotion_id = v_p), 3);
  end loop;

  if v_was_active then perform public.manager_activate_demo(v_net); end if;
  return v_net;
end;
$$;
revoke all on function public.manager_build_demo(text) from public, anon;
grant execute on function public.manager_build_demo(text) to authenticated;

-- Vue d'ensemble pour le Manager : clients, démos, secteurs.
create or replace function public.manager_overview()
returns jsonb language plpgsql stable security definer set search_path to '' as $$
declare v_me uuid := (select auth.uid());
begin
  if not public.is_platform_admin() then raise exception 'Accès réservé à l''équipe Vitriin.' using errcode = '42501'; end if;
  return jsonb_build_object(
    'networks', coalesce((select jsonb_agg(x order by x.is_demo, x.name) from (
      select n.id, n.name, n.is_demo, n.demo_sector, n.logo_url, n.created_at,
        (select count(*) from public.stores s where s.network_id = n.id) stores,
        (select count(*) from public.stores s where s.network_id = n.id
           and exists (select 1 from public.social_accounts a where a.store_id = s.id and a.status = 'active')) connected,
        (select count(*) from public.promotions p where p.created_by_network_id = n.id) promos,
        (select count(*) from public.publications pu join public.store_promotions sp on sp.id = pu.store_promotion_id
           join public.stores s on s.id = sp.store_id where s.network_id = n.id and pu.status = 'published') published,
        (select coalesce(jsonb_agg(u.email order by u.email), '[]') from public.network_members m join auth.users u on u.id = m.user_id
           where m.network_id = n.id) members,
        exists (select 1 from public.network_members m where m.network_id = n.id and m.user_id = v_me) as active
      from public.networks n) x), '[]'),
    'sectors', coalesce((select jsonb_agg(jsonb_build_object('key', d.key, 'label', d.label, 'brand', d.brand,
        'generated', d.generated, 'promos', jsonb_array_length(d.promos)) order by d.sort) from public.demo_sectors d), '[]'),
    'independent_stores', (select count(*) from public.stores where network_id is null)
  );
end;
$$;
revoke all on function public.manager_overview() from public, anon;
grant execute on function public.manager_overview() to authenticated;
