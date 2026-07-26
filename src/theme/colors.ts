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
  muted: '#888888',
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
  primarySurface: '#FDEBF5', // DÉRIVÉ : magenta @ ~8 % sur blanc — remplace l'ancien --rose #fdf5f3
  violetSurface: '#F7EDF5', // DÉRIVÉ : violet @ ~8 % sur blanc
  tealSurface: '#ECF7F4', // DÉRIVÉ : teal @ ~8 % sur blanc — remplace l'ancien --mint #f2f6f2
  creamSurface: palette.cream, // la crème de marque sert directement de surface chaude
  neutralSurface: '#F4F3F0', // DÉRIVÉ : famille de `line`, éclaircie — fonds segmentés, brouillon

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
export const channelColors = {
  facebook: '#1877F2',
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
