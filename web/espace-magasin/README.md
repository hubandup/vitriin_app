# Espace magasin (app.vitriin.co)

Page web unique qui déroule le parcours magasin complet : connexion, magasin,
connexion Facebook et Instagram, publication d'une promotion, statistiques.
C'est le parcours présenté à Meta pour l'App Review.

Déployée sur Vercel (projet `vitriin-espace`, domaine `app.vitriin.co`).
`build.mjs` génère au build le visuel de test `promo-test.jpg` (JPEG carré,
format accepté par Instagram).

## Espace Centrale (app.vitriin.co/centrale)

`public/centrale/index.html` : le back-office de la centrale, calé sur la
maquette Claude Design « Vitriin Centrale ». Tableau de bord, promotions
(création, envoi aux magasins, suivi magasin par magasin), magasins (état des
connexions, invitation par lien `/?rejoindre=CODE`), audience (à venir).

La centrale n'appelle jamais Meta : elle crée des activations
(`send_promotion`), chaque magasin publie depuis l'Espace magasin. Le code de
caisse est écrit dans le texte du post à la création de la promo.

Côté magasin, `index.html` gagne deux étapes : « Mon réseau » (rejoindre par
code ou lien d'invitation) et « Promos du réseau » (activer, refuser, publier).

Migration associée : `20261028223629_espace_centrale.sql`.

## App magasin, version démo (app.vitriin.co/magasin)

`public/magasin/index.html` : l'app magasin calée sur la maquette Claude Design
« Vitriin App » (magenta), installable en plein écran sur l'écran d'accueil
(manifest + balises Apple).

Branchée sur Supabase, dans la même base que l'Espace Centrale : une promo
envoyée par la centrale apparaît dans l'app (rafraîchissement toutes les 15 s
et au retour sur l'onglet), et ce que fait le magasin (activer, refuser,
programmer, publier) remonte dans le suivi de la centrale.

Publication SIMULÉE : RPC `demo_publish`, `demo_reconnect`, `demo_tick`
(migration `demo_mode`), autorisées uniquement pour un réseau `is_demo`.
Aucun appel à Meta depuis cette page.

Démo « Chausselandia » : 20 magasins, 10 promos centrale, 3 promos du magasin
de Lyon (`supabase/seed/demo_chausselandia.sql`). Compte magasin :
`magasin.demo@vitriin.co` (mot de passe hors dépôt). Centrale : compte
administrateur du réseau Chausselandia.
