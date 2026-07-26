/**
 * Screen — wrapper de tous les écrans.
 *
 * Gère l'encoche iOS (SafeAreaView cœur RN) et la barre de statut Android
 * (StatusBar.currentHeight), sans dépendance supplémentaire.
 *
 * NB : le SafeAreaView du cœur de React Native est marqué déprécié en RN 0.86
 * (au profit de react-native-safe-area-context). On l'emploie volontairement
 * pour respecter la contrainte « aucune dépendance hors expo-linear-gradient et
 * expo-font ». Migration possible plus tard si Charly lève la contrainte.
 */
import type { ReactNode } from 'react';
import {
  Platform,
  SafeAreaView,
  ScrollView,
  StatusBar,
  StyleSheet,
  View,
  type ViewStyle,
} from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { colors, gradients, spacing } from '../theme';

type Props = {
  children: ReactNode;
  /** `white` (écrans app) ou `gradient` (auth / onboarding). */
  background?: 'white' | 'gradient';
  /** Contenu défilant. */
  scroll?: boolean;
  /** Padding horizontal d'écran (20). */
  padded?: boolean;
  style?: ViewStyle;
};

const androidTop: ViewStyle | null =
  Platform.OS === 'android' ? { paddingTop: StatusBar.currentHeight ?? 0 } : null;

export function Screen({
  children,
  background = 'white',
  scroll = false,
  padded = true,
  style,
}: Props) {
  const pad: ViewStyle | undefined = padded
    ? { paddingHorizontal: spacing.screen }
    : undefined;

  const body = scroll ? (
    <ScrollView
      contentContainerStyle={[styles.scrollContent, pad]}
      showsVerticalScrollIndicator={false}
    >
      {children}
    </ScrollView>
  ) : (
    <View style={[styles.flex, pad]}>{children}</View>
  );

  if (background === 'gradient') {
    return (
      <View style={styles.flex}>
        <LinearGradient
          colors={[...gradients.authBackground]}
          locations={[0, 0.48, 1]}
          start={{ x: 0, y: 0 }}
          end={{ x: 0.26, y: 1 }}
          style={StyleSheet.absoluteFill}
        />
        <SafeAreaView style={[styles.flex, androidTop, style]}>{body}</SafeAreaView>
      </View>
    );
  }

  return (
    <SafeAreaView style={[styles.flex, styles.white, androidTop, style]}>
      {body}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  flex: { flex: 1 },
  white: { backgroundColor: colors.surface },
  scrollContent: { flexGrow: 1 },
});
