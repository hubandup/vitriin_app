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

## 2026-10-30

### MOD-021 · Centrale : import Excel / CSV des points de vente et invitation des gérants
- **Quoi** : dans « Ajouter des magasins », la centrale importe un fichier
  .xlsx, .xls ou .csv (une ligne par magasin ; colonnes reconnues
  automatiquement ; modèle téléchargeable ; aperçu avant import). Les
  doublons (même nom et même code postal) sont ignorés, les lignes fautives
  listées. Chaque gérant avec un email reçoit une invitation Vitriin ; s'il a
  déjà un compte, le magasin est ajouté à son espace. Bouton « Réessayer »
  pour les envois refusés. Dans la liste, « Invité le … » tant que le magasin
  n'a rien connecté. Côté app magasin, le gérant invité choisit son mot de
  passe à l'arrivée (`?bienvenue=1`).
- **Sécurité** : RPC `import_network_stores` (SECURITY DEFINER, admin du
  réseau vérifié en base, 1000 lignes max) ; fonction `network-stores-invite`
  (admin vérifié avec le jeton de l'appelant, magasins du réseau uniquement,
  clé service_role côté serveur seulement).
- **Fichiers** : `centrale/index.html`, `magasin/index.html`,
  `supabase/functions/network-stores-invite/index.ts`,
  migrations `20261030131730_network_stores_import`, `20261030131848_network_stores_import_fix`.
- **Retour arrière** : `git revert` du commit ; supprimer la fonction
  `network-stores-invite` ; `drop function public.import_network_stores(uuid, jsonb)`.

### MOD-020 · Publication Meta : personnalisation magasin, réseaux coupés, promos suspendues
- **Quoi** : la fonction `meta-publish` (version 5 déployée) publie le titre,
  le texte et la photo personnalisés par le magasin ; elle ignore un compte
  Facebook ou Instagram désactivé dans les Réglages (`enabled = false`) ;
  elle refuse de publier une promo suspendue ou supprimée par le magasin.
- **Fichier** : `supabase/functions/meta-publish/index.ts`.
- **Retour arrière** : redéployer la version précédente du fichier
  (`git show <commit>~1:supabase/functions/meta-publish/index.ts`).

### MOD-019 · Stats : toutes les statistiques d'une promo
- **Quoi** : dans Stats, toucher une ligne d'« Activité récente » (ou de
  « Statut par promo ») ouvre le détail de la promo : statut et dates,
  portée / vues / interactions / codes utilisés, tableau Facebook /
  Instagram (portée, vues, interactions, commentaires, date de publication
  ou échec), taux d'engagement, codes utilisés en magasin (total et 7 jours),
  bouton « Ouvrir la promo ».
- **Fichier** : `web/espace-magasin/public/magasin/index.html`.
- **Retour arrière** : `git revert` du commit MOD-019.

### MOD-018 · App magasin : Réglages réorganisés
- **Ordre** : 1. fiche du magasin (nom, adresse, contact principal, téléphone,
  email, site web ; bouton « Compléter / Modifier les informations ») ·
  2. une ligne « Affilié à la centrale X » · 3. promos de la centrale ·
  4. notifications · 5. comptes connectés · 6. support de l'enseigne.
- **Comptes connectés** : Facebook et Instagram avec interrupteur
  activer / désactiver (désactivé = reste connecté mais n'y publie plus) ;
  TikTok, Google Business Profile, Pinterest affichés « Bientôt disponible ·
  Non connecté », interrupteur grisé.
- **Base** : migration `20261030123854_store_contact_and_channel_toggle` :
  `stores.contact_first_name / contact_last_name / contact_phone /
  contact_email / website` (formats contrôlés), `social_accounts.enabled`
  (seule colonne modifiable par le magasin sur cette table, politique dédiée).
  Testé : le magasin ne modifie que ses comptes, et pas leur statut.
- **À faire** : `meta-publish` doit aussi ignorer un compte désactivé (l'app
  ne propose déjà plus de publier dessus).
- **Fichier** : `web/espace-magasin/public/magasin/index.html`.
- **Retour arrière** : `git revert` du commit MOD-018.

### MOD-017 · Codes utilisés rattachés au magasin où se trouve le client ; vue clients épurée
- **Géolocalisation** : quand le client révèle le code, l'app lui demande sa
  position (il peut refuser). Le serveur rattache l'utilisation au magasin du
  réseau le plus proche, à 10 km au plus ; sinon (refus, trop loin), au
  magasin qui a publié la promo. **Les coordonnées ne sont jamais
  enregistrées** : seuls le magasin trouvé (`store_id`), le magasin d'origine
  (`origin_store_id`) et `located` sont gardés.
- **Base** : migration `20261030081943_code_reveals_geoloc` : colonnes
  `origin_store_id`, `located` ; RPC `record_code_reveal_at(…, lat, lng)` ;
  l'ancienne `record_code_reveal` passe par la nouvelle (sans position).
  Testé : un client près de Paris Rivoli est compté pour Paris Rivoli, un
  client loin ou sans position pour le magasin d'origine.
- **Vue clients** : flèche retour et bouton « Côté clients · Revenir au
  magasin » retirés ; le logo du magasin fait l'aller-retour.
- **À prévoir** : mention de la géolocalisation dans la politique de
  confidentialité de la vitrine.
- **Fichier** : `web/espace-magasin/public/magasin/index.html`.
- **Retour arrière** : `git revert` du commit MOD-017.

### MOD-016 · Drive to store : « Codes utilisés »
- **Quoi** : quand un client touche « Utiliser cette promotion » et révèle le
  code-barre, l'événement est enregistré. Affiché : Stats › 4e tuile « Codes
  utilisés 7 j » (remplace la portée, déjà dans les cartes), page promo ›
  4e statistique « Codes utilisés », accueil › ligne de la semaine.
- **Base** : migration `20261030081255_code_reveals` :
  - table `code_reveals` (RLS : lecture par le magasin et sa centrale ;
    aucune écriture directe, ni anon ni authenticated) ;
  - RPC `record_code_reveal(store_promotion_id, client_id)` (anon et
    connectés) : ne compte que les promos activées, ni suspendues ni
    supprimées, en cours ; un appareil compte une fois par promo et par jour ;
    les membres du magasin qui testent leur vue client ne comptent pas, sauf
    sur un réseau de démo. Testé en base.
- **Démo** : 54 révélations fictives (`source = 'demo'`) sur les promos en
  ligne de Chausselandia Lyon, réparties sur 7 jours.
  Retour arrière : `delete from code_reveals where source = 'demo';`
- **Limite** : mesure le code affiché par le client, pas l'achat validé en caisse.
- **Fichier** : `web/espace-magasin/public/magasin/index.html`.
- **Retour arrière** : `git revert` du commit MOD-016 ; la table peut rester.

### MOD-015 · App magasin : Stats plus compactes
- **Quoi** : les trois grandes barres (promos actives, publications réussies,
  en échec) deviennent quatre tuiles sur une ligne, dans le style de la page
  promo : Actives · Publiées · En échec · Portée 7 j (décidé à l'oral).
  Cartes de résultats et taux d'engagement resserrés.
- **Code retiré** : CSS `.bigk`.
- **Fichier** : `web/espace-magasin/public/magasin/index.html`.
- **Retour arrière** : `git revert` du commit MOD-015.

### MOD-014 · App magasin : accueil simplifié, logo = bascule côté clients
- **Accueil en trois blocs** (décidé avec Charles à l'oral) :
  1. « À faire maintenant » : une seule carte qui regroupe promos de la
     centrale à valider, obligatoires à publier, promos activées à publier,
     Instagram à reconnecter (sinon « Rien à faire : tout est à jour ») ;
  2. « En ce moment » : promos en ligne en grandes cartes (avec logos réseaux),
     défilement horizontal, lien vers Promos › En cours ;
  3. résumé des 7 derniers jours en une ligne (vues, interactions,
     publications), lien vers Stats.
- **Retirés de l'accueil** : bouton « Voir côté clients », bandeaux séparés,
  les trois compteurs, l'ancien carrousel. « Activité récente » passe dans Stats.
- **Logo du magasin** : le toucher ouvre la vue côté clients ; dans la vue
  clients, toucher le logo ramène à l'espace magasin.
- **Code retiré** : `statusPill`, `priceLine`, CSS `.hero`, `.due`, `.warn`,
  `.kpis`, `.pc`, `.client-btn`.
- **Fichier** : `web/espace-magasin/public/magasin/index.html`.
- **Retour arrière** : `git revert` du commit MOD-014.

### BUG-005 · Page promo qui bouge de côté sur iPhone — corrigé
- **Cause** : sur Safari iOS, les deux champs de date et la ligne de
  statistiques débordaient légèrement de l'écran ; la page pouvait alors
  glisser horizontalement (vidéo de Charles du 30/10).
- **Correction** : page promo bloquée en largeur (`overflow-x:hidden`,
  défilement vertical seul), champs et colonnes contraints à la largeur
  (`min-width:0`, grilles `minmax(0,1fr)`), champs date sans largeur native.
  Vérifié sans débordement sur iPhone 13 et iPhone SE émulés.
- **Fichier** : `web/espace-magasin/public/magasin/index.html`.

### MOD-013 · Page promo : changement de photo simplifié
- **Quoi** : toucher la photo ouvre directement le sélecteur du téléphone
  (sur iPhone : « Prendre une photo » / « Photothèque » / « Fichiers »), sans
  menu Vitriin avant. La médiathèque de la centrale a son propre bouton
  « Médiathèque » sur la photo. Fin du double menu.
- **Fichier** : `web/espace-magasin/public/magasin/index.html`.
- **Retour arrière** : `git revert` du commit MOD-013.

### MOD-012 · Promos par catégories qu'on balaye, logos réseaux, page promo
- **Page Promos** : cinq catégories qu'on fait défiler en balayant (ou en
  touchant l'onglet) : À traiter (magenta) · En cours (vert) · À venir
  (violet) · Suspendues (bleu) · Supprimées (gris). Les promos terminées et
  refusées sont rangées dans « Supprimées ». Cartes façon piste A, statut
  dans la couleur de sa catégorie, boutons Activer / Publier sur les cartes
  « À traiter ». Les onglets « De la centrale / Mes promos » disparaissent :
  la carte indique « Centrale » ou « Ma promo ».
- **Glisser sur une carte retiré** : le balayage horizontal sert désormais à
  changer de catégorie ; Suspendre / Reprendre / Supprimer passent sur la
  page de la promo (avec confirmation).
- **Logos réseaux partout** : Facebook et Instagram toujours affichés, en
  couleur si la promo y est publiée, grisés sinon (× rouge si échec).
- **Page d'une promo** : photo (toucher = menu : prendre une photo, galerie,
  médiathèque de la centrale), statut, logos, statistiques (portée, vues,
  interactions, commentaires), champs titre / texte (+ dates pour une promo
  du magasin), modifiables si autorisé ; « Suspendre » ou « Supprimer » selon
  le statut, et « Valider » (enregistre ; accepte aussi une promo reçue).
- **Suppression** : désormais douce pour toutes les promos (la promo passe
  dans « Supprimées », `store_promotions.hidden`), plus de suppression
  définitive depuis l'app.
- **Fichier** : `web/espace-magasin/public/magasin/index.html`.
- **Retour arrière** : `git revert` du commit MOD-012.

### MOD-011 · App magasin : nouvelles cartes promo et fiche promo
- **Choix de Charles** : « À traiter » en tête façon piste B, puis grandes
  cartes façon piste A (maquettes sur la planche « Vitriin · Cartes promo »).
- **Liste** : par onglet (De la centrale / Mes promos), trois sections :
  « À traiter » (visuel 104 px, un statut, titre, offre + date, une seule
  action Activer ou Publier), « En cours et à venir » et « Suspendues et
  terminées » (grand visuel 190 px, statut en pastille, offre posée sur
  l'image, titre + une date). Un seul statut coloré par promo. Le glisser
  (Suspendre / Reprendre / Supprimer) est inchangé sur les deux formes.
- **Fiche promo** commune (toucher une carte) : grand visuel, statut, prix,
  dates, état Facebook / Instagram (date, vues, reconnexion), détails repliés
  (codes, formats, texte), une action principale selon l'état et les liens
  Modifier / Suspendre / Reprendre / Supprimer.
- **Code retiré** : ancienne carte `cardPromo`, ancien bloc CSS `.card …`.
- **Fichier** : `web/espace-magasin/public/magasin/index.html`.
- **Retour arrière** : `git revert` du commit MOD-011.

## 2026-10-29

### MOD-010 · Une seule règle de glisser, centrale comme magasin
- **Règle** (remplace MOD-009) :
  - en cours ou à venir → glisser à gauche : « Suspendre » (bleu) + confirmation ;
  - suspendue → à gauche : « Supprimer » (rouge), à droite : « Reprendre »
    (vert) ; chacun avec confirmation ;
  - terminée (ou brouillon) → à gauche : « Supprimer » + confirmation.
  - Garde-fous conservés pour une promo de la centrale : suspendre suppose
    l'accord de la centrale et jamais une obligatoire.
- **Base** : migration `20261029224915_store_delete_when_suspended` : une promo
  de la centrale peut être supprimée si elle est suspendue ou terminée.
- **Fichier** : `web/espace-magasin/public/magasin/index.html`.
- **Retour arrière** : `git revert` du commit MOD-010, puis réappliquer la
  fonction de la migration `20261029222520_store_suspend`.

### BUG-004 · Glisser sans effet (Suspendre / Supprimer) — corrigé
- **Cause** : le glisser reposait sur les « pointer events ». Sur iPhone
  (Safari) et à la souris (glisser natif de l'image, sélection de texte), le
  geste était annulé : aucun bouton n'apparaissait, aucune requête ne partait
  (vérifié dans les journaux Supabase : aucune mise à jour `suspended`).
- **Correction** : gestes gérés en événements tactiles + souris séparés,
  sélection et glisser d'image désactivés sur les cartes. Testé en tactile
  (iPhone émulé) et à la souris. En plus, la fiche d'une promo de la centrale
  propose « Suspendre / Reprendre / Supprimer la promo », sans glisser.
- **Promo terminée** : la carte affiche « Terminée » sans boutons de
  publication. Le magasin de Lyon n'avait aucune promo terminée : ajout d'une
  promo démo « Rentrée des classes » (terminée il y a 20 jours, envoyée aux
  20 magasins) pour tester « Supprimer ».
  Retour arrière : `delete from promotions where title = 'Rentrée des classes'
  and created_by_network_id = '<id Chausselandia>';`
- **Fichier** : `web/espace-magasin/public/magasin/index.html`.

### BUG-003 · Centrale affichait « Créez votre réseau » — corrigé
- **Cause** : /centrale et /magasin partagent le domaine app.vitriin.co et
  donc la même session Supabase. La connexion du compte démo magasin sur
  /magasin a remplacé celle de Charles ; la Centrale a vu un compte sans
  réseau. Aucune donnée perdue (Chausselandia : 20 magasins, 11 promos).
- **Correction** : session séparée par espace (`storageKey`
  `vitriin-centrale-auth` et `vitriin-magasin-auth`). Un compte magasin qui
  ouvre la Centrale voit « Ce compte est un compte magasin » au lieu du
  formulaire de création de réseau.
- **Effet de bord** : une reconnexion est demandée une fois sur chaque espace.
- **Fichiers** : `centrale/index.html`, `magasin/index.html`.
- **Retour arrière** : `git revert` du commit BUG-003.

### MOD-009 · Glisser à gauche : Supprimer ou Suspendre selon la promo
- **Règle** (corrige MOD-008) :
  - promo du magasin → bouton rouge « Supprimer » puis confirmation ;
  - promo de la centrale en cours ou à venir → bouton bleu « Suspendre » puis
    confirmation, si la centrale l'autorise, jamais pour une obligatoire.
    La promo suspendue sort de la vitrine ; « Reprendre » la remet ;
  - promo de la centrale terminée → bouton rouge « Supprimer » (retirée de
    la liste du magasin), toujours possible.
- **Centrale** : l'interrupteur devient « Les magasins peuvent suspendre une
  promo » (même réglage `store_delete`) ; le suivi affiche « Suspendue ».
- **Base** : migration `20261029222520_store_suspend` : colonne
  `store_promotions.suspended`, trigger `guard_store_customization` mis à
  jour (suspendre = autorisation centrale + non obligatoire ; supprimer une
  promo centrale = seulement une fois terminée), vitrine publique sans les
  promos suspendues ou retirées. Testé en base (4 cas).
- **Fichiers** : `web/espace-magasin/public/magasin/index.html`,
  `web/espace-magasin/public/centrale/index.html`.
- **Retour arrière** : `git revert` du commit MOD-009 ; la colonne
  `suspended` reste à false et n'a pas d'effet.

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
