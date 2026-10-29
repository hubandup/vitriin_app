# Journal de la plateforme Vitriin

Tout changement de la plateforme (bug, correction, modification) est noté ici,
du plus récent au plus ancien. Chaque entrée dit **quoi**, **où**, et **comment
revenir en arrière**.

Règles de travail :
- On remplace l'ancien code, on ne l'empile pas. Le code retiré reste
  récupérable par Git (commit cité dans l'entrée).
- Une migration Supabase ne se modifie jamais après application : on corrige
  par une nouvelle migration, et le retour arrière se fait aussi par migration.
- Retour arrière du code : `git revert <commit>` puis redéploiement Vercel.

Repères :
- Base : Supabase `zjugauidrijghesgsmap` (migrations dans `supabase/migrations`).
- Web : Vercel `vitriin-espace` → app.vitriin.co (`/`, `/centrale`, `/magasin`).
- Fonctions : `supabase/functions` (déploiement manuel `supabase functions deploy`).

---

## 2026-10-29

### MOD-008 · App magasin : cartes compactes, ouvrir, glisser pour supprimer
- **Accueil** : l'activité affiche les logos Facebook / Instagram au lieu des
  lignes « Publiée sur … ✓ ». « Réseau » devient « Centrale » partout dans
  l'app (étiquettes, onglet « De la centrale », réglages).
- **Promos** :
  - texte d'explication des promos de la centrale en pop-in, une seule fois
    par magasin et par appareil (clé `vitriin-intro-<magasin>`) ;
  - cartes moins hautes (visuel 56 px, une ligne dates, codes regroupés) ;
  - œil « Voir côté clients » en haut à droite des promos publiées ;
  - toucher une carte l'ouvre : promo du magasin → formulaire de modification
    (« Enregistrer les modifications » sans republier si déjà publiée) ;
    promo de la centrale → titre, texte et visuel personnalisables si la
    centrale l'autorise, sinon fiche grisée en lecture seule ;
  - glisser vers la gauche → « Supprimer » : promo du magasin supprimée ;
    promo de la centrale retirée de l'app et de la vitrine (si autorisé,
    jamais pour une obligatoire).
- **Centrale** : Paramètres > Préférences, deux interrupteurs « Les magasins
  peuvent personnaliser les promos » et « … supprimer une promo » (désactivés
  par défaut). Le suivi d'une promo affiche « Supprimée » pour ces magasins.
- **Base** (règles appliquées côté serveur, testées) :
  - migration `20261029220821_store_customization` : `store_promotions.overrides`
    (titre, texte, visuel https uniquement) et `hidden` ; trigger
    `guard_store_customization` qui refuse toute personnalisation ou
    suppression non autorisée par la centrale, et toute suppression d'une
    promo obligatoire ; `get_store_network` renvoie `store_edit`, `store_delete` ;
  - migration `20261029220831_store_promotions_public_not_hidden` : une promo
    retirée n'est plus lisible publiquement.
- **Fonction `meta-publish`** : utilise la personnalisation du magasin (titre,
  texte, visuel) pour la vraie publication Meta. **Modifiée dans le dépôt,
  pas encore redéployée** (sans effet tant qu'aucune centrale réelle n'active
  la personnalisation ; la démo publie en simulé).
- **Fichiers** : `web/espace-magasin/public/magasin/index.html`,
  `web/espace-magasin/public/centrale/index.html`,
  `supabase/functions/meta-publish/index.ts`.
- **Retour arrière** : `git revert` du commit MOD-008. En base, colonnes et
  trigger sans effet sur l'ancien code (overrides vides, hidden à false).

### MOD-007 · App magasin alignée sur la Centrale
- **Quoi** :
  - Logo : la pastille du magasin (accueil, réglages, aperçu côté clients)
    affiche son logo, sinon celui de l'enseigne, sinon l'initiale.
  - Réglages : contact de l'enseigne (email support, téléphone, CGV) quand la
    centrale l'a renseigné.
  - Promos de la centrale : nombre de photos et formats prévus
    (ex. « 3 photos · Instagram Carrousel · Facebook Carrousel ») ; un post
    sans offre n'affiche plus de ligne de prix vide.
  - Déjà livrés en MOD-005 : acceptation automatique, code EAN.
- **Base** : migration `20261029215143_get_store_network_contact`
  (`get_store_network` renvoie aussi `support_email`, `phone`, `cgv_url`,
  toujours réservé aux membres du magasin).
- **Fichier** : `web/espace-magasin/public/magasin/index.html`.
- **Retour arrière** : `git revert` du commit MOD-007 ; la fonction élargie
  reste compatible avec l'ancien code.

### MOD-006 · Logos des magasins, onglet « Enseigne »
- **Quoi** : page Magasins, logo à gauche de chaque magasin (tableau, bandeau
  « à activer », fiche). Sans logo propre, celui de la centrale ; sans aucun
  logo, les initiales. Logo ajouté ou retiré depuis la fiche magasin
  (administrateurs). Paramètres : l'onglet « Compte » devient « Enseigne ».
- **Base** : migration `20261029214806_stores_logo_url` (`stores.logo_url`,
  https uniquement, modifiable selon les règles existantes de `stores`).
- **Fichier** : `web/espace-magasin/public/centrale/index.html`.
- **Retour arrière** : `git revert` du commit MOD-006 ; la colonne peut rester.

### BUG-002 · Photo de profil géante dans le menu de la Centrale — corrigé
- **Quoi** : l'avatar du bas du menu n'était pas contraint à sa pastille
  (image affichée en taille réelle, par-dessus « Importer en masse »).
- **Correction** : `overflow:hidden` + règle `.me .av img` (32 px, recadrée).
- **Fichier** : `web/espace-magasin/public/centrale/index.html`.
- **Retour arrière** : `git revert` du commit BUG-002.

### MOD-005 · Centrale : Paramètres, panneaux éditables, formats par réseau
- **Paramètres** (nouvelle page) :
  - Préférences : thème clair / sombre / auto et astuces (par navigateur),
    acceptation automatique des promos, codes caisse (réduction, EAN), types
    de promotion personnalisés (`networks.settings`, admins seulement).
  - Utilisateurs : mon profil (photo, prénom, nom, email, mot de passe) ;
    équipe avec rôles Administrateur / Éditeur, retrait, invitation par email
    (fonction `network-invite`, la clé service_role reste côté serveur).
  - Compte : logo, raison sociale, adresse, email support, téléphone, SIRET,
    SIREN, TVA, CGV (contrôles de format en base et dans l'écran).
  - Communication : modèles éditables (invitation, relance, annonce promo).
    Vitriin n'envoie rien : on copie le message.
- **Sidebar** repliable (mémorisé par navigateur).
- **Tableau de bord** : chiffres des cartes agrandis, « Voir les 5 autres
  magasins » dans le classement, magasins cliquables.
- **Promotions** : vignette dans le tableau ; panneau 33 % où tout se modifie
  (visuels, post ou promo, type, offre, texte, dates, codes, obligatoire,
  formats) ; liste des magasins repliée derrière « N magasins actifs ».
- **Nouvelle promo** : choix promo / post, plusieurs photos (carrousel), EAN,
  info-bulle « i » sur Promo obligatoire, formats par réseau avec les
  incompatibilités grisées, aperçu au ratio du format choisi. Stocké dans
  `promotions.details` (`kind`, `media`, `formats`). Seuls Facebook et
  Instagram sont actifs ; Google Business, TikTok, Pinterest affichés « Bientôt ».
- **Magasins** : fiche en panneau 33 % (infos modifiables par les admins,
  comptes connectés, stats détaillées, promos récentes).
- **App magasin** : réglage « Accepter automatiquement les promos du réseau »
  (`stores.auto_accept`), affichage du code EAN.
- **Base** : migrations `20261029211203_centrale_settings`,
  `20261029211256_network_invite_grants`. Fonction `network-invite` déployée.
- **Fichiers** : `web/espace-magasin/public/centrale/index.html`,
  `web/espace-magasin/public/magasin/index.html`,
  `supabase/functions/network-invite/index.ts`, `supabase/config.toml`.
- **Retour arrière** : `git revert <commit MOD-005>` puis redéploiement. En
  base, les colonnes ajoutées sont sans effet sur l'ancien code ; à retirer
  seulement si besoin, par une nouvelle migration.

### SEC-002 · TRUNCATE retiré aux rôles clients
- **Quoi** : `truncate`, `trigger`, `references` retirés à `anon` et
  `authenticated` sur toutes les tables (TRUNCATE ignore la RLS).
- **Migration** : `20261029212703_revoke_truncate_trigger_references`.
- **Tests** : un magasin ne peut modifier ni le réseau, ni les autres magasins,
  ni les promos de la centrale ; il peut modifier son propre `auto_accept`.
- **Retour arrière** : inutile (aucun usage légitime côté client).

### MOD-004 · Centrale, page Promotions : suivi en panneau latéral
- **Quoi** :
  - « Pousser des visuels » devient « Importer des visuels ».
  - Un clic sur une campagne ouvre son suivi dans un panneau qui glisse de la
    droite, sur 33 % de la largeur (420 px minimum, plein écran sur mobile).
  - La liste reste visible derrière, et la ligne ouverte est surlignée.
  - Pour fermer : la croix, un clic à côté ou la touche Échap.
  - L'ancienne page de détail pleine largeur et son bouton « Toutes les
    campagnes » sont supprimés, remplacés par le panneau.
- **Fichier** : `web/espace-magasin/public/centrale/index.html` (CSS du détail,
  `render`, `renderDrawer`, `viewDetail`, `bindView`).
- **Retour arrière** : `git revert` du commit de cette entrée.

### SEC-001 · Audit sécurité et durcissement
- **Vérifié** :
  - RLS active sur toutes les tables du schéma `public`.
  - Le schéma `private` (jetons Meta chiffrés, états OAuth, registre de
    suppression) n'est lisible ni par `anon` ni par `authenticated`.
  - Seule la clé publique `anon` figure dans le code (pages web et
    keep-alive). Elle est conçue pour être publique : la RLS s'applique.
  - Aucune clé `service_role`, aucun secret Meta, aucun jeton ni mot de passe
    dans le dépôt, ni dans son historique Git.
  - Secrets serveur : variables des Edge Functions Supabase uniquement.
- **Corrigé** (migrations `20261029193343_security_hardening` et
  `20261029193441_revoke_is_demo_store`) :
  - Colonnes modifiables restreintes : un magasin ne peut plus réaffecter une
    activation à une autre promo, ni changer l'auteur d'une promo.
  - Un magasin ne peut plus s'abonner à la promo d'un autre réseau.
  - Les fonctions internes ne sont plus appelables sans connexion, et les
    fonctions de trigger plus du tout.
  - `search_path` figé sur `set_updated_at`.
  - Désormais, une nouvelle fonction n'est exécutable qu'avec un GRANT
    explicite.
- **Corrigé (code)** :
  - Échappement HTML des noms de magasin, de Page et des titres dans
    `/magasin` et `/` (risque d'injection de script via un nom de magasin).
  - L'app magasin n'envoie plus `created_by_store_id` en modification.
- **Testé en SQL** :
  - Compte magasin : activer, créer un brouillon et son activation, publier
    en simulation. Tout passe.
  - Changer la promo d'une activation : refusé.
  - Compte centrale : créer une promo puis `send_promotion` (20 magasins).
    Passe.
  - Appel anonyme de `is_store_member` : refusé.
- **Reste à faire, côté tableau de bord Supabase** : activer « Leaked password
  protection » (Authentication → Policies). Avertissement accepté : les RPC
  `SECURITY DEFINER` appelables par un utilisateur connecté sont voulues.
  Chacune vérifie l'appartenance au magasin ou au réseau.
- **Retour arrière** : nouvelle migration qui ré-accorde
  `insert, update on store_promotions, promotions to authenticated`, `update
  on store_members, network_members`, et recrée l'ancienne policy
  `store_promotions_insert_members` (`with check (is_store_member(store_id))`).
  Code : `git revert` du commit de cette entrée.

### BUG-001 · Création de promo impossible dans la Centrale — corrigé
- **Symptôme** : « new row violates row-level security policy for table
  "promotions" » en créant une promo sur /centrale.
- **Cause** : les policies d'auteur appelaient `can_write_promotion(id)`, qui
  relit la table ; la ligne insérée n'y est pas visible pendant
  `INSERT … RETURNING`. Touchait aussi les brouillons et promos à venir créés
  depuis l'app magasin.
- **Correction** : migration `20261029192924_promotions_rls_columns` (policies
  sur les colonnes, fonction `can_write_promotion` supprimée). Testé en SQL avec
  le compte centrale : insertion + RETURNING OK.
- **Retour arrière** : nouvelle migration recréant `can_write_promotion` et les
  trois policies telles que dans `20260716000000_initial_schema.sql`
  (lignes ~355 et ~735-765). Déconseillé : réintroduit le bug.

### MOD-003 · Démo Chausselandia branchée de bout en bout
- **Quoi** : l'app magasin (/magasin) lit et écrit dans Supabase (plus de
  données locales) ; la Centrale se rafraîchit toutes les 15 s.
  Publication simulée via `demo_publish` (réseaux `is_demo` uniquement).
- **Fichiers** : `web/espace-magasin/public/magasin/index.html`,
  `web/espace-magasin/public/centrale/index.html`, README.
- **Commit** : `eb7dc1b`.
- **Retour arrière** : `git revert eb7dc1b` (l'app revient aux données locales
  de démo « L'Atelier du Coureur »).

### MOD-002 · Données de démo Chausselandia
- **Quoi** : 20 magasins, 34 comptes sociaux factices (`demo-…`, sans jeton),
  10 promos centrale, 3 promos du magasin de Lyon, publications simulées.
  Compte magasin `magasin.demo@vitriin.co` (mot de passe hors dépôt).
- **Fichier** : `supabase/seed/demo_chausselandia.sql` (exécuté le 29/10).
- **Retour arrière** (destructif, à lancer à la main) :
  `delete from promotions where created_by_network_id = '<id réseau>' or created_by_store_id in (select id from stores where network_id = '<id réseau>'); delete from stores where network_id = '<id réseau>'; update networks set is_demo = false where slug = 'chausselandia';`

### MOD-001 · Mode démo en base
- **Quoi** : `networks.is_demo`, `promotions.details`, RPC `demo_publish`,
  `demo_reconnect`, `demo_tick` (refusées hors réseau démo).
- **Migration** : `20261029175319_demo_mode`. **Commit** : `f5df228`.
- **Retour arrière** : migration `drop function demo_tick, demo_reconnect,
  demo_publish, demo_guard, is_demo_store; alter table promotions drop column
  details; alter table networks drop column is_demo;` (après MOD-003 annulé).

---

## 2026-10-28

- **MOD** · Espace Centrale + parcours réseau côté magasin
  (migration `20261028223629_espace_centrale`, commit `de44db2`).
- **MOD** · App magasin démo installable /magasin (commit `e125b6e`).
- **MOD** · Keep-alive Supabase tous les 3 jours, GitHub Actions
  (`.github/workflows/supabase-keepalive.yml`, commit `ea28d45`).
- **BUG** · Visuel par défaut écrasé à chaque build (build.mjs régénérait
  `promo-test.jpg`) → visuel renommé `lyon-laval-2027.jpg` (commit `70596fa`).
- **MOD** · Upload des visuels, bucket `promo-media`
  (migration `20261028151554_promo_media_bucket`, commit `1f56701`).
- **MOD** · Statistiques Meta et suppression des données
  (migration `20261028120000_insights_and_data_deletion`, commits `574fa16`,
  `eb2f2f0`, `7a1f2ff`).
- **Info** · Soumission App Review Meta envoyée (examen en cours).
