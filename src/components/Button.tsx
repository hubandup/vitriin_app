/**
 * Button — variantes primary / secondary / ghost / danger.
 * États : normal, pressed (visible : seul retour tactile sur mobile), disabled,
 * loading.
 *
 *  • primary   : dégradé de marque (magenta → violet) + glow. La signature.
 *  • secondary : surface blanche, bordure `line`, texte encre.
 *  • ghost     : transparent, texte discret.
 *  • danger    : surface blanche, bordure `line`, texte danger (comme la maquette
 *                — « Se déconnecter » n'est PAS un bouton rouge plein).
 *
 * Le pressed n'existe pas dans la maquette (statique) : dérivé, sans couleur hors
 * palette (primary → dégradé assombri ; autres → surface teintée).
 */
import type { ReactNode } from 'react';
import {
  ActivityIndicator,
  Pressable,
  StyleSheet,
  Text,
  View,
  type ViewStyle,
} from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { colors, gradients, radius, shadows, spacing, text } from '../theme';

type Variant = 'primary' | 'secondary' | 'ghost' | 'danger';

type Props = {
  label: string;
  onPress?: () => void;
  variant?: Variant;
  disabled?: boolean;
  loading?: boolean;
  icon?: ReactNode;
  size?: 'md' | 'sm';
  fullWidth?: boolean;
};

export function Button({
  label,
  onPress,
  variant = 'primary',
  disabled = false,
  loading = false,
  icon,
  size = 'md',
  fullWidth = true,
}: Props) {
  const isDisabled = disabled || loading;
  const pad = size === 'sm' ? styles.padSm : styles.padMd;
  const labelColor = variant === 'primary' ? colors.onPrimary : TEXT_COLOR[variant];

  const inner = (pressed: boolean) => (
    <View style={styles.row}>
      {loading ? (
        <ActivityIndicator
          size="small"
          color={variant === 'primary' ? colors.onPrimary : colors.primary}
        />
      ) : (
        <>
          {icon}
          <Text style={[text.button, size === 'sm' && styles.labelSm, { color: labelColor }]}>
            {label}
          </Text>
        </>
      )}
    </View>
  );

  // — primary : dégradé + glow —
  if (variant === 'primary') {
    return (
      <Pressable
        onPress={onPress}
        disabled={isDisabled}
        style={[fullWidth && styles.fullWidth, isDisabled && styles.disabled]}
      >
        {({ pressed }) => (
          <View style={[styles.glowWrap, shadows.glow]}>
            <LinearGradient
              colors={[...(pressed ? gradients.brandPressed : gradients.brand)]}
              start={{ x: 0, y: 0 }}
              end={{ x: 1, y: 0 }}
              style={[styles.base, pad]}
            >
              {inner(pressed)}
            </LinearGradient>
          </View>
        )}
      </Pressable>
    );
  }

  // — secondary / ghost / danger —
  return (
    <Pressable
      onPress={onPress}
      disabled={isDisabled}
      style={({ pressed }) => [
        styles.base,
        pad,
        fullWidth && styles.fullWidth,
        SURFACE[variant],
        pressed && PRESSED[variant],
        isDisabled && styles.disabled,
      ]}
    >
      {({ pressed }) => inner(pressed)}
    </Pressable>
  );
}

const TEXT_COLOR: Record<Variant, string> = {
  primary: colors.onPrimary,
  secondary: colors.ink,
  ghost: colors.muted,
  danger: colors.danger,
};

const SURFACE: Record<Variant, ViewStyle> = {
  primary: {},
  secondary: { backgroundColor: colors.surface, borderWidth: 1.5, borderColor: colors.line },
  ghost: { backgroundColor: 'transparent' },
  danger: { backgroundColor: colors.surface, borderWidth: 1.5, borderColor: colors.line },
};

const PRESSED: Record<Variant, ViewStyle> = {
  primary: {},
  secondary: { backgroundColor: colors.neutralSurface },
  ghost: { backgroundColor: colors.neutralSurface },
  danger: { backgroundColor: colors.dangerSurface },
};

const styles = StyleSheet.create({
  base: {
    borderRadius: radius.lg,
    overflow: 'hidden',
    alignItems: 'center',
    justifyContent: 'center',
  },
  glowWrap: { borderRadius: radius.lg },
  padMd: { paddingVertical: 16, paddingHorizontal: spacing.xxl },
  padSm: { paddingVertical: 11, paddingHorizontal: spacing.l },
  fullWidth: { alignSelf: 'stretch' },
  row: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: spacing.s },
  labelSm: { fontSize: 14 },
  disabled: { opacity: 0.45 },
});
