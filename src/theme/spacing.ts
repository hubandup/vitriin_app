/**
 * Vitriin — espacements
 *
 * Extraits de la maquette Vitriin.dc.html. La maquette n'est PAS sur une grille
 * 4pt stricte (elle emploie 6, 9, 11, 14…) : ces valeurs intermédiaires sont
 * conservées telles quelles. Les paddings vraiment ponctuels restent inline dans
 * les composants qui les portent.
 *
 * `screen` (20) = padding horizontal des écrans app ; `gutter` (26) = padding
 * horizontal des écrans auth / onboarding.
 */
export const spacing = {
  xxs: 2,
  xs: 4,
  sm: 6,
  s: 8,
  ms: 10,
  m: 12,
  ml: 14,
  l: 16,
  xl: 18,
  xxl: 20,
  xxxl: 24,
  x4: 26,
  x5: 30,
  x6: 34,

  screen: 20,
  gutter: 26,
} as const;

export type Spacing = keyof typeof spacing;
