/** Écran natif quand la page ne charge pas : jamais d'erreur de navigateur à l'écran. */
import { Pressable, StyleSheet, Text, View } from 'react-native';
import Svg, { Path } from 'react-native-svg';

import { colors, fonts, radius } from '../theme';

export function Offline({ onRetry }: { onRetry: () => void }) {
  return (
    <View style={styles.root}>
      <Svg width={44} height={44} viewBox="0 0 24 24" fill="none" stroke={colors.primary} strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round">
        <Path d="M2 8.5a15 15 0 0 1 20 0M5.5 12.5a10 10 0 0 1 13 0M9 16.5a5 5 0 0 1 6 0M12 20h.01M3 3l18 18" />
      </Svg>
      <Text style={styles.title}>Pas de connexion</Text>
      <Text style={styles.text}>Vérifiez votre réseau, puis réessayez. Vos promos vous attendent.</Text>
      <Pressable accessibilityRole="button" onPress={onRetry} style={styles.button}>
        <Text style={styles.buttonText}>Réessayer</Text>
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  root: { ...StyleSheet.absoluteFill, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', padding: 32, gap: 12 },
  title: { fontFamily: fonts.bold, fontSize: 20, color: colors.ink },
  text: { fontFamily: fonts.regular, fontSize: 15, lineHeight: 22, color: colors.muted, textAlign: 'center' },
  button: { marginTop: 12, height: 48, paddingHorizontal: 28, borderRadius: radius.lg, backgroundColor: colors.primary, alignItems: 'center', justifyContent: 'center' },
  buttonText: { fontFamily: fonts.bold, fontSize: 15, color: '#fff' },
});
