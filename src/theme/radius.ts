/**
 * Vitriin — rayons de bordure (nouveau design, MOD-077)
 *
 * Formes plus généreuses, comme l'espace magasin et l'app client web :
 *  xs 9    → pastilles de prix sur vignette
 *  sm 14   → tuiles d'icône (40 px)
 *  md 18   → champs de saisie, boutons secondaires, vignettes
 *  lg 20   → bouton principal (58 px), lignes « À faire », tuiles KPI
 *  xl 24   → cartes promo, boîtes de réglages
 *  xxl 26  → carte d'action noire
 *  xxxl 30 → feuilles et cartes de résultat
 *  dock 34 → barre de navigation flottante (68 px de haut)
 *  pill    → pastilles, avatars, boutons ronds, interrupteurs (999)
 */
export const radius = {
  xs: 9,
  sm: 14,
  md: 18,
  lg: 20,
  xl: 24,
  xxl: 26,
  xxxl: 30,
  dock: 34,
  pill: 999,
} as const;

export type Radius = keyof typeof radius;
