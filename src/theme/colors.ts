/**
 * Vitriin — couleurs
 *
 * SOURCE DE VÉRITÉ : .cursor/rules/vitriin-brand.mdc (tokens verrouillés).
 *
 * ⚠️ La maquette Vitriin.dc.html est PRÉ-REBRAND. Ses couleurs (primaire corail
 * `#f1917d`, pas de dégradé, DM Sans partout) datent de l'ancienne identité et
 * NE SONT PAS reprises ici — c'est la « violation » que la règle de marque
 * anticipe. Seuls la STRUCTURE, les espacements, les rayons et l'échelle typo de
 * la maquette sont conservés (voir spacing.ts / radius.ts / typography.ts).
 *
 * Les surfaces teintées (`primarySurface`, `tealSurface`…) ne sont pas dans la
 * charte : elles sont DÉRIVÉES des teintes de marque (hue de marque posée à ~8 %
 * sur blanc). Aucune teinte inventée — chaque dérivation est annotée.
 */

/** Palette verrouillée — vitriin-brand.mdc, ne pas modifier sans mise à jour de la règle. */
export const palette = {
  magenta: '#e5087e', // primary
  magentaDark: '#c4076c', // primary pressed
  violet: '#951b81',
  violetDark: '#80176f', // DÉRIVÉ : violet assombri ~12 % (état pressed du dégradé)
  cream: '#f5ecd3',
  teal: '#0c9875',
  tealLight: '#5ebca3',
  ink: '#2D2D2D',
  muted: '#6F6A63', // MOD-077 : #888888 ne passait pas le contraste AA sur blanc (3,5:1) ; #6F6A63 = 5,3:1
  line: '#EEECE8',
  white: '#FFFFFF',
} as const;

export const colors = {
  // — Marque (verrouillé) —
  primary: palette.magenta,
  primaryPressed: palette.magentaDark,
  violet: palette.violet,
  teal: palette.teal,
  tealLight: palette.tealLight,
  cream: palette.cream,

  // — Texte —
  ink: palette.ink,
  muted: palette.muted,
  faint: '#B9B6B2', // DÉRIVÉ : point médian muted↔line — placeholders, horodatages, texte désactivé
  onPrimary: palette.white,

  // — Surfaces —
  surface: palette.white,
  line: palette.line,
  primarySurface: '#FDF1F7', // DÉRIVÉ : magenta @ ~6 % sur blanc — fond d'une tuile sélectionnée
  pinkSurface: '#FBE6F1', // DÉRIVÉ : magenta @ ~10 % — carte centrale, pastille de compteur
  violetSurface: '#F7EDF5', // DÉRIVÉ : violet @ ~8 % sur blanc
  tealSurface: '#E3F2EC', // DÉRIVÉ : teal @ ~11 % sur blanc — succès (« Promo validée »)
  tealText: '#0A7A5E', // DÉRIVÉ : teal assombri pour le texte (contraste AA)
  creamSurface: palette.cream, // la crème de marque sert directement de surface chaude
  neutralSurface: '#F6F5F3', // DÉRIVÉ : famille de `line` — LA surface du nouveau design (tuiles KPI, boutons ronds, lignes de canal)
  inkSurface: palette.ink, // carte d'action noire (« Valider la promo d'un client »)

  // — Danger / erreur / expiré —
  // ⚠️ À VALIDER PAR CHARLY. vitriin-brand.mdc ne définit AUCUNE couleur danger.
  // Défaut = le terracotta que la maquette utilisait déjà (déconnexion + statut
  // expiré). Ce n'est donc pas une couleur inventée, mais un placeholder repris
  // de la maquette en attendant un token de marque dédié.
  danger: '#C47565',
  dangerSurface: '#F7ECE9', // DÉRIVÉ : danger @ ~14 % sur blanc

  // — Divers —
  trackOff: '#DCD9D2', // rail des interrupteurs à l'état off (neutre chaud)
} as const;

/** Dégradés — passés tels quels à expo-linear-gradient (readonly → spread si besoin). */
export const gradients = {
  /** Signature de la marque — magenta → violet. Bouton primary, blocs forts. */
  brand: [palette.magenta, palette.violet] as const,
  /** État pressed du bouton primary. */
  brandPressed: [palette.magentaDark, palette.violetDark] as const,
  /**
   * Fond des écrans auth / onboarding. Neutres chauds (validés par Charly :
   * « ils passent avec le magenta »), pas l'ancien corail. locations [0,.48,1].
   */
  authBackground: ['#fdf5f3', '#faf6f0', '#f2f6f2'] as const,
} as const;

/**
 * Couleurs OFFICIELLES des marques tierces — pour ChannelIcon UNIQUEMENT.
 * Ce ne sont pas nos couleurs ; ne jamais les mélanger à la palette Vitriin.
 */
/** Tracés officiels (Simple Icons 16.37.0), viewBox 24×24 — ChannelIcon les dessine avec react-native-svg. */
export const channelPaths = {
  facebook: 'M9.101 23.691v-7.98H6.627v-3.667h2.474v-1.58c0-4.085 1.848-5.978 5.858-5.978.401 0 .955.042 1.468.103a8.68 8.68 0 0 1 1.141.195v3.325a8.623 8.623 0 0 0-.653-.036 26.805 26.805 0 0 0-.733-.009c-.707 0-1.259.096-1.675.309a1.686 1.686 0 0 0-.679.622c-.258.42-.374.995-.374 1.752v1.297h3.919l-.386 2.103-.287 1.564h-3.246v8.245C19.396 23.238 24 18.179 24 12.044c0-6.627-5.373-12-12-12s-12 5.373-12 12c0 5.628 3.874 10.35 9.101 11.647Z',
  instagram: 'M7.0301.084c-1.2768.0602-2.1487.264-2.911.5634-.7888.3075-1.4575.72-2.1228 1.3877-.6652.6677-1.075 1.3368-1.3802 2.127-.2954.7638-.4956 1.6365-.552 2.914-.0564 1.2775-.0689 1.6882-.0626 4.947.0062 3.2586.0206 3.6671.0825 4.9473.061 1.2765.264 2.1482.5635 2.9107.308.7889.72 1.4573 1.388 2.1228.6679.6655 1.3365 1.0743 2.1285 1.38.7632.295 1.6361.4961 2.9134.552 1.2773.056 1.6884.069 4.9462.0627 3.2578-.0062 3.668-.0207 4.9478-.0814 1.28-.0607 2.147-.2652 2.9098-.5633.7889-.3086 1.4578-.72 2.1228-1.3881.665-.6682 1.0745-1.3378 1.3795-2.1284.2957-.7632.4966-1.636.552-2.9124.056-1.2809.0692-1.6898.063-4.948-.0063-3.2583-.021-3.6668-.0817-4.9465-.0607-1.2797-.264-2.1487-.5633-2.9117-.3084-.7889-.72-1.4568-1.3876-2.1228C21.2982 1.33 20.628.9208 19.8378.6165 19.074.321 18.2017.1197 16.9244.0645 15.6471.0093 15.236-.005 11.977.0014 8.718.0076 8.31.0215 7.0301.0839m.1402 21.6932c-1.17-.0509-1.8053-.2453-2.2287-.408-.5606-.216-.96-.4771-1.3819-.895-.422-.4178-.6811-.8186-.9-1.378-.1644-.4234-.3624-1.058-.4171-2.228-.0595-1.2645-.072-1.6442-.079-4.848-.007-3.2037.0053-3.583.0607-4.848.05-1.169.2456-1.805.408-2.2282.216-.5613.4762-.96.895-1.3816.4188-.4217.8184-.6814 1.3783-.9003.423-.1651 1.0575-.3614 2.227-.4171 1.2655-.06 1.6447-.072 4.848-.079 3.2033-.007 3.5835.005 4.8495.0608 1.169.0508 1.8053.2445 2.228.408.5608.216.96.4754 1.3816.895.4217.4194.6816.8176.9005 1.3787.1653.4217.3617 1.056.4169 2.2263.0602 1.2655.0739 1.645.0796 4.848.0058 3.203-.0055 3.5834-.061 4.848-.051 1.17-.245 1.8055-.408 2.2294-.216.5604-.4763.96-.8954 1.3814-.419.4215-.8181.6811-1.3783.9-.4224.1649-1.0577.3617-2.2262.4174-1.2656.0595-1.6448.072-4.8493.079-3.2045.007-3.5825-.006-4.848-.0608M16.953 5.5864A1.44 1.44 0 1 0 18.39 4.144a1.44 1.44 0 0 0-1.437 1.4424M5.8385 12.012c.0067 3.4032 2.7706 6.1557 6.173 6.1493 3.4026-.0065 6.157-2.7701 6.1506-6.1733-.0065-3.4032-2.771-6.1565-6.174-6.1498-3.403.0067-6.156 2.771-6.1496 6.1738M8 12.0077a4 4 0 1 1 4.008 3.9921A3.9996 3.9996 0 0 1 8 12.0077',
} as const;

export const channelColors = {
  facebook: '#0866FF', // bleu officiel actuel (Meta brand resources)
  instagram: ['#f9ce34', '#ee2a7b', '#6228d7'] as const, // dégradé officiel
  instagramSolid: '#E1306C',
  tiktok: '#111111',
  whatsapp: '#25D366',
  google: '#4285F4', // ⚠️ Google Business : la maquette n'a que le logo Google Sign-in, pas d'icône Business dédiée
} as const;

/** Statuts de promo — définis à l'identique de la maquette (stStyle), reteints marque. */
export const statusColors = {
  active: { bg: colors.tealSurface, fg: colors.teal, label: 'Active' },
  scheduled: { bg: colors.violetSurface, fg: colors.violet, label: 'Programmée' },
  draft: { bg: colors.neutralSurface, fg: colors.muted, label: 'Brouillon' },
  expired: { bg: colors.dangerSurface, fg: colors.danger, label: 'Expirée' },
} as const;

export type StatusKey = keyof typeof statusColors;
