# Plomberie Meta — déploiement et configuration

Quatre Edge Functions, une migration. Aucune interface : le tuyau d'abord.

```
meta-oauth-start     ouvre le flux d'autorisation          JWT requis
meta-oauth-callback  reçoit Meta, chiffre et stocke        PUBLIQUE
meta-publish         publie sur les canaux connectés       JWT requis
meta-health-check    détecte les comptes décrochés         service_role ou JWT
```

---

## 1. Secrets

| Secret | Où le trouver |
|---|---|
| `META_APP_ID` | `1295742995710498` |
| `META_APP_SECRET` | Tableau de bord Meta → Paramètres → De base |
| `META_CONFIG_ID` | Configuration Facebook Login for Business (§2.3) — `1873307593649923` |
| `META_GRAPH_VERSION` | `v25.0` — à revérifier dans le tableau de bord, Meta déprécie tous les ~2 ans |
| `META_REDIRECT_URI` | `https://zjugauidrijghesgsmap.supabase.co/functions/v1/meta-oauth-callback` |
| `META_STATE_SECRET` | `openssl rand -base64 32` |
| `TOKEN_ENCRYPTION_KEY` | `openssl rand -base64 32` — exactement 32 octets |
| `APP_RETURN_URL` | *optionnel* — laisser vide en développement |
| `ALLOWED_ORIGINS` | *optionnel* — origines CORS, `*` par défaut |

`SUPABASE_URL`, `SUPABASE_ANON_KEY` et `SUPABASE_SERVICE_ROLE_KEY` sont injectés
par la plateforme. Le préfixe `SUPABASE_` est réservé : inutile d'essayer de les
poser.

> **`TOKEN_ENCRYPTION_KEY` n'est récupérable nulle part ailleurs.** La perdre
> rend tous les tokens stockés illisibles et oblige chaque commerçant à
> refaire sa connexion. À mettre dans le gestionnaire de mots de passe **avant**
> de la poser ici.

```bash
supabase link --project-ref zjugauidrijghesgsmap

# Heredoc : à coller d'un seul tenant, pas ligne par ligne.
# EOF non quoté pour que $(openssl …) soit évalué.
umask 077
cat > supabase/.env.production <<EOF
META_APP_ID=1295742995710498
META_APP_SECRET=<32 caractères hexadécimaux, Meta → Paramètres → De base>
META_CONFIG_ID=1873307593649923
META_GRAPH_VERSION=v25.0
META_REDIRECT_URI=https://zjugauidrijghesgsmap.supabase.co/functions/v1/meta-oauth-callback
META_STATE_SECRET=$(openssl rand -base64 32)
TOKEN_ENCRYPTION_KEY=$(openssl rand -base64 32)
EOF

supabase secrets set --env-file ./supabase/.env.production
supabase secrets list     # affiche les noms et un condensat, jamais les valeurs
```

`secrets set` s'applique au projet **lié** — d'où le `supabase link` juste
au-dessus. Sans lien, ajouter `--project-ref zjugauidrijghesgsmap`.

`supabase/.env.production` est déjà ignoré par git (motif `.env.*`), mais il
reste sur le disque en clair avec l'App Secret et la clé de chiffrement
dedans. Une fois les secrets poussés, il ne sert plus à rien : le supprimer, ou
le déplacer dans le gestionnaire de mots de passe. Pour une modification
ponctuelle, `supabase secrets set NOM=valeur` évite d'avoir à recréer le
fichier.

Alternative sans CLI : Dashboard → Project Settings → Edge Functions → Secrets.

### Validation au démarrage

`_shared/env.ts` contrôle la **forme** de chaque secret au boot du worker, pas
seulement sa présence : App Secret en 32 hexadécimaux, identifiants numériques,
URI de redirection en `https://` sans slash final et pointant bien sur
`meta-oauth-callback`, clé de chiffrement qui décode à exactement 32 octets, et
rejet des valeurs de remplissage (`COLLER_ICI`, `CHANGEME`, `<…>`…).

C'est délibéré : un secret mal renseigné doit faire échouer le **déploiement**,
pas apparaître trois jours plus tard en `Invalid appsecret` au milieu d'un flux
OAuth chez un commerçant. Si `functions deploy` passe, les secrets sont bons.

---

## 2. Côté Meta, écran par écran

`developers.facebook.com/apps/1295742995710498`

### 2.1 Paramètres de l'app → De base

- **Domaines de l'app** : `zjugauidrijghesgsmap.supabase.co` **et** `vitriin.co`
- URL de la politique de confidentialité — *bloquant pour l'App Review*
- URL des conditions d'utilisation
- Instructions de suppression des données (URL) — *bloquant pour l'App Review*
- Icône 1024×1024, catégorie
- Entreprise liée : Hub & Up — déjà fait, statut Tech Provider validé

### 2.2 Connexion Facebook pour les entreprises → Paramètres

| Réglage | Valeur |
|---|---|
| Connexion OAuth du client | activée |
| Connexion OAuth Web | activée |
| Forcer HTTPS | activée |
| Mode strict pour les URI de redirection | activé |
| Connexion avec le SDK JavaScript | désactivée |

**URI de redirection OAuth valides**, exactement, sans slash final :

```
https://zjugauidrijghesgsmap.supabase.co/functions/v1/meta-oauth-callback
```

> Un espace ou un slash de trop et Meta renvoie `redirect_uri` invalide, sans
> autre explication. C'est l'erreur la plus fréquente de ce flux.

### 2.3 Connexion Facebook pour les entreprises → Configurations

Créer une configuration :

- Type : accès aux ressources
- Ressources : **Pages** et **comptes Instagram**
- Autorisations :
  `pages_show_list`, `pages_read_engagement`, `pages_manage_posts`,
  `instagram_basic`, `instagram_content_publish`, `business_management`

Relever l'**ID de configuration** → `META_CONFIG_ID`.

> La permission s'écrit **`instagram_content_publish`**, pas
> `instagram_content_publishing`. Un nom erroné fait échouer la boîte de
> dialogue sans message clair.

Les permissions ne figurent **pas** dans l'URL d'autorisation : Facebook Login
for Business les lit depuis cette configuration, via `config_id`. C'est pour ça
que le code ne construit aucun paramètre `scope`.

### 2.4 Cas d'utilisation

Vérifier que les cas actifs relèvent bien de l'**Instagram API with Facebook
Login** — publication via la Page. L'autre voie, *Instagram API with Instagram
Login*, utilise d'autres permissions (`instagram_business_*`) et un flux
entièrement différent. Tout le code suppose la première.

### 2.5 Rôles de l'app

Ajouter le compte Facebook de test en **Administrateur** ou **Testeur**. En mode
Développement, seuls ces comptes peuvent autoriser l'app — c'est ce qui permet
de tester avec une vraie Page avant toute soumission.

---

## 3. Déployer

```bash
supabase db push
supabase functions deploy meta-oauth-start meta-oauth-callback \
                          meta-publish meta-health-check
```

`verify_jwt` est porté par `supabase/config.toml` et appliqué au déploiement :
`meta-oauth-callback` y est déclarée publique, les trois autres protégées.

---

## 4. Tester

```bash
cp scripts/smoke-meta.env.example scripts/smoke-meta.env
# renseigner, puis
./scripts/smoke-meta.sh
```

Le parcours complet enchaîne : authentification, magasin, tests négatifs,
autorisation Meta dans un vrai navigateur, contrôle d'étanchéité, promo,
publication, rejeu, santé des comptes.

Sous-commandes : `leaks`, `negatives`, `publish <id>`, `health`.

**Le test qui compte** (`./scripts/smoke-meta.sh leaks`) vérifie trois choses :
aucune colonne ressemblant à un token dans la réponse PostgREST, la RPC
`social_account_token_get` refusée à un JWT utilisateur, et `anon` qui ne voit
rien.

---

## 5. Pourquoi c'est construit comme ça

**Le token n'est pas dans une table exposée.** `public.social_accounts` porte
les métadonnées, `private.social_account_secrets` porte le chiffré. Le schéma
`private` est absent d'`api.schemas` : PostgREST ne le sert pas, quel que soit
le rôle. RLS filtre des lignes, pas des colonnes — tant que le chiffré vit dans
la même table, un `select *` d'un membre du réseau parent le ramène.

**La clé n'est jamais en base.** AES-256-GCM dans l'Edge Function, clé dans un
secret Supabase. Postgres ne voit que du `bytea` opaque : le déchiffrement en
SQL est impossible par construction, pas par policy. L'AAD du GCM lie chaque
chiffré à `store_id|channel|external_account_id`, donc un chiffré recopié d'une
ligne vers une autre ne déchiffre pas.

**On ne garde que le token de Page.** Le token utilisateur longue durée sert en
mémoire, le temps d'appeler `/me/accounts`, puis il est jeté. Il porte
`business_management` et énumère tout le patrimoine Business du commerçant ; un
token de Page ne publie que sur sa Page.

**L'ordre des échanges n'est pas négociable.** Les tokens de Page héritent de la
durée de vie du token utilisateur qui les produit. Dérivés du token court, ils
expirent en une heure ; dérivés du token longue durée, ils n'expirent pas. C'est
l'erreur classique de ce flux.

**Un token de Page meurt sans prévenir.** Pas de date d'expiration : révocation,
perte de l'administration de la Page, changement de mot de passe ne se voient
que par un code d'erreur Graph (190, 200, 10). `meta-publish` marque alors le
compte `revoked` dans la table, et `meta-health-check` le détecte en amont —
pour que la centrale lise « ce point de vente n'est plus connecté » sans
attendre qu'une campagne échoue.

**Le retour OAuth est une page HTML, pas un deep link.** Un deep link ne tient
pas en développement : Expo Go sert l'app sous un schéma `exp://` qui change à
chaque session. La page marche partout sans reconfiguration. Poser
`APP_RETURN_URL` y ajoute un bouton de retour, le jour où il y aura une app
installée.

---

## 6. Planifier la vérification de santé

Dashboard → Integrations → Cron, une fois par heure :

```sql
select net.http_post(
  url     := 'https://zjugauidrijghesgsmap.supabase.co/functions/v1/meta-health-check',
  headers := jsonb_build_object(
               'Authorization', 'Bearer <service_role_key>',
               'Content-Type',  'application/json'),
  body    := '{"stale_after_minutes": 360}'::jsonb
);
```

Le mode balayage ignore les comptes déjà `revoked` : ils ne redeviennent actifs
que par une reconnexion, qui remet le statut à jour d'elle-même.

---

## 7. Reste à faire avant la soumission

Non bloquant pour le code, bloquant pour Meta :

- politique de confidentialité et instructions de suppression des données, à
  des URL publiques ;
- la vidéo du flux complet — se tourne avec `smoke-meta.sh` ;
- révocation réelle côté Meta à la déconnexion (`DELETE /{user-id}/permissions`).
  Aujourd'hui, supprimer la ligne `social_accounts` ne supprime que notre copie.
  À ouvrir si l'App Review l'exige pour les autorisations demandées.
