/**
 * Dock — barre de navigation flottante du nouveau design (MOD-077).
 *
 * Même dessin que l'espace magasin web (/magasin) et l'app client (/v) :
 * 68 px de haut, rayon 34, posée à 16 px des bords et 18 px du bas (+ zone sûre),
 * onglet actif = icône et libellé encre + point magenta de 5 px.
 * `onCreate` ajoute le « + » central en dégradé (espace magasin) ; sans lui, 4 onglets (app client).
 */
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import Svg, { Path } from 'react-native-svg';
import { colors, gradients, radius, shadows, text } from '../theme';

export type DockTab = { key: string; label: string; icon: string };

/** Tracés des icônes du dock (viewBox 24×24, trait 2). */
export const dockIcons = {
  home: 'M3 10.5 12 3l9 7.5V20a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z',
  promos: 'M20.6 13.4 13.4 20.6a2 2 0 0 1-2.8 0L3 13V3h10l7.6 7.6a2 2 0 0 1 0 2.8zM7.5 6a1.5 1.5 0 1 0 0 3 1.5 1.5 0 0 0 0-3',
  stats: 'M4 20V10M10 20V4M16 20v-7M22 20H2',
  store: 'M12 4a4 4 0 1 0 0 8 4 4 0 0 0 0-8M4 21a8 8 0 0 1 16 0',
  search: 'M11 4a7 7 0 1 0 0 14 7 7 0 0 0 0-14m9 16-3.5-3.5',
  bookmark: 'M6 4h12v17l-6-4-6 4V4Z',
} as const;

type Props = {
  tabs: DockTab[];
  active: string;
  onChange: (key: string) => void;
  onCreate?: () => void;
  /** Zone sûre du bas (barre d'accueil iOS), à fournir par l'écran. */
  bottomInset?: number;
};

export function Dock({ tabs, active, onChange, onCreate, bottomInset = 0 }: Props) {
  const half = Math.ceil(tabs.length / 2);
  const tab = (t: DockTab) => {
    const on = t.key === active;
    const c = on ? colors.ink : colors.muted;
    return (
      <Pressable key={t.key} onPress={() => onChange(t.key)} style={styles.tab} accessibilityRole="tab" accessibilityState={{ selected: on }} accessibilityLabel={t.label}>
        <Svg width={22} height={22} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth={on ? 2.2 : 2} strokeLinecap="round" strokeLinejoin="round">
          <Path d={t.icon} />
        </Svg>
        <Text style={[text.nav, { color: c }, on && styles.labelOn]}>{t.label}</Text>
        <View style={[styles.dot, on && styles.dotOn]} />
      </Pressable>
    );
  };
  return (
    <View style={[styles.dock, shadows.dock, { bottom: 18 + bottomInset }]} accessibilityRole="tablist">
      {tabs.slice(0, onCreate ? half : tabs.length).map(tab)}
      {onCreate ? (
        <Pressable onPress={onCreate} accessibilityRole="button" accessibilityLabel="Nouvelle publication" style={shadows.fab}>
          <LinearGradient colors={[...gradients.brand]} start={{ x: 0, y: 0 }} end={{ x: 1, y: 1 }} style={styles.fab}>
            <Svg width={26} height={26} viewBox="0 0 24 24" fill="none" stroke="#FFFFFF" strokeWidth={2.6} strokeLinecap="round">
              <Path d="M12 5v14M5 12h14" />
            </Svg>
          </LinearGradient>
        </Pressable>
      ) : null}
      {onCreate ? tabs.slice(half).map(tab) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  dock: {
    position: 'absolute',
    left: 16,
    right: 16,
    height: 68,
    borderRadius: radius.dock,
    backgroundColor: colors.surface,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-around',
    paddingHorizontal: 8,
  },
  tab: { alignItems: 'center', gap: 3, minWidth: 52 },
  labelOn: { fontFamily: 'DMSans_700Bold' },
  dot: { width: 5, height: 5, borderRadius: 3 },
  dotOn: { backgroundColor: colors.primary },
  fab: { width: 56, height: 56, borderRadius: 28, alignItems: 'center', justifyContent: 'center' },
});
