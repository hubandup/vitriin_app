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

## 2026-10-31

### MOD-060 · Profil particulier aligné sur le reste de l'app
- Bandeau dégradé et avatar en surimpression (même grammaire que la fiche commerce), titres de section du fil (« Mon compte », « Centres d'intérêt », « Préférences »), centres d'intérêt en pastilles du fil avec picto, compteurs dans une carte blanche menant à Mes promos.
- Styles retirés : `.stats`, `.lbl`, `.intg`.
- **Retour arrière** : `git revert` du commit.

### BUG-009 · Fil particulier vide pour le compte de démo
- **Constat** : sur iPhone, charles@baulu.net ne voyait que « Vos commerces » puis « Pas encore de promo ». Ouvert sans `?demo=1`, le fil n'interrogeait que les commerces réels (aucun en production) ; seuls les commerces suivis, tous de démo, s'affichaient.
- **Correction** (`/v/`) : un compte qui suit au moins un commerce de démonstration passe automatiquement en mode démo. Le message « Pas encore de promo » ne s'affiche plus quand « Vos commerces » a du contenu.
- **Retour arrière** : `git revert` du commit.

### MOD-059 · Particulier : fil enrichi, Mes promos sur un écran, profil complet, photo
- **Fil `/v/`** : « Autour de vous » devient « À découvrir » (centres d'intérêt et catégories suivies d'abord, puis univers proches via la table `AFF`). Nouveaux carrousels « Derniers jours » (fin < 72 h), « Commerces à suivre » (cartes magasin), « Bientôt » (promos qui démarrent sous 21 jours), puis une tuile « Toutes les promos en plein écran ». Recherche ou filtre : un seul carrousel de résultats.
- **Promo à venir en plein écran** : pas de code ni de « Garder », bouton « Disponible le X » qui fait suivre le commerce.
- **Mes promos** : un seul écran, économies, carrousel « Gardées » (disparaissent à échéance), carrousel « Utilisées » grisé et inactif. Grille, onglets et « Voir + » retirés.
- **Profil** : compte (prénom, nom, email, téléphone ; changement d'email confirmé par lien Supabase), centres d'intérêt en vignettes avec pictos, interrupteurs Localisation, Alertes, Newsletter (opt-in, désactivée par défaut). CTA « Passer en mode commerçant » retiré. Photo de profil en touchant l'avatar (carré 320 px JPEG).
- **Base** (`20261031070000_customer_profile_soon.sql`) : `customer_prefs` + `last_name`, `phone`, `newsletter`, `geo`, `avatar_url` (limité au bucket avatars) ; fonction `vitrine_soon` (anon/authenticated, aucun code exposé) ; bucket public `avatars` (1 Mo, jpeg/png/webp), RLS : chacun n'écrit, ne liste et ne supprime que `avatars/<son uid>/`.
- **Retour arrière** : `git revert` du commit ; migration inverse (drop des colonnes, de `vitrine_soon`, des policies et du bucket).

### MOD-058 · Accueil particulier : toujours le fil de promos
- **Problème** : sans position connue, l'accueil `/v/` affichait un écran « Les bons plans de vos commerces… / Autour de moi / villes » au lieu du fil. Contraire à la maquette (écran 4).
- **Base** : nouvelle fonction `vitrine_feed(p_lat, p_lng, p_demo)` (SECURITY DEFINER, anon/authenticated) : promos en cours dédupliquées par promotion (le magasin le plus proche quand une position est connue), triées par distance puis nouveauté, 80 max. Migration `20261031060000_vitrine_feed.sql`.
- **Front `/v/`** : l'écran ville est supprimé. L'accueil affiche toujours stories, recherche, « Vos commerces » (suivis), « Chez X », filtres, « À la une » / « Autour de vous » et carrousels par catégorie. La pastille lieu (« Partout », « Lyon », « Autour de moi ») ouvre une feuille « Où chercher ? » par-dessus le fil. Position utilisée automatiquement si déjà autorisée. Mode démo mémorisé sur l'appareil (`?demo=0` pour le quitter). Réglage « Rayon de recherche » retiré (plus utilisé). `loadNearby` remplacé par `loadFeed`.
- **Retour arrière** : `git revert` du commit ; `drop function public.vitrine_feed` par migration.

### MOD-057 · Démos fleuriste, opticien, hoodies et compte particulier de démonstration
- **Secteurs de démo** : « Pétale & Tige » (fleuriste), « Lunetterie Lumière » (opticien), « Hoodie Club » (hoodies),
  chacun 20 magasins et 6 promos centrale + 2 promos magasin, construits par `manager_build_demo` (images Unsplash).
  Logos `public/demo/petale-tige.svg`, `lunetterie-lumiere.svg`, `hoodie-club.svg`. Magasins lyonnais placés à des
  adresses distinctes (Presqu'île, Gambetta), avec présentation, téléphone et couverture.
- **Compte particulier charles@baulu.net** : prénom, centres d'intérêt, 6 commerces suivis, 8 promos gardées,
  8 promos utilisées déclarées sur les jours passés (historique et économies). Données de démonstration.
- **Où** : migration `20261031050000_demo_sectors_fleuriste_optique_mode.sql`, données en base, logos.
- **Retour arrière** : Manager > Démos (supprimer les réseaux) ; supprimer les lignes du compte dans customer_* et code_reveals.

### MOD-056 · Particulier : noms des stories lisibles, badges courts
- **Stories** : nom de l'enseigne sans la ville, sur deux lignes au plus (plus de « Jardins & S… »).
- **Badges** : un texte libre de plus de 14 caractères est raccourci (« Atelier offert samedi » → « Offert »,
  « −20 % sur le rayon » → « −20 % », « −10 € sur la 2e paire » → « −10 € », « Dès 50 € d'achat » → « Dès 50 € »,
  sinon « Bon plan ») ; le texte complet s'affiche sous le titre en plein écran.
- **Où** : `public/v/index.html` (`shortBadge`, `storyName`). **Retour arrière** : `git revert`.

### MOD-055 · Particulier : carrousels partout, grille pour Mes promos
- **Accueil** : « Autour de vous » en carrousel de vignettes (plus de publications empilées), puis un carrousel par
  catégorie quand le filtre est sur « Tout ». Toucher une vignette ouvre le plein écran sur cette promo, puis on fait
  défiler la rangée. Même composant pour « Chez … » (commerce d'origine) et la fiche commerce.
- **Mes promos** : « Gardées » et « Utilisées » en grille de 3 vignettes (badge ou économie, magasin), « Voir + » pour
  les suivantes ; une vignette gardée ouvre le plein écran.
- **Nettoyage** : suppression des publications en fil (`postHtml`, `bindPosts`, `bindCards`) et de leurs styles,
  remplacés par `tilesHtml` / `bindTiles`.
- **Règle mise à jour** : promos en plein écran ou en carrousel, grille autorisée pour Mes promos.
- **Où** : `public/v/index.html`. **Retour arrière** : `git revert`.

### MOD-054 · Règle UI particulier : promos en fil ou en carrousel uniquement
- **Règle (décidée avec Charles le 31/10)** : côté particulier, les promotions ne s'affichent que sous forme de fil
  (publications, plein écran) ou de carrousel, jamais en liste.
- **Appliqué** : « Mes promos > Sauvegardées » passe en fil (mêmes publications que l'accueil) ; l'ancienne carte en
  liste (`cardHtml`) et ses styles sont supprimés. L'onglet « Utilisées » reste un historique d'économies.
- **Où** : `public/v/index.html`.
- **Retour arrière** : `git revert`.

### MOD-053 · Particulier : en-tête du fil, stories, inscription en feuille avec code, onboarding
- **En-tête du fil** : logo Vitriin, ville (touchée : retour au choix de la ville), « Connexion » ou initiale du compte.
  « Bonjour / Près de vous » et le bouton de localisation de la recherche sont retirés.
- **Stories** : un rond par commerce qui a des promos autour, les commerces suivis d'abord ; anneau magenta tant qu'une
  promo n'a pas été vue en plein écran (mémorisé sur l'appareil), gris ensuite. Toucher ouvre ses promos en plein écran.
- **Inscription au bon moment** : Garder, Suivre ou Connexion ouvrent une feuille par-dessus l'écran (plus de changement
  de page). Email, puis code à 6 chiffres reçu par email, saisi sur place (le lien de l'email marche toujours).
  L'action demandée est faite juste après. Écran Connexion (onglets Mes promos, Suivies, Profil) : même formulaire.
- **Emails** : « Votre code de connexion Vitriin » et « Confirmez votre adresse » affichent le code (`{{ .Token }}`) en
  plus du bouton ; enregistrés dans le Dashboard Supabase (vérifié après rechargement) et dans `supabase/templates/`.
- **Onboarding** (première connexion, prénom non renseigné) : prénom et envies, commerces à suivre (commerce d'origine
  et autour), alertes ; « Passer » à chaque étape. Le bouton « Obtenir l'application » n'apparaît que si les liens
  des stores sont renseignés.
- **Où** : `public/v/index.html`, `supabase/templates/magic_link.html`, `confirmation.html`, `supabase/config.toml`.
- **Retour arrière** : `git revert` ; remettre les modèles d'email précédents dans le Dashboard.

### MOD-052 · Fiche commerce et fil de promos façon publication
- **Fiche commerce (particulier)** : photo de couverture (dégradé à défaut), logo, nom, catégorie et distance,
  Suivre + Itinéraire, présentation, coordonnées clients (adresse, téléphone, email, site), plan OpenStreetMap avec
  le point du magasin (ouvre l'itinéraire), puis les promos en fil.
- **Fiche commerce, promos** (corrigé le 31/10 à la demande de Charles) : plus de liste en fil sur la fiche ; carrousel
  « En ce moment » sous le plan, toucher une promo ouvre le plein écran à cette promo, puis on fait défiler.
- **Promos en fil sur l'accueil** (« Autour de vous ») : image 4:5, badge, titre, prix, date de fin,
  « J'en profite », garder, partager. Toucher l'image ouvre le plein écran. « À la une » est retiré du fil.
- **Données** : `stores.description`, `cover_url`, `public_phone`, `public_email` (coordonnées publiques, distinctes du
  contact gérant qui reste privé), droits de mise à jour colonne par colonne pour le gérant ; `vitrine_store_json` les expose.
- **Espace magasin** : Réglages > Informations du magasin > « Ma vitrine » (photo de couverture, présentation,
  téléphone et email clients).
- **Où** : `public/v/index.html`, `public/magasin/index.html`, migration `20261031040000_store_public_profile.sql`.
- **Retour arrière** : `git revert` ; colonnes sans effet si le front revient en arrière.

### MOD-051 · Plein écran des promos : épuré
- **Quoi** : retrait des barres de progression en haut (elles suggéraient un balayage gauche/droite) et de
  « Promo suivante » ; à la première ouverture (une fois par session), la promo fait un petit sursaut vers le haut
  qui laisse apercevoir la suivante. Picto « Y aller » remplacé par un repère de carte (il ressemblait à
  « Partager »), partout (plein écran, feuille du code, fiche commerce).
- **Où** : `public/v/index.html`.
- **Retour arrière** : `git revert`.

### MOD-050 · Particulier : cap sur l'application mobile, plus d'invitation à « ajouter à l'écran d'accueil »
- **Quoi** : Vitriin particulier sera une application mobile (App Store, Google Play), pas une web app installée.
  Le mode d'emploi Safari et l'invitation d'installation Android sont retirés. Les bandeaux « Obtenir » (plein écran
  à l'arrivée par lien, fil) ne s'affichent que lorsque les liens des stores sont renseignés dans `STORES`
  (`public/v/index.html`) et mènent alors au bon store selon le téléphone. Le web reste complet sans l'application.
- **Géolocalisation** : vérifié, aucun réglage serveur ne la bloque (pas d'en-tête Permissions-Policy). Le fil vide
  sans `?demo=1` vient de l'absence de commerces hors démonstration, pas de la position.
- **Retour arrière** : `git revert`.

### MOD-049 · Particulier : arrivée sur la promo, code flouté 2 min, « Profité », fiabilité des codes
- **Arrivée par un lien** (`/v/p/<id>` : post, QR code, newsletter) : la promo s'ouvre directement en plein écran,
  suivie des autres promos du même commerce ; fermer mène à la fiche du commerce. Le commerce d'origine
  (lien ou fiche visitée) apparaît en tête du fil (« Chez … » + carte « Suivez … ») tant qu'il n'est pas suivi.
- **J'en profite, sans compte** : bouton principal du plein écran (remplace « Trouver en magasin »). Feuille avec
  code-barres flouté, « Afficher mon code » (à faire devant la caisse) : le code reste visible 2 minutes
  (compte à rebours, barre animée pour distinguer d'une capture, écran maintenu allumé), puis se refloute.
  « Garder ce code » (inscription si besoin), « Y aller », « Envoyer à un ami », « C'est fait, je l'ai utilisé ».
- **Écran « Profité »** après confirmation : économie réalisée quand elle est calculable, invitation à suivre le commerce.
- **Plus d'écran vide** : sans position, « Autour de moi » + villes qui ont des promos (`vitrine_cities`) ; si rien
  autour, les villes s'affichent sous le message.
- **Ajout à l'écran d'accueil** (web et appli) : bandeau dans le plein écran à l'arrivée par lien, bandeau dans le
  fil, refermables ; invitation native Android, mode d'emploi Safari sur iPhone. « Continuer sur le web » les masque.
- **Fiabilité des codes (serveur)** : `code_reveals.confidence` = probable (≤ 200 m du magasin, 8 h-21 h heure de
  Paris), incertain (sans position, 8 h-21 h), distance (sinon) ; `distance_m` ; un nouvel affichage le même jour
  ne peut qu'améliorer l'indice. `used_at` via `vitrine_confirm_use` (déclaratif, seulement après un affichage de
  moins de 24 h sur le même appareil). Espace magasin : les codes « à distance » non confirmés ne comptent plus
  comme utilisés ; détail par promo (confirmés, au magasin, sans position, à distance).
- **Où** : `public/v/index.html`, `public/magasin/index.html`, migration `20261031030000_reveal_confidence.sql`.
- **Retour arrière** : `git revert` (front) ; les colonnes ajoutées sont sans effet si le front revient en arrière.
- **À venir (décidé le 31/10)** : promo à usage unique (option à la création) ; validation vendeur et rapprochement
  ventes par EAN, à la demande.

### MOD-048 · Email « Nouvelle campagne » aux gérants
- **Quoi** : quand la centrale envoie une campagne, chaque gérant concerné reçoit un email avec l'image, les dates
  et un bouton : « Voir et activer » (campagne à valider) ou « Voir et publier » (obligatoire ou validation
  automatique). Le bouton ouvre la promo dans l'espace magasin (`/magasin/?promo=<id>`).
- **Sécurité** : fonction `campaign-notify` (JWT requis), réservée aux membres de la centrale qui a créé la campagne.
  `campaign_notify_claim` (service_role seulement) réserve les magasins ajoutés depuis moins d'une heure et pas encore
  prévenus (`store_promotions.notified_at`) : pas de doublon, pas de renvoi d'anciennes campagnes. Magasins masqués,
  suspendus ou sans compte activé : pas d'email. Comptes bloqués exclus.
- **Mutualisation** : gabarit et envoi Brevo dans `supabase/functions/_shared/email.ts`, utilisé aussi par `support-notify`.
- **Où** : `supabase/functions/campaign-notify/`, migration `20261031020000_campaign_notify.sql`, `centrale` (`notifyCampaign`),
  `magasin` (lien profond `?promo=`).
- **Retour arrière** : retirer l'appel `notifyCampaign` ; `git revert`.

## 2026-10-30

### BUG-008 · Fonctions serveur sans droits sur les tables (corrigé)
- **Symptôme** : emails du support jamais envoyés (`support-notify` répond 404 « Demande introuvable ») ;
  « Modifier l'email » d'un gérant refusé (400) ; invitation des magasins par la centrale en échec.
- **Cause** : la clé service_role contourne la RLS mais pas les GRANT. Elle n'avait aucun droit de lecture sur
  `support_tickets`, `support_messages`, `stores`, `networks`, `platform_admins`, ni d'écriture sur `store_members`.
- **Correctif** : migration `20261031010000_service_role_grants.sql`, droits minimaux (mises à jour limitées aux
  colonnes utilisées). anon et authenticated inchangés. Vérifié en SQL sous le rôle service_role.
- **Retour arrière** : `revoke` des mêmes droits (les trois fonctions cessent alors de marcher).

### MOD-047 · Emails du support via Brevo
- **Quoi** : nouvelle demande ou message client → email à l'équipe (SUPPORT_INBOX, hello@vitriin.co par défaut),
  « répondre » va au client, bouton vers le ticket dans le Manager (`/manager/?ticket=<id>`). Réponse de l'équipe →
  email au client avec le message et un bouton vers la conversation (`/magasin/?support=<id>` ou `/centrale/?support=<id>`).
  Notes internes et changements de statut seuls : pas d'email.
- **Sécurité** : fonction `support-notify` (JWT requis) ; l'appelant ne peut faire partir que SES messages, non internes,
  pas encore notifiés (`support_messages.notified_at`, réservé avant l'envoi : pas de doublon). Clé Brevo en secret
  Supabase uniquement (`BREVO_API_KEY`) ; sans clé, la fonction ne fait rien. Contenu échappé (pas d'injection HTML).
- **Où** : `supabase/functions/support-notify/`, migration `20261031000000_support_notified.sql`,
  appels dans `magasin`, `centrale`, `manager` (`notifySupport`, liens profonds).
- **Retour arrière** : supprimer le secret `BREVO_API_KEY` (plus aucun envoi) ; `git revert`.

### MOD-046 · Alertes de sécurité par email
- **Quoi** : deux emails automatiques Supabase, en français et à la charte : « mot de passe modifié » et
  « adresse email modifiée » (envoyé à l'ancienne adresse, avec contact hello@vitriin.co si ce n'est pas
  la personne). Pas de lien d'action dans ces emails.
- **Où** : `supabase/templates/password_changed_notification.html`, `email_changed_notification.html`,
  `supabase/config.toml` (`[auth.email.notification.*]`).
- **En place** : activés dans Dashboard > Authentication > Emails, objet et contenu vérifiés après rechargement.
- **Retour arrière** : désactiver « Enable notification » sur les deux modèles ; `git revert`.

### MOD-045 · Liens des emails sur app.vitriin.co (page /auth/)
- **Quoi** : les liens des emails (connexion, invitation, mot de passe, confirmation, changement d'email)
  pointent vers `https://app.vitriin.co/auth/?t=…&type=…&next=…` au lieu de `…supabase.co/auth/v1/verify…`.
  La page /auth/ valide le jeton (`verifyOtp` avec `token_hash`) **seulement au clic** sur le bouton : les
  antivirus et aperçus de messagerie (Outlook Safe Links…) ne grillent plus le lien à usage unique.
  La session est rangée sous la clé de l'espace de destination (/v, /magasin, /centrale, /manager) ;
  destination limitée à app.vitriin.co ; le jeton est retiré de la barre d'adresse.
- **Où** : `public/auth/index.html` (nouveau), `supabase/templates/*.html` (`{{ .TokenHash }}`).
- **En place** : les 5 modèles sont mis à jour dans le Dashboard Supabase (vérifié après rechargement).
- **Retour arrière** : remettre `{{ .ConfirmationURL }}` dans les modèles Supabase ; `git revert`.

### MOD-044 · Emails d'authentification en place dans Supabase
- **Quoi** : les 6 modèles (`supabase/templates/*.html`) et leurs objets en français sont enregistrés dans le
  Dashboard (Authentication > Emails > Templates) : Confirm sign up, Invite user, Magic link, Change email,
  Reset password, Reauthentication. Vérifié après rechargement ; aperçu Supabase : logo affiché.
- **Non modifiés** : les notifications de sécurité (mot de passe changé, email changé, etc.), désactivées
  ou en anglais par défaut ; à traduire si on les active.
- **Retour arrière** : recoller les modèles par défaut de Supabase (bouton dans chaque modèle) ou une version
  antérieure des fichiers.

### BUG-007 · Logo des emails non affiché (corrigé)
- **Problème** : le logo hébergé sur app.vitriin.co ne s'affichait pas dans l'aperçu des emails.
- **Correction** : logo déposé dans un bucket public Supabase `email-assets`
  (https://zjugauidrijghesgsmap.supabase.co/storage/v1/object/public/email-assets/logo-vitriin-blanc.png),
  même domaine que l'expéditeur des emails d'auth ; modèles mis à jour. Migration `20261030235500_email_assets_bucket`
  (lecture publique, écriture équipe Vitriin). La copie sur app.vitriin.co reste en secours.
- **Retour arrière** : `git revert` ; supprimer le bucket `email-assets`.

### MOD-043 · Emails d'authentification : logo Vitriin blanc dans le bandeau
- **Quoi** : `public/email/logo-vitriin-blanc.png` (logo officiel du projet passé en blanc, PNG car Gmail
  n'affiche pas le SVG), servi sur https://app.vitriin.co/email/logo-vitriin-blanc.png, utilisé dans les
  6 modèles `supabase/templates/*.html` (affiché à 140 px, image 2x).
- **Retour arrière** : `git revert` du commit.

### MOD-042 · Manager > Utilisateurs > Gérants : pictos et « Modifier l'email » ; emails d'authentification en français
- **Gérants des magasins** : actions en pictos (modifier l'email, renvoyer l'accès, bloquer / débloquer,
  retirer). « Modifier » : saisie en ligne ; l'email du compte et du magasin est remplacé, un lien pour choisir
  un mot de passe part à la nouvelle adresse. Refusé si l'adresse appartient à un autre compte.
- **Fonction Edge** `manager-invite` v2 : action `change_email` (équipe Vitriin, gérant de ce magasin seulement).
- **Emails Supabase Auth** : 6 modèles HTML en français dans `supabase/templates/` (invitation, lien de connexion,
  confirmation, mot de passe, changement d'email, code), référencés dans `config.toml`. À coller dans le
  Dashboard (pas d'outil pour les pousser d'ici).
- **Retour arrière** : `git revert` ; redéployer `manager-invite` v1.

### MOD-041 · Manager > fiche client > Utilisateurs : gestion des comptes
- **Quoi** : onglet « Utilisateurs ». Équipe de la centrale : ajouter (email + rôle, invitation si nouveau
  compte), changer le rôle, renvoyer l'accès, bloquer / débloquer, retirer. Gérants des magasins : recherche,
  inviter un gérant (email pré-rempli), renvoyer l'accès, bloquer, retirer du magasin. Statuts : invitation en
  attente, bloqué, dernière connexion. La carte « Équipe » de la vue d'ensemble est remplacée par un lien vers l'onglet.
- **Base** : migration `20261030233000_manager_users` : `manager_network_users`, `manager_user_set_role`,
  `manager_user_remove`, `manager_user_block` (équipe Vitriin seulement, via `manager_guard`) ; garde-fous :
  toujours au moins un propriétaire, pas de blocage de son propre compte ni d'un compte de l'équipe Vitriin ;
  le blocage coupe aussi les sessions. `guard_network_owner` laisse l'équipe Vitriin changer un propriétaire.
- **Fonction Edge** `manager-invite` (v1, verify_jwt) : invitation d'un utilisateur centrale ou d'un gérant,
  réservée à l'équipe Vitriin (vérifiée avec le jeton de l'appelant), clé service_role côté serveur seulement.
- **Testé en base** : magasin refusé, dernier propriétaire protégé, auto-blocage refusé, blocage effectif.
- **Retour arrière** : `git revert` ; `drop function` des 4 fonctions et `manager_user_json` ; supprimer la
  fonction Edge `manager-invite` ; restaurer `guard_network_owner` (version de la migration initiale).

### MOD-040 · Manager > fiche client en onglets
- **Quoi** : onglets « Vue d'ensemble » (indicateurs, équipe), « Intégration · x % », « Magasins · n »,
  « Promos · n » (toutes les promos, plus seulement les 12 dernières). L'onglet revient à « Vue d'ensemble »
  quand on ouvre un autre client.
- **Où** : `public/manager/index.html` (vNet, bind).
- **Retour arrière** : `git revert` du commit.

### MOD-039 · Manager > fiche client > Intégration : on coche directement la pastille
- **Quoi** : les étapes manuelles (contrat, SEPA, formations) se valident en cliquant la pastille de gauche
  (re-clic pour annuler) ; la case « fait » à droite est supprimée. Étapes automatiques non cliquables.
- **Où** : `public/manager/index.html` (onbHtml, bind).
- **Retour arrière** : `git revert` du commit.

### MOD-038 · App particulier refaite selon la maquette Claude Design « Vitriin » (remplace MOD-036 côté écran)
- **Pourquoi** : la première version (MOD-036) était une page web générique ; Charles voulait les écrans
  particulier de la maquette (projet claude.ai, `Vitriin.dc.html`).
- **Quoi** (`/v/`, app mobile, charte magenta) : Découvrir (« Près de vous », recherche, localisation ou ville,
  filtres par catégorie, « À la une », « Autour de vous », enregistrer), plein écran façon reels (enregistrer,
  coupon, partager, « Trouver en magasin »), coupon avec code-barres, Mes promos (Sauvegardées / Utilisées
  et euros économisés), Enseignes suivies, Profil (statistiques, centres d'intérêt, alertes, rayon, prénom,
  suppression du compte, passer en mode commerçant), fiche commerce `/v/m/<slug>`, lien direct `/v/p/<id>`.
  Connexion par lien email (SMS, Apple, Google : plus tard).
- **Base** : migration `20261030223000_vitrine_app_particulier` : `code_reveals.user_id` (utilisation
  rattachée au compte connecté), table `customer_prefs` (RLS : ses lignes), `customer_me` enrichi
  (prefs, uses), `vitrine_reveal` rattache l'utilisation au compte.
- **Vercel** : réécriture `/v/:path*` vers `/v/index.html`.
- **Retour arrière** : `git revert` du commit (revient à MOD-037) ; colonnes et table sans effet si inutilisées.

### MOD-037 · Vitrine : cartes alignées, adresse sans doublon ; lien vitrine dans les posts Facebook
- **Vitrine** : images des cartes contraintes au carré (les cartes avaient des hauteurs différentes),
  ville non répétée quand l'adresse la contient déjà. Vérifié en ligne : magasin, promo, code Code 128.
- **meta-publish** : sur Facebook, la légende se termine par « En profiter en magasin : https://app.vitriin.co/v/p/<id> »
  (`PUBLIC_VITRINE_URL` pour changer de domaine). Instagram inchangé (liens non cliquables).
  **Code commité, fonction pas encore redéployée** : à déployer avec la prochaine mise à jour de meta-publish
  (les publications Meta réelles attendent l'App Review).
- **Retour arrière** : `git revert` du commit.

### SEC-001 · Coordonnées des gérants lisibles publiquement (corrigé)
- **Problème** : la règle `stores_select_public` (lecture de tous les magasins par tous, y compris
  sans connexion) exposait `contact_email`, `contact_phone`, noms des gérants. Les promos actives
  (avec leurs codes) étaient aussi lisibles directement.
- **Correction** : lecture des magasins réservée aux membres du magasin, de sa centrale et à l'équipe
  Vitriin ; lectures publiques directes de `stores`, `promotions`, `store_promotions` supprimées.
  Le public passe par les fonctions `vitrine_*`, qui ne renvoient que les champs publics.
- **Testé** : anon refusé sur les 3 tables ; gérant démo : 1 magasin visible ; compte client : 0.
- **Retour arrière** : recréer les règles `*_select_public` (déconseillé).

### MOD-036 · Vitrine publique et compte client (app.vitriin.co/v)
- **Quoi** : page `/v/` (promos autour de moi, recherche ville / code postal / magasin), `/v/m/<slug>`
  (vitrine d'un magasin : suivre, itinéraire, partager), `/v/p/<id>` (promo : code en caisse
  EAN-13 ou Code 128, enregistrer, partager), `/v/compte` (connexion par lien email, fil des
  magasins suivis, promos enregistrées, alertes par magasin, suppression du compte).
  Réseaux de démo masqués dans « autour de moi » sauf `?demo=1`.
- **Base** : migration `20261030210000_vitrine_publique` : `vitrine_store`, `vitrine_promo`,
  `vitrine_nearby`, `vitrine_search`, `vitrine_reveal` (compte l'utilisation puis renvoie le code),
  tables `customer_follows` / `customer_saves` (RLS : ses lignes seulement), `customer_me`,
  `customer_delete_account` (refusé pour un compte magasin ou centrale).
- **App magasin** : Réglages > « Voir ma vitrine publique ».
- **Reste à faire** : SMTP Supabase (sinon pas d'email de connexion), URL de redirection
  `https://app.vitriin.co/v/**` dans Supabase Auth, envoi réel des alertes, lien de la vitrine
  dans les publications Meta.
- **Retour arrière** : `git revert` ; `drop function vitrine_*, customer_*` ; `drop table customer_follows, customer_saves`.

### MOD-035 · Manager > Site web : onglets Statistiques / Demandes
- **Quoi** : onglets « Statistiques » (visites) et « Demandes » (liste d'attente, avec compteur).
  Carte « Compteur à installer » et code du compteur (SNIPPET) retirés : le compteur est en place sur vitriin.fr.
- **Où** : `public/manager/index.html` (vSite, vWaitlist, bind).
- **Retour arrière** : `git revert` du commit.

### MOD-033 · Liste d'attente des indépendants (vitriin.fr → Manager)
- **Quoi** : table fermée `waitlist_signups` ; `join_waitlist` (anon, email validé,
  doublon ignoré sans le révéler, plafond 200/h) ; `manager_waitlist` et
  `manager_waitlist_contacted` (équipe Vitriin seulement). Manager > Site web :
  carte « Liste d'attente indépendants » avec case « contacté ».
- **Où** : migration `20261030170000_waitlist_independants`, `public/manager/index.html`.
- **Sécurité testée** : anon sans droit de lecture sur la table ni sur `manager_waitlist`.
- **Retour arrière** : `git revert` du commit ; `drop function` des 4 fonctions et `drop table public.waitlist_signups`.

### MOD-034 · vitriin.fr : quick wins SEO (non publié)
- **Quoi** : réponses FAQ présentes dans le HTML serveur, JSON-LD FAQPage, title et
  description orientés acheteurs, UTM sur les liens Calendly (utm_content = emplacement),
  `llms.txt`, `lastmod` au sitemap. Décisions de Charles : email reste en .co,
  bandeau de preuve en attente de l'accord Brisach, indépendants en liste d'attente.
- **Où** : projet Lovable « Vitriin ».
- **Retour arrière** : version antérieure dans l'historique Lovable.

### MOD-032 · vitriin.fr : hero avec téléphone et maquettes de publications (non publié)
- **Quoi** : hero en deux colonnes avec un iPhone dessiné en CSS et 6 écrans
  qui défilent (légendes synchronisées). 3e écran : maquette de post Instagram
  en code. Étape « 02 · Le magasin » : même promo publiée par deux magasins
  (Instagram Lyon, Facebook Nantes), sans logos officiels. Pastilles flottantes
  masquées sur l'écran Instagram.
- **Où** : projet Lovable « Vitriin » (c4816cab…) : `src/components/site/HeroPhone.tsx`,
  `src/components/site/SocialMockups.tsx`, `src/routes/index.tsx`, `src/styles.css`.
  Commits Lovable cac06f7, 04f0342, 6c445f8.
- **Statut** : aperçu seulement, publication après validation de Charles.
  Les captures de l'app (écrans 1, 2, 4, 5, 6) sont à remplacer par les UI actuelles.
- **Retour arrière** : restaurer une version antérieure dans l'historique Lovable.

### MOD-031 · Manager : démos au nom d'un prospect
- **Quoi** : Manager > Démos > « Démos au nom d'un prospect ». On saisit le
  nom de l'enseigne, le secteur et (facultatif) son logo ; le Manager génère
  une démo complète à ce nom (centrale, 20 magasins « Enseigne Ville »,
  promos du secteur, statistiques, codes utilisés) et propose de l'activer.
  Chaque démo prospect a ses boutons Utiliser / Ouvrir / Supprimer.
  30 démos prospects au plus.
- **Technique** : générateur interne `demo_build_network` dérivé de
  `manager_build_demo` (nom, logo, drapeau `settings.prospect`) ;
  `manager_prospect_demo`, `manager_delete_demo` (démos prospects
  uniquement, bascule sur Chausselandia si elle était active) ; la
  réinitialisation d'une démo sectorielle ne touche jamais les démos
  prospects. Logo envoyé dans `promo-media/demo/`, dépôt réservé à
  l'équipe Vitriin (policy `promo_media_insert_platform_admin`).
- **Fichiers** : `manager/index.html`, migration `20261030155446_manager_prospect_demos`.
- **Retour arrière** : `git revert` ; supprimer les démos prospects depuis le Manager.

### MOD-030 · Support : messages en direct et délai de réponse affiché
- **Quoi** : une conversation ouverte se met à jour toute seule toutes les
  4 secondes (app magasin, Espace Centrale, Manager), sans perdre le message
  en cours de saisie. Le compteur « Support » du Manager se met à jour
  toutes les 20 s (avec une notification), le badge de l'Espace Centrale
  toutes les 30 s, celui de l'app magasin avec le rafraîchissement habituel
  (15 s). Vérification suspendue quand l'onglet n'est pas visible.
- **Délai** : « réponse sous 24 h (jours ouvrés) » affiché à l'ouverture du
  support, dans le formulaire, après l'envoi, et sous la conversation tant
  que la dernière réponse vient du client.
- **Choix technique** : vérification périodique plutôt que Supabase
  Realtime, qui demanderait d'ouvrir les tables de support en lecture
  directe (elles restent fermées, accès par fonctions uniquement).
- **Fichiers** : `magasin/index.html`, `centrale/index.html`, `manager/index.html`.
- **Retour arrière** : `git revert` du commit MOD-030.

### MOD-029 · Manager : « À traiter » actionnable, support (tickets), checklist d'intégration
- **À traiter** : chaque élément se marque comme lu (« Lu ✓ », ou « Tout
  marquer comme lu », avec « Annuler » quelques secondes). Un élément lu
  revient si la situation change (nouvelle erreur, nouvelle date). Au clic,
  une fenêtre explique la cause et les étapes pour résoudre, avec les
  actions prêtes : email au gérant pré-rédigé (reconnexion, publication
  refusée, connexion des réseaux, relance de centrale), copier le message,
  renvoyer l'accès, renvoyer l'invitation, ouvrir la fiche client ou le
  ticket. Les nouveaux tickets apparaissent aussi dans « À traiter ».
- **Support** : bouton « Contacter le support Vitriin » dans l'app magasin
  (Réglages > Support) et « Support Vitriin » dans l'Espace Centrale (barre
  latérale). Le client choisit un sujet, écrit, suit ses demandes et voit
  « Nouvelle réponse ». La demande joint automatiquement l'état des comptes
  et le dernier échec. Manager > Support : liste filtrable, fil de
  discussion, réponse, note interne (jamais visible du client), statut,
  urgence, situation au moment de la demande et situation actuelle, autres
  demandes du même client.
- **Intégration** : sur chaque fiche client, 11 étapes avec barre
  d'avancement : 7 calculées automatiquement (logo et coordonnées, magasins
  importés, invitations, 80 % activés, 80 % connectés, première promo,
  première publication) et 4 à cocher (contrat, mandat SEPA, formation de
  la centrale, formation des magasins). Avancement visible dans la liste
  Clients.
- **Sécurité** : tables `support_tickets`, `support_messages`,
  `manager_dismissed`, `network_onboarding` sans policy ; accès par
  fonctions vérifiées côté serveur (membre du magasin ou de la centrale pour
  créer, auteur seulement pour lire et répondre, notes internes filtrées ;
  équipe Vitriin pour le reste). Limites : 10 demandes et 40 messages par
  heure et par personne. Testé : autre magasin refusé, accès direct aux
  tables refusé, notes internes invisibles.
- **Fichiers** : `manager/index.html`, `magasin/index.html`,
  `centrale/index.html`, migration `20261030160000_manager_support_onboarding`.
- **Retour arrière** : `git revert` du commit ; les tables peuvent rester.

### MOD-028 · vitriin.fr : compteur de visites installé
- **Quoi** : script du Manager (onglet Site web) ajouté au site Lovable
  « Vitrine Locale » dans `src/routes/__root.tsx` (exécuté une fois, côté
  navigateur), commit Lovable `5a3d74f`, site republié.
- **Retour arrière** : dans Lovable, revenir à la version précédente de
  `src/routes/__root.tsx` puis republier.

### MOD-027 · Manager : navigation en barre latérale
- **Quoi** : les onglets du haut deviennent une barre latérale, comme dans
  l'Espace Centrale, regroupée en Pilotage (Accueil, Clients, Magasins),
  Commercial (Démos, Site web) et Technique (Santé). En bas : « Inclure les
  démos », compte connecté, déconnexion. Sur mobile, la barre devient un
  menu horizontal en haut.
- **Fichier** : `web/espace-magasin/public/manager/index.html`.
- **Retour arrière** : `git revert` du commit MOD-027.

### MOD-026 · Manager V2 : poste de pilotage de Vitriin
- **Quoi** : le Manager passe en onglets.
  - **Accueil** : centrales, magasins, part connectée, publications 30 j (et
    tendance), personnes touchées, codes utilisés, visites du site, échecs ;
    courbes 30 jours ; colonne « À traiter » (comptes à reconnecter, échecs
    de publication, magasins invités qui n'ont rien connecté, centrales
    inactives depuis 15 j) ; échéances (Meta 30/11, Brisach 8/12).
  - **Clients** : liste puis fiche centrale (équipe et dernière connexion,
    promos et taux de relais, magasins avec état du compte, réseaux,
    publications, promos à valider). Actions : inviter un gérant ou tous ceux
    en attente, « Renvoyer l'accès » (email pour choisir un nouveau mot de
    passe).
  - **Magasins** : tous les magasins avec recherche et filtres (sans réseau,
    à reconnecter, pas activés, sans publication, indépendants).
  - **Démos** : inchangé.
  - **Santé** : taux de réussite des publications, échecs par cause, comptes
    à reconnecter ou désactivés, invitations jamais ouvertes, dernière
    collecte des statistiques Meta.
  - **Site web** : pages vues, visiteurs, clics « démo » et « essai »,
    pages, provenance, appareils, et le code du compteur à installer.
  - Case « Inclure les démos dans les chiffres ».
- **Compteur de visites** : table `site_visits` (aucune policy, illisible du
  navigateur) alimentée par `track_visit` (seule fonction ouverte au public :
  valeurs bornées, vitriin.fr uniquement, 30 envois par minute et par
  visiteur au plus). Sans cookie, sans IP ; identifiant visiteur aléatoire
  renouvelé chaque jour.
- **Sécurité** : fonctions `manager_dashboard`, `manager_network`,
  `manager_stores`, `manager_health`, `manager_site` protégées par
  `is_platform_admin()` (testé : magasin et visiteur refusés).
  `network-stores-invite` (version 2) accepte aussi l'équipe Vitriin.
- **Fichiers** : `manager/index.html`, migration `20261030150000_manager_v2`,
  `supabase/functions/network-stores-invite/index.ts`.
- **Retour arrière** : `git revert` du commit ; les fonctions SQL peuvent
  rester, elles ne sont utilisées que par le Manager.

### MOD-025 · Manager : logo des enseignes de démo
- **Quoi** : chaque carte de démo affiche le logo de l'enseigne (sinon son
  initiale). Logos créés pour Flamme & Foyer et Jardins & Saisons
  (`public/demo/*.svg`, servis par app.vitriin.co), enregistrés dans
  `demo_sectors.logo_url` et repris à chaque génération ; ils apparaissent
  aussi dans la centrale et l'app magasin de ces démos.
- **Fichiers** : `manager/index.html`, `public/demo/`, migration
  `20261030143000_manager_demos_logos`.
- **Retour arrière** : `git revert` du commit ; `update networks set logo_url = null` sur les démos.

### BUG-006 · Médiathèque du magasin figée sur les images Chausselandia
- **Symptôme** : dans une promo, « Médiathèque » proposait toujours les mêmes
  photos de chaussures, quelle que soit l'enseigne.
- **Cause** : liste d'images de démo écrite en dur dans l'app (`LIB`).
- **Correction** : la médiathèque affiche les visuels des promos réellement
  envoyées par la centrale du magasin (champ `netMedia`, visuels d'origine,
  plus récents d'abord, sans doublon, https uniquement). Message si la
  centrale n'a encore rien partagé. Constantes `LIB` et `IMG` supprimées.
- **Fichier** : `web/espace-magasin/public/magasin/index.html`.
- **Retour arrière** : `git revert` du commit BUG-006.

### MOD-024 · App magasin : Stats sans « Activité récente »
- **Quoi** : la section « Activité récente » faisait doublon avec « Statut par
  promo » ; elle est retirée (fonction `activity`, styles `.act`, champs
  `recAt` / `schedSetAt` et utilitaire `ago` devenus inutiles). Toucher une
  ligne de « Statut par promo » ouvre toujours toutes les stats de la promo.
- **Fichier** : `web/espace-magasin/public/magasin/index.html`.
- **Retour arrière** : `git revert` du commit MOD-024.

### MOD-023 · Vitriin Manager (super admin) et démos sectorielles
- **Quoi** : nouvelle page `app.vitriin.co/manager`, réservée à l'équipe Vitriin
  (au départ : charles@hubandup.com). Bloc « Démos » : une carte par secteur
  (Retail · Chausselandia, Cheminées et poêles · Flamme & Foyer, Jardinerie ·
  Jardins & Saisons) avec ses chiffres, « Utiliser cette démo » (bascule la
  centrale de Charles et le compte magasin.demo@vitriin.co sur ce réseau),
  « Réinitialiser » (recrée la démo avec des dates et chiffres à jour).
  Bloc « Clients » : centrales réelles, magasins, connexions, promos,
  publications, équipe.
- **Générateur** : `manager_build_demo(secteur)` crée 20 magasins (villes
  françaises), comptes Facebook / Instagram simulés (dont partiels, un à
  reconnecter, deux sans réseau), 7 promos centrale (passées, en cours, à
  venir, une obligatoire), 2 promos du magasin vitrine, publications avec
  statistiques qui montent (demo_tick), codes utilisés. Contenu des secteurs
  dans la table `demo_sectors` : ajouter un secteur = ajouter une ligne.
- **Sécurité** : table `platform_admins` sans policy (illisible depuis le
  navigateur) ; `is_platform_admin()` vérifié dans chaque fonction manager ;
  fonctions internes demo_* non exécutables par les utilisateurs ; testé :
  magasin et visiteur refusés.
- **Fichiers** : `web/espace-magasin/public/manager/index.html`, migrations
  `20261030135650_manager_demos`, `20261030135705_manager_demos_ig_parent`.
- **Retour arrière** : réactiver Chausselandia depuis le Manager ; `git revert`
  du commit ; les démos générées se suppriment via `demo_drop_network`.

### MOD-022 · Centrale : import Excel / CSV des promos
- **Quoi** : carte « Importer un fichier Excel » (page Promotions) et bouton
  « Importer » de la barre latérale. Une ligne = une promo (Titre, Offre,
  Texte, Code en caisse, EAN, Début, Fin, Obligatoire, Image). Image : lien
  https, ou nom d'un fichier sélectionné à côté (recadré au format
  Instagram et envoyé dans le stockage). Aperçu ligne par ligne avec les
  erreurs (image manquante, dates illisibles…), puis envoi à tous les
  magasins ou enregistrement en brouillon. Type de promo déduit de l'offre ;
  formats par défaut Instagram Feed + Facebook Photo. Mêmes contrôles que
  la création manuelle (`promoRow`). 100 promos max par fichier.
- **Fichier** : `web/espace-magasin/public/centrale/index.html`.
- **Retour arrière** : `git revert` du commit MOD-022.

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
