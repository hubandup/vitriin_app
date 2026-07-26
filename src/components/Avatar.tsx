/**
 * Avatar — initiale ou image, tailles S / M / L (36 / 46 / 58, d'après la
 * maquette). Rond. Fond magenta par défaut (surchargeable via `color`).
 */
import { Image, StyleSheet, Text, View } from 'react-native';
import { colors, fonts } from '../theme';

type Size = 'S' | 'M' | 'L';

type Props = {
  initial?: string;
  uri?: string;
  size?: Size;
  color?: string;
};

const DIM: Record<Size, number> = { S: 36, M: 46, L: 58 };
const FONT: Record<Size, number> = { S: 15, M: 18, L: 23 };

export function Avatar({ initial, uri, size = 'M', color = colors.primary }: Props) {
  const dim = DIM[size];
  const shape = { width: dim, height: dim, borderRadius: dim / 2 };

  if (uri) {
    return <Image source={{ uri }} style={[shape, styles.image]} />;
  }

  return (
    <View style={[shape, styles.fallback, { backgroundColor: color }]}>
      <Text style={[styles.initial, { fontSize: FONT[size] }]}>{initial ?? '?'}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  image: { backgroundColor: colors.neutralSurface },
  fallback: { alignItems: 'center', justifyContent: 'center' },
  initial: { fontFamily: fonts.bold, color: colors.onPrimary },
});
