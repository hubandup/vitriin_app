-- =============================================================================
-- Démo « Chausselandia » : réseau de 20 magasins de chaussures
-- =============================================================================
-- Prérequis :
--   - le réseau de slug 'chausselandia' existe (créé depuis l'Espace Centrale) ;
--   - le compte magasin de démo existe (magasin.demo@vitriin.co), créé à part
--     pour que son mot de passe ne soit pas dans le dépôt.
--
-- Dates relatives au jour d'exécution. S'exécute sur un réseau vide.
--
-- Rien ici n'appelle Meta : les comptes sociaux sont factices (identifiants
-- « demo-… », sans jeton) et les publications portent metrics.demo = true.
-- =============================================================================

-- Publications d'une activation, une par compte connecté du magasin :
-- publiée avec des statistiques plausibles si le compte est actif, en échec
-- sinon. Fonction temporaire, propre à cette session.
create or replace function pg_temp.demo_seed_pub(p_sp uuid, p_store uuid, p_at timestamptz, p_k int)
returns void language plpgsql as $f$
declare a record; v int;
begin
  for a in select channel, status, external_account_id from public.social_accounts where store_id = p_store loop
    v := 280 + ((length(a.external_account_id) * 131 + p_k * 197 + (extract(epoch from p_at)::bigint % 997)) % 1600);
    if a.channel = 'instagram' then v := (v * 0.8)::int; end if;
    insert into public.publications (store_promotion_id, channel, status, error_message, published_at, metrics, metrics_fetched_at)
    values (p_sp, a.channel,
            case when a.status = 'active' then 'published' else 'failed' end::public.publication_status,
            case when a.status <> 'active' then 'Compte déconnecté : reconnectez-le.' end,
            p_at,
            case when a.status = 'active' then jsonb_build_object('demo', true, 'views', v, 'reach', (v * 0.62)::int,
                 'reactions', (v * 0.045)::int, 'comments', (v * 0.006)::int, 'shares', (v * 0.004)::int)
                 else '{"demo":true}'::jsonb end,
            now())
    on conflict (store_promotion_id, channel) do nothing;
  end loop;
end;
$f$;

do $$
declare
  v_net        uuid;
  v_demo_user  uuid;
  v_demo_store uuid;
  v_store      record;
  v_promo      record;
  v_sp         uuid;
  v_i          int;
  v_n          int;
  v_roll       float;
  v_pub_at     timestamptz;
  v_img        text := 'https://images.unsplash.com/%s?auto=format&fit=crop&w=1080&q=80';
  t0           timestamptz := date_trunc('day', now());
  c_red   text; c_grey text; c_lace text; c_trail text; c_phantom text; c_air text; c_bf text; c_socks text;
begin
  c_red     := format(v_img, 'photo-1542291026-7eec264c27ff');
  c_grey    := format(v_img, 'photo-1491553895911-0055eca6402d');
  c_lace    := format(v_img, 'photo-1597892657493-6847b9640bac');
  c_trail   := format(v_img, 'photo-1560769629-975ec94e6a86');
  c_phantom := format(v_img, 'photo-1606107557195-0e29a4b5b4aa');
  c_air     := format(v_img, 'photo-1600185365926-3a2ce3cdb9eb');
  c_bf      := format(v_img, 'photo-1758506971683-c080e6f16ce9');
  c_socks   := format(v_img, 'photo-1571008887538-b36bb32f4571');

  select id into v_net from public.networks where slug = 'chausselandia';
  if v_net is null then raise exception 'Réseau chausselandia introuvable'; end if;

  select id into v_demo_user from auth.users where email = 'magasin.demo@vitriin.co';
  if v_demo_user is null then raise exception 'Compte magasin.demo@vitriin.co introuvable'; end if;

  -- Pas de nettoyage automatique : pour rejouer, supprimer d'abord les
  -- magasins et promos du réseau (opération destructive, à faire à la main).
  if exists (select 1 from public.stores where network_id = v_net) then
    raise exception 'Le réseau contient déjà des magasins : nettoyage nécessaire avant de rejouer.';
  end if;

  update public.networks set name = 'Chausselandia', is_demo = true where id = v_net;

  -- ---------------------------------------------------------------------------
  -- 20 magasins
  -- ---------------------------------------------------------------------------
  create temp table demo_stores (k int, name text, address text, city text, pc text, lat float, lng float) on commit drop;
  insert into demo_stores values
    ( 0, 'Chausselandia Lyon Presqu''île', '25 rue de la République', 'Lyon', '69002', 45.7620, 4.8357),
    ( 1, 'Chausselandia Paris Rivoli', '112 rue de Rivoli', 'Paris', '75001', 48.8606, 2.3426),
    ( 2, 'Chausselandia Paris Montparnasse', '58 rue de Rennes', 'Paris', '75006', 48.8467, 2.3290),
    ( 3, 'Chausselandia Boulogne', '87 boulevard Jean-Jaurès', 'Boulogne-Billancourt', '92100', 48.8397, 2.2399),
    ( 4, 'Chausselandia Marseille Canebière', '41 la Canebière', 'Marseille', '13001', 43.2970, 5.3810),
    ( 5, 'Chausselandia Aix-en-Provence', '12 cours Mirabeau', 'Aix-en-Provence', '13100', 43.5265, 5.4474),
    ( 6, 'Chausselandia Nice Masséna', '8 avenue Jean-Médecin', 'Nice', '06000', 43.7019, 7.2680),
    ( 7, 'Chausselandia Montpellier Comédie', '5 rue de la Loge', 'Montpellier', '34000', 43.6110, 3.8770),
    ( 8, 'Chausselandia Toulouse Capitole', '30 rue d''Alsace-Lorraine', 'Toulouse', '31000', 43.6045, 1.4442),
    ( 9, 'Chausselandia Bordeaux Sainte-Catherine', '96 rue Sainte-Catherine', 'Bordeaux', '33000', 44.8378, -0.5737),
    (10, 'Chausselandia La Rochelle', '18 rue du Palais', 'La Rochelle', '17000', 46.1603, -1.1511),
    (11, 'Chausselandia Nantes Commerce', '3 place du Commerce', 'Nantes', '44000', 47.2130, -1.5600),
    (12, 'Chausselandia Rennes', '14 rue Le Bastard', 'Rennes', '35000', 48.1120, -1.6800),
    (13, 'Chausselandia Tours', '60 rue Nationale', 'Tours', '37000', 47.3930, 0.6880),
    (14, 'Chausselandia Lille Grand-Place', '22 rue Neuve', 'Lille', '59000', 50.6372, 3.0633),
    (15, 'Chausselandia Reims', '45 rue de Vesle', 'Reims', '51100', 49.2550, 4.0300),
    (16, 'Chausselandia Strasbourg Kléber', '9 place Kléber', 'Strasbourg', '67000', 48.5839, 7.7455),
    (17, 'Chausselandia Dijon', '33 rue de la Liberté', 'Dijon', '21000', 47.3220, 5.0400),
    (18, 'Chausselandia Grenoble', '10 rue Félix-Poulat', 'Grenoble', '38000', 45.1885, 5.7245),
    (19, 'Chausselandia Annecy', '7 rue Royale', 'Annecy', '74000', 45.8992, 6.1294);

  for v_store in select * from demo_stores order by k loop
    insert into public.stores (network_id, slug, name, address, city, postal_code, lat, lng, category, created_at)
    values (v_net, 'chausselandia-' || v_store.k || '-' || lower(regexp_replace(translate(v_store.city, 'éèêëàâîïôöûüçÉ', 'eeeeaaiioouucE'), '[^a-zA-Z0-9]+', '-', 'g')),
            v_store.name, v_store.address || ', ' || v_store.pc || ' ' || v_store.city, v_store.city, v_store.pc,
            v_store.lat, v_store.lng, 'chaussures', now() - ((60 - v_store.k) || ' days')::interval)
    returning id into v_sp;

    if v_store.k = 0 then
      v_demo_store := v_sp;
      insert into public.store_members (store_id, user_id, role) values (v_sp, v_demo_user, 'owner');
      -- Facebook connecté, Instagram à reconnecter : montre le parcours de réparation.
      insert into public.social_accounts (store_id, channel, external_account_id, display_name, status, last_error, last_error_at, connected_at)
      values (v_sp, 'facebook', 'demo-fb-0', 'Chausselandia Lyon Presqu''île', 'active', null, null, now() - interval '40 days');
      insert into public.social_accounts (store_id, channel, external_account_id, parent_external_id, display_name, status, last_error, last_error_at, connected_at)
      values (v_sp, 'instagram', 'demo-ig-0', 'demo-fb-0', '@chausselandia.lyon', 'error', 'Session expirée', now() - interval '2 days', now() - interval '40 days');
    else
      -- 0-6 : Facebook + Instagram ; 7 : Facebook seul ; 8 : Instagram en erreur ; 9 : rien.
      if v_store.k % 10 <> 9 then
        insert into public.social_accounts (store_id, channel, external_account_id, display_name, status, connected_at)
        values (v_sp, 'facebook', 'demo-fb-' || v_store.k, v_store.name, 'active', now() - ((50 - v_store.k) || ' days')::interval);
      end if;
      if v_store.k % 10 not in (7, 9) then
        insert into public.social_accounts (store_id, channel, external_account_id, parent_external_id, display_name, status, last_error, connected_at)
        values (v_sp, 'instagram', 'demo-ig-' || v_store.k, 'demo-fb-' || v_store.k,
                '@chausselandia.' || lower(regexp_replace(translate(v_store.city, 'éèêëàâîïôöûüçÉ', 'eeeeaaiioouucE'), '[^a-zA-Z0-9]+', '', 'g')) || v_store.k,
                (case when v_store.k % 10 = 8 then 'error' else 'active' end)::public.social_account_status,
                case when v_store.k % 10 = 8 then 'Session expirée' end,
                now() - ((50 - v_store.k) || ' days')::interval);
      end if;
    end if;
  end loop;

  -- ---------------------------------------------------------------------------
  -- 10 promos de la centrale
  -- ---------------------------------------------------------------------------
  create temp table demo_promos (k int, title text, mech text, descr text, ptype text, code text, img text,
                                 s timestamptz, e timestamptz, mand boolean, details jsonb, demo_state text) on commit drop;
  insert into demo_promos values
    (1, 'Semaine de la sneaker', '-25 %', 'Toutes les sneakers de la sélection à -25 %. Venez les essayer en magasin !', 'percent', 'SNEAK25', c_red,
        t0 - interval '5 days', t0 + interval '9 days 23:59', false, '{"orig":119,"val":25}', 'published'),
    (2, 'Bottines cuir d''automne', '-30 %', 'Nos bottines en cuir à -30 % pour bien commencer la saison.', 'percent', 'BOTTI30', c_grey,
        t0 - interval '8 days', t0 + interval '6 days 23:59', true, '{"orig":139,"val":30}', 'due'),
    (3, 'La 2e paire à -50 %', '2e paire à -50 %', 'Sur toute la collection femme : la deuxième paire à moitié prix.', 'x_plus_y', 'PAIRE50', c_lace,
        t0 - interval '1 day', t0 + interval '12 days 23:59', false, '{"sub":"Sur toute la collection femme"}', 'pending'),
    (4, 'Running Phantom Glide', '89,90 € au lieu de 119,90 €', 'La Phantom Glide à prix doux, dans la limite des stocks.', 'new_price', 'GLIDE89', c_phantom,
        t0 - interval '2 days', t0 + interval '16 days 23:59', false, '{"orig":119.9,"val":89.9}', 'active'),
    (5, 'Trail Spark', '-20 %', 'Le trail de la saison à -20 %. Idéal pour les sorties d''automne.', 'percent', 'TRAIL20', c_trail,
        t0, t0 + interval '14 days 23:59', false, '{"orig":89,"val":20}', 'pending'),
    (6, 'Black Friday', '-40 % sur une sélection', 'Le Black Friday Chausselandia : -40 % sur une sélection de modèles, 4 jours seulement.', 'percent', 'BF40', c_bf,
        timestamptz '2026-11-27 00:00+01', timestamptz '2026-11-30 23:59+01', true, '{"val":40,"sub":"Sur une sélection de modèles"}', 'scheduled'),
    (7, 'Cyber Week', '-15 € dès 80 €', '15 € de remise immédiate dès 80 € d''achat en magasin.', 'amount', 'CYBER15', c_air,
        timestamptz '2026-12-01 00:00+01', timestamptz '2026-12-07 23:59+01', false, '{"val":15,"sub":"Dès 80 € d''achat"}', 'pending'),
    (8, 'Chaussons offerts', 'Chaussons offerts dès 60 € d''achat', 'Pour Noël, une paire de chaussons offerte dès 60 € d''achat.', 'free_with_condition', 'NOEL60', c_socks,
        timestamptz '2026-12-10 00:00+01', timestamptz '2026-12-24 19:00+01', false, '{"sub":"Dès 60 € d''achat"}', 'pending'),
    (9, 'Carte fidélité : 10 % cagnottés', '10 % cagnottés', 'Avec la carte Chausselandia, 10 % de vos achats cagnottés ce mois-ci.', 'cashback', 'FIDELITE10', c_air,
        t0 - interval '20 days', t0 + interval '30 days 23:59', false, '{"val":10}', 'published'),
    (10, 'Entretien du cuir : 2 + 1 offert', '2 achetés, le 3e offert', 'Cirages, imperméabilisants, brosses : 2 produits achetés, le 3e offert.', 'x_plus_y', 'SOIN3', c_lace,
        t0 - interval '12 days', t0 + interval '18 days 23:59', false, '{"xy":[2,1],"orig":29.7,"val":19.8,"sub":"Les 3 pour 19,80 €"}', 'declined');

  for v_promo in select * from demo_promos order by k loop
    insert into public.promotions (created_by_network_id, title, mechanic, description, promo_type, discount_code, media_url,
                                   starts_at, ends_at, is_mandatory, status, details, created_at)
    values (v_net, v_promo.title, v_promo.mech, v_promo.descr || E'\n\nCode en caisse : ' || v_promo.code, v_promo.ptype, v_promo.code, v_promo.img,
            v_promo.s, v_promo.e, v_promo.mand, 'active', v_promo.details,
            least(v_promo.s, now()) - interval '2 days')
    returning id into v_sp;

    -- Une activation par magasin (le trigger pose pending, ou active si obligatoire).
    insert into public.store_promotions (promotion_id, store_id, created_at)
    select v_sp, s.id, least(v_promo.s, now()) - interval '2 days' from public.stores s where s.network_id = v_net;

    -- États magasin par magasin.
    v_n := 0;
    for v_store in
      select sp.id as sp_id, s.id as store_id, d.k
      from public.store_promotions sp
      join public.stores s on s.id = sp.store_id
      join demo_stores d on d.name = s.name
      where sp.promotion_id = v_sp
    loop
      v_roll := ((v_store.k * 37 + v_promo.k * 11) % 100) / 100.0;   -- pseudo-aléatoire stable

      if v_store.k = 0 then
        -- Le magasin de démo : un état choisi par promo pour raconter l'histoire.
        if v_promo.demo_state = 'published' then
          update public.store_promotions set status = 'active', activated_at = v_promo.s + interval '3 hours' where id = v_store.sp_id;
          perform pg_temp.demo_seed_pub(v_store.sp_id, v_store.store_id, v_promo.s + interval '4 hours', v_promo.k);
        elsif v_promo.demo_state = 'active' then
          update public.store_promotions set status = 'active', activated_at = now() - interval '5 hours' where id = v_store.sp_id;
        elsif v_promo.demo_state = 'declined' then
          update public.store_promotions set status = 'declined' where id = v_store.sp_id;
        elsif v_promo.demo_state = 'scheduled' then
          insert into public.publications (store_promotion_id, channel, status, published_at, metrics)
          values (v_store.sp_id, 'facebook', 'pending', v_promo.s + interval '9 hours',
                  '{"demo":true,"live":true,"target_reach":900,"target_views":1600,"target_reactions":60,"target_comments":7,"reach":0,"views":0,"reactions":0,"comments":0}');
        end if;
        -- 'due' (obligatoire actif non publié) et 'pending' : rien à faire.
        continue;
      end if;

      if v_promo.s > now() then
        -- À venir : quelques magasins ont déjà validé ou programmé.
        if v_promo.mand then
          if v_roll < 0.45 then
            insert into public.publications (store_promotion_id, channel, status, published_at, metrics)
            select v_store.sp_id, a.channel, 'pending', v_promo.s + interval '8 hours', '{"demo":true}'
            from public.social_accounts a where a.store_id = v_store.store_id and a.status = 'active';
          end if;
        elsif v_roll < 0.30 then
          update public.store_promotions set status = 'active' where id = v_store.sp_id;
        elsif v_roll > 0.92 then
          update public.store_promotions set status = 'declined' where id = v_store.sp_id;
        end if;
      elsif v_promo.k = 5 then
        -- Lancée aujourd'hui : la plupart n'ont pas encore répondu.
        if v_roll < 0.20 then
          update public.store_promotions set status = 'active' where id = v_store.sp_id;
          perform pg_temp.demo_seed_pub(v_store.sp_id, v_store.store_id, now() - interval '3 hours', v_promo.k);
        end if;
      else
        -- En cours : environ 70 % publient, le reste se répartit.
        if v_promo.mand or v_roll < 0.70 then
          update public.store_promotions set status = 'active', activated_at = v_promo.s + interval '2 hours' where id = v_store.sp_id;
          v_pub_at := least(now() - interval '1 hour', v_promo.s + ((v_store.k % 5) * 7 + 3 || ' hours')::interval);
          perform pg_temp.demo_seed_pub(v_store.sp_id, v_store.store_id, v_pub_at, v_promo.k);
        elsif v_roll < 0.80 then
          update public.store_promotions set status = 'active' where id = v_store.sp_id;
        elsif v_roll > 0.90 then
          update public.store_promotions set status = 'declined' where id = v_store.sp_id;
        end if;
      end if;
    end loop;
  end loop;

  -- Instagram du magasin de démo n'est tombé qu'il y a 2 jours : ses publications
  -- plus anciennes sont passées normalement.
  update public.publications p
  set status = 'published', error_message = null,
      metrics = jsonb_build_object('demo', true, 'views', 640, 'reach', 410, 'reactions', 31, 'comments', 4, 'shares', 2)
  from public.store_promotions sp
  where sp.id = p.store_promotion_id and sp.store_id = v_demo_store
    and p.channel = 'instagram' and p.status = 'failed' and p.published_at < now() - interval '2 days';

  -- ---------------------------------------------------------------------------
  -- 3 promos du magasin de démo
  -- ---------------------------------------------------------------------------
  insert into public.promotions (created_by_store_id, title, mechanic, description, promo_type, discount_code, media_url,
                                 starts_at, ends_at, is_mandatory, status, details, created_at)
  values (v_demo_store, 'Mocassins Presqu''île', '69 € au lieu de 89 €', 'Les mocassins cuir de la boutique à 69 € jusqu''à dimanche.', 'new_price', 'LYON69', c_grey,
          t0 - interval '2 days', t0 + interval '4 days 23:59', false, 'active', '{"orig":89,"val":69}', now() - interval '2 days')
  returning id into v_sp;
  insert into public.store_promotions (promotion_id, store_id) values (v_sp, v_demo_store) returning id into v_sp;
  update public.store_promotions set status = 'active', activated_at = now() - interval '26 hours' where id = v_sp;
  insert into public.publications (store_promotion_id, channel, status, published_at, metrics, metrics_fetched_at) values
    (v_sp, 'facebook', 'published', now() - interval '26 hours', '{"demo":true,"reach":490,"views":710,"reactions":27,"comments":3}', now()),
    (v_sp, 'instagram', 'failed', now() - interval '26 hours', '{"demo":true}', now());
  update public.publications set error_message = 'Compte Instagram déconnecté : reconnectez-le.' where store_promotion_id = v_sp and channel = 'instagram';

  insert into public.promotions (created_by_store_id, title, mechanic, description, promo_type, discount_code, media_url,
                                 starts_at, ends_at, is_mandatory, status, details, created_at)
  values (v_demo_store, 'Chaussettes laine : 2 + 1 offerte', '2 achetées, la 3e offerte', 'Les chaussettes en laine mérinos : 2 achetées, la 3e offerte.', 'x_plus_y', 'LAINE3', c_socks,
          t0 - interval '4 days', t0 + interval '10 days 23:59', false, 'active', '{"xy":[2,1],"orig":44.7,"val":29.8,"sub":"Les 3 pour 29,80 €"}', now() - interval '4 days')
  returning id into v_sp;
  insert into public.store_promotions (promotion_id, store_id) values (v_sp, v_demo_store) returning id into v_sp;
  update public.store_promotions set status = 'active', activated_at = now() - interval '3 days' where id = v_sp;
  insert into public.publications (store_promotion_id, channel, status, published_at, metrics, metrics_fetched_at) values
    (v_sp, 'facebook', 'published', now() - interval '3 days', '{"demo":true,"reach":808,"views":1142,"reactions":40,"comments":5}', now()),
    (v_sp, 'instagram', 'published', now() - interval '3 days', '{"demo":true,"reach":343,"views":677,"reactions":36,"comments":5}', now());

  insert into public.promotions (created_by_store_id, title, mechanic, description, promo_type, discount_code, media_url,
                                 starts_at, ends_at, is_mandatory, status, details, created_at)
  values (v_demo_store, 'Atelier cirage offert', 'Cirage offert dès 50 € d''achat', 'Samedi, notre atelier cirage est offert dès 50 € d''achat.', 'free_with_condition', null, null,
          t0 + interval '2 days', t0 + interval '9 days 23:59', false, 'draft', '{"sub":"Dès 50 € d''achat"}', now() - interval '1 hour')
  returning id into v_sp;
  insert into public.store_promotions (promotion_id, store_id) values (v_sp, v_demo_store);
end;
$$;
