/** Premier lancement : le choix de l'espace. Le client entre sans compte. */
import { Image, Pressable, StyleSheet, Text, View } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { colors, fonts, gradients, radius } from '../theme';
import type { Space } from './rules';

export function Welcome({ onChoose }: { onChoose: (space: Space) => void }) {
  const insets = useSafeAreaInsets();
  return (
    <LinearGradient
      colors={gradients.brand}
      start={{ x: 0, y: 0 }}
      end={{ x: 1, y: 0 }}
      style={[styles.root, { paddingTop: insets.top + 24, paddingBottom: insets.bottom + 24 }]}
    >
      <View style={styles.head}>
        <Image source={require('../../assets/splash-icon.png')} style={styles.logo} />
        <Text style={styles.title}>Les bonnes affaires de vos commerces, près de chez vous.</Text>
      </View>
      <View style={styles.actions}>
        <Pressable accessibilityRole="button" onPress={() => onChoose('client')} style={styles.primary}>
          <Text style={styles.primaryText}>Découvrir les promos</Text>
        </Pressable>
        <Pressable accessibilityRole="button" onPress={() => onChoose('magasin')} style={styles.secondary}>
          <Text style={styles.secondaryText}>Je suis commerçant</Text>
        </Pressable>
        <Text style={styles.note}>Pas besoin de compte pour voir les promos.</Text>
      </View>
    </LinearGradient>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, paddingHorizontal: 26, justifyContent: 'space-between' },
  head: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: 24 },
  logo: { width: 120, height: 120, resizeMode: 'contain' },
  title: { fontFamily: fonts.bold, fontSize: 26, lineHeight: 33, color: '#fff', textAlign: 'center' },
  actions: { gap: 12 },
  primary: { height: 54, borderRadius: radius.lg, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center' },
  primaryText: { fontFamily: fonts.bold, fontSize: 16, color: colors.primary },
  secondary: { height: 54, borderRadius: radius.lg, borderWidth: 1.5, borderColor: 'rgba(255,255,255,0.7)', alignItems: 'center', justifyContent: 'center' },
  secondaryText: { fontFamily: fonts.semibold, fontSize: 16, color: '#fff' },
  note: { fontFamily: fonts.regular, fontSize: 13, color: 'rgba(255,255,255,0.85)', textAlign: 'center', marginTop: 4 },
});
