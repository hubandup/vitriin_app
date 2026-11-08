/**
 * Vitriin — ombres
 *
 * DEUX systèmes pour un seul résultat visuel :
 *  • iOS     → shadowColor / shadowOffset / shadowOpacity / shadowRadius.
 *              La couleur de l'ombre est libre → on reproduit le GLOW magenta.
 *  • Android → elevation (entier). L'ombre est GÉRÉE PAR LE SYSTÈME et n'est PAS
 *              colorable avant l'API 28 → le glow magenta est perdu, il ne reste
 *              qu'une profondeur grise neutre. C'est un écart iOS/Android assumé.
 *
 * Les opacités sont celles de la maquette (subtiles). Le glow corail `#f1917d`
 * de la maquette est reteint en magenta `#e5087e` (décision rebrand).
 *
 * Usage : `style={[styles.card, shadows.card]}`.
 */
import { Platform, type ViewStyle } from 'react-native';
import { palette } from './colors';

const ios = (
  color: string,
  height: number,
  opacity: number,
  blur: number,
): ViewStyle => ({
  shadowColor: color,
  shadowOffset: { width: 0, height },
  shadowOpacity: opacity,
  shadowRadius: blur,
});

const shadow = (iosStyle: ViewStyle, elevation: number): ViewStyle =>
  Platform.select({ ios: iosStyle, android: { elevation }, default: iosStyle }) as ViewStyle;

export const shadows = {
  /** Glow des actions primaires (bouton, FAB) — teinté magenta sur iOS. */
  glow: shadow(ios(palette.magenta, 8, 0.4, 20), 8),
  /** Glow renforcé (logo, FAB). */
  glowStrong: shadow(ios(palette.magenta, 12, 0.4, 28), 12),

  /** Carte standard — ombre brune neutre, très douce. */
  card: shadow(ios('#3C2D28', 6, 0.06, 18), 3),
  /** Carte légère (liste, canal). */
  cardSoft: shadow(ios('#3C2D28', 4, 0.05, 12), 2),
  /** Surface surélevée (carte e-mail, modale). */
  raised: shadow(ios('#3C2D28', 10, 0.09, 26), 6),

  /** Dock de navigation flottant — 0 10 30 rgba(45,45,45,.14). */
  dock: shadow(ios('#2D2D2D', 10, 0.14, 30), 10),
  /** « + » central du dock — glow magenta. */
  fab: shadow(ios(palette.magenta, 8, 0.35, 20), 8),

  /** Bouton d'interrupteur (knob). */
  knob: shadow(ios('#000000', 1, 0.25, 3), 2),
} as const;

export type ShadowVariant = keyof typeof shadows;
