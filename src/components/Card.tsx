/**
 * Card — surface de base.
 *
 *  • standard : rayon 18, padding 16, ombre douce (cartes fortes de la maquette).
 *  • compact  : rayon 16, padding 11 (lignes de liste).
 *
 * Rendue pressable si `onPress` est fourni (retour tactile léger).
 */
import type { ReactNode } from 'react';
import { Pressable, StyleSheet, View, type ViewStyle } from 'react-native';
import { colors, radius, shadows, spacing } from '../theme';

type Props = {
  children: ReactNode;
  variant?: 'standard' | 'compact';
  onPress?: () => void;
  style?: ViewStyle;
};

export function Card({ children, variant = 'standard', onPress, style }: Props) {
  const cardStyle = [
    styles.base,
    variant === 'standard' ? styles.standard : styles.compact,
    style,
  ];

  if (onPress) {
    return (
      <Pressable
        onPress={onPress}
        style={({ pressed }) => [...cardStyle, pressed && styles.pressed]}
      >
        {children}
      </Pressable>
    );
  }

  return <View style={cardStyle}>{children}</View>;
}

const styles = StyleSheet.create({
  base: {
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.line,
  },
  standard: {
    borderRadius: radius.xl,
    padding: spacing.l,
    ...shadows.cardSoft,
  },
  compact: {
    borderRadius: 16,
    padding: 11,
  },
  pressed: { backgroundColor: colors.neutralSurface },
});
