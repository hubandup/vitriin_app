/**
 * Badge — statuts de promo et étiquettes.
 *
 *  • statuts : active / scheduled / draft / expired — couleurs de statusColors
 *    (identiques à la maquette, reteintes marque).
 *  • category : pastille teintée magenta (chip de catégorie sélectionnée).
 *  • count : pastille compteur (ex. « 12 actives »).
 *
 * `dot` ajoute une pastille de couleur avant le label et force la forme pilule
 * (comme l'indicateur « Actif » de l'en-tête magasin).
 */
import { StyleSheet, Text, View } from 'react-native';
import { colors, radius, spacing, statusColors, text, type StatusKey } from '../theme';

type Variant = StatusKey | 'category' | 'count';

type Props = {
  label: string;
  variant?: Variant;
  dot?: boolean;
};

export function Badge({ label, variant = 'active', dot = false }: Props) {
  const { bg, fg } = resolve(variant);
  const pill = dot || variant === 'category' || variant === 'count';

  return (
    <View
      style={[
        styles.base,
        { backgroundColor: bg, borderRadius: pill ? radius.pill : radius.xs },
        pill ? styles.pillPad : styles.tagPad,
      ]}
    >
      {dot ? <View style={[styles.dot, { backgroundColor: fg }]} /> : null}
      <Text style={[text.caption, styles.label, { color: fg }]}>{label}</Text>
    </View>
  );
}

function resolve(variant: Variant): { bg: string; fg: string } {
  if (variant === 'category' || variant === 'count') {
    return { bg: colors.primarySurface, fg: colors.primary };
  }
  return statusColors[variant];
}

const styles = StyleSheet.create({
  base: {
    flexDirection: 'row',
    alignItems: 'center',
    alignSelf: 'flex-start',
    gap: spacing.sm,
  },
  tagPad: { paddingHorizontal: spacing.sm, paddingVertical: 3 },
  pillPad: { paddingHorizontal: spacing.m, paddingVertical: 5 },
  dot: { width: 6, height: 6, borderRadius: 3 },
  label: { fontSize: 11 },
});
