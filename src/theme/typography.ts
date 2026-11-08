/**
 * Vitriin — typographie
 *
 * Familles : DM Sans (UI + corps) et Racing Sans One (logo + chiffres promo).
 * DM Sans est la police de la maquette, disponible telle quelle sur mobile via
 * @expo-google-fonts/dm-sans — transcription exacte, aucun compromis.
 * Racing Sans One (@expo-google-fonts/racing-sans-one) : STRICTEMENT réservée au
 * logo et aux chiffres promo (`-30%`, `29€`). Jamais en UI, jamais en corps.
 *
 * En React Native, chaque graisse est une famille distincte (pas de fontWeight
 * sur police custom, sous peine de faux-gras). L'échelle et les letter-spacing
 * sont extraits de la maquette ; les valeurs `em` sont converties en px
 * (letterSpacing RN = px = taille × em).
 */
import type { TextStyle } from 'react-native';

export const fonts = {
  regular: 'DMSans_400Regular',
  medium: 'DMSans_500Medium',
  semibold: 'DMSans_600SemiBold',
  bold: 'DMSans_700Bold',
  extrabold: 'DMSans_800ExtraBold',
  /** Logo + chiffres promo uniquement. */
  promo: 'RacingSansOne_400Regular',
} as const;

export const text = {
  /** Chiffres promo (`-30%`, `29€`) — Racing Sans One. Rien d'autre. */
  promo: { fontFamily: fonts.promo, fontSize: 34, letterSpacing: -1, lineHeight: 38 },

  /** Titre d'étape (création, onboarding) — 28 / 800 / -.03em */
  titleXL: { fontFamily: fonts.extrabold, fontSize: 28, letterSpacing: -0.84, lineHeight: 32 },
  /** Titre de page — 32 / 800 / -.03em */
  h1: { fontFamily: fonts.extrabold, fontSize: 32, letterSpacing: -0.96, lineHeight: 36 },
  /** En-tête de section — 20 / 800 / -.02em */
  h2: { fontFamily: fonts.extrabold, fontSize: 20, letterSpacing: -0.4, lineHeight: 25 },
  /** Titre de carte — 16 / 700 */
  h3: { fontFamily: fonts.bold, fontSize: 16, letterSpacing: -0.16, lineHeight: 21 },
  /** Chiffre clé (tuiles KPI) — 24 / 800 / -.02em */
  kpi: { fontFamily: fonts.extrabold, fontSize: 24, letterSpacing: -0.48, lineHeight: 28 },

  /** Libellé du bouton principal — 17 / 800 */
  button: { fontFamily: fonts.extrabold, fontSize: 17, letterSpacing: 0 },
  /** Libellé de bouton secondaire — 15 / 700 */
  buttonSm: { fontFamily: fonts.bold, fontSize: 15, letterSpacing: 0 },

  /** Corps accentué — 15 / 600 */
  bodyStrong: { fontFamily: fonts.semibold, fontSize: 15, lineHeight: 21 },
  /** Corps — 15 / 400 */
  body: { fontFamily: fonts.regular, fontSize: 15, lineHeight: 21 },

  /** Libellé de champ — 13 / 600 */
  label: { fontFamily: fonts.semibold, fontSize: 13, lineHeight: 18 },
  /** Petit texte — 13 / 400 */
  small: { fontFamily: fonts.regular, fontSize: 13, lineHeight: 18 },
  /** Métadonnée — 12 / 500 */
  caption: { fontFamily: fonts.medium, fontSize: 12, lineHeight: 16 },
  /** Eyebrow — 12 / 700 / +.06em, MAJUSCULES */
  eyebrow: {
    fontFamily: fonts.bold,
    fontSize: 12,
    letterSpacing: 0.72,
    lineHeight: 14,
    textTransform: 'uppercase',
  },
  /** Libellé du dock — 11 / 600 (700 pour l'onglet actif) */
  nav: { fontFamily: fonts.semibold, fontSize: 11, lineHeight: 14 },
} satisfies Record<string, TextStyle>;

export type TextVariant = keyof typeof text;
