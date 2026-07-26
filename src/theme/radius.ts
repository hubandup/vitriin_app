/**
 * Vitriin — rayons de bordure
 *
 * Extraits de la maquette. Correspondances :
 *  xs 6   → tags de statut / mécanique inline
 *  sm 10  → petites pastilles
 *  md 13  → champs de saisie, barre de recherche
 *  lg 15  → boutons principaux
 *  xl 18  → cartes standard
 *  xxl 22 → cartes fortes (choix de rôle, carte e-mail)
 *  xxxl 24→ modales
 *  pill   → pastilles, avatars, interrupteurs (999)
 */
export const radius = {
  xs: 6,
  sm: 10,
  md: 13,
  lg: 15,
  xl: 18,
  xxl: 22,
  xxxl: 24,
  pill: 999,
} as const;

export type Radius = keyof typeof radius;
