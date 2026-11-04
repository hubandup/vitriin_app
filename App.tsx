/** Vitriin mobile : une seule application, espaces client et magasin. */
import { useFonts, DMSans_400Regular, DMSans_500Medium, DMSans_600SemiBold, DMSans_700Bold } from '@expo-google-fonts/dm-sans';
import { RacingSansOne_400Regular } from '@expo-google-fonts/racing-sans-one';
import * as SplashScreen from 'expo-splash-screen';
import { SafeAreaProvider } from 'react-native-safe-area-context';

import { Shell } from './src/shell/Shell';

SplashScreen.preventAutoHideAsync().catch(() => {});

export default function App() {
  const [fontsReady] = useFonts({
    DMSans_400Regular,
    DMSans_500Medium,
    DMSans_600SemiBold,
    DMSans_700Bold,
    RacingSansOne_400Regular,
  });
  if (!fontsReady) return null;
  return (
    <SafeAreaProvider>
      <Shell />
    </SafeAreaProvider>
  );
}
