# App mobile Vitriin

Une seule application, deux espaces : client (sans compte) et magasin. Les écrans sont ceux de
app.vitriin.co, affichés dans une coquille native. Une correction web arrive donc sur les téléphones
sans passer par les stores.

- `src/shell/rules.ts` : ce qui reste dans l'app, ce qui part dans le navigateur, liens et messages acceptés.
- `src/shell/Shell.tsx` : espace, écran web, liens, notifications.
- `web/espace-magasin/public/shell.js` : le pont côté page, sans effet dans un navigateur.
- Contrôles : `npm test` et `npm run typecheck`.

## Pour sortir la première version

À faire par Charles, dans cet ordre :

1. **Comptes** : Apple Developer (99 $/an), Google Play Console (25 $), Expo (gratuit).
2. **Fusionner** `feat/app-mobile` : Vercel publie `shell.js` et `/retour-app/`. L'app ne fonctionne pas sans eux.
3. **Base et fonctions** : `supabase db push`, puis `supabase functions deploy campaign-notify`.
4. **Projet Expo** : `npm i -g eas-cli`, `eas login`, puis `eas init` (ajoute le `projectId` dans `app.json`).
5. **iPhone** : `eas build --profile production --platform ios` (mot de passe Apple et code à deux facteurs
   demandés), puis `eas submit --platform ios`. La version arrive sur TestFlight.
6. **Android** : `eas build --profile test --platform android` donne un fichier APK à installer directement.

## Notifications

- iOS : `eas build` propose de créer la clé APNs, accepter.
- Android : créer un projet Firebase, ajouter `google-services.json` à la racine et déclarer
  `"googleServicesFile"` dans `app.json`, puis déposer la clé FCM avec `eas credentials`.
- Tant que le `projectId` n'existe pas, l'app ne demande pas l'autorisation et ne s'inscrit nulle part.

## Quand l'app sera dans les stores

- **Liens universels** : publier `web/espace-magasin/public/.well-known/apple-app-site-association`
  (identifiant d'équipe Apple) et `assetlinks.json` (empreinte SHA-256 de la signature Android).
  En attendant, les liens https s'ouvrent dans le navigateur.
- **Bandeaux web** : renseigner `STORES` dans `public/v/index.html`.

## À contrôler sur un vrai téléphone

- Connexion Facebook : aller-retour complet depuis Réglages, sur iPhone et sur Android.
- Clavier sur Android : les champs restent visibles au-dessus du clavier.
- Géolocalisation, choix d'une photo, partage.
- Session conservée après fermeture de l'app, dans les deux espaces.
- Déconnexion : plus de notification pour ce compte.

## Validation Apple

La règle 4.2 refuse les sites simplement emballés. Atouts déjà en place : onglets natifs, écran de
choix, écran hors connexion, notifications, partage natif, pas de lien vers le site. Il faudra fournir
au relecteur un compte de démonstration magasin. Le paiement reste hors de l'app.
