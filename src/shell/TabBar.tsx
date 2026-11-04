/** Barre d'onglets native. Mêmes hauteurs que le menu web, pour ne rien changer à la mise en page des écrans. */
import type { ReactNode } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import Svg, { Circle, Path } from 'react-native-svg';

import { colors, fonts } from '../theme';
import type { Space } from './rules';

export const TAB_HEIGHT: Record<Space, number> = { client: 76, magasin: 64 };

const INACTIVE = '#a8a29b';

function Icon({ tab, space, color }: { tab: string; space: Space; color: string }) {
  const line = { fill: 'none', stroke: color, strokeWidth: 1.9, strokeLinecap: 'round', strokeLinejoin: 'round' } as const;
  const shapes: Record<string, ReactNode> = space === 'client'
    ? {
        feed: <><Circle cx={11} cy={11} r={7} {...line} /><Path d="m20 20-3.4-3.4" {...line} /></>,
        promos: <Path d="M6 4h12v17l-6-4-6 4V4Z" {...line} />,
        follows: <><Path d="M3 9l1.5-5h15L21 9" {...line} /><Path d="M3 9a3 3 0 0 0 6 0 3 3 0 0 0 6 0 3 3 0 0 0 6 0" {...line} /><Path d="M5 11.5V20h14v-8.5" {...line} /><Path d="M10 20v-5h4v5" {...line} /></>,
        profile: <><Circle cx={12} cy={8} r={4} {...line} /><Path d="M4 21v-1a6 6 0 0 1 6-6h4a6 6 0 0 1 6 6v1" {...line} /></>,
      }
    : {
        home: <><Path d="M3 10.5 12 4l9 6.5" {...line} /><Path d="M5 9.4V20h14V9.4" {...line} /></>,
        promos: <><Path d="M20.6 13.4 11 3.8a2 2 0 0 0-1.4-.6H5a2 2 0 0 0-2 2v4.6c0 .5.2 1 .6 1.4l9.6 9.6a2 2 0 0 0 2.8 0l4.6-4.6a2 2 0 0 0 0-2.8Z" {...line} /><Circle cx={7.6} cy={7.6} r={1.3} fill={color} /></>,
        stats: <Path d="M5 20V10M12 20V4M19 20v-7" {...line} />,
        settings: <><Path d="M4 8h10M18 8h2M4 16h2M10 16h10" {...line} /><Circle cx={16} cy={8} r={2.3} {...line} /><Circle cx={8} cy={16} r={2.3} {...line} /></>,
      };
  return <Svg width={24} height={24} viewBox="0 0 24 24">{shapes[tab]}</Svg>;
}

const TABS: Record<Space, { id: string; label: string }[]> = {
  client: [
    { id: 'feed', label: 'Découvrir' },
    { id: 'promos', label: 'Mes promos' },
    { id: 'follows', label: 'Commerces' },
    { id: 'profile', label: 'Profil' },
  ],
  magasin: [
    { id: 'home', label: 'Accueil' },
    { id: 'promos', label: 'Promos' },
    { id: 'stats', label: 'Stats' },
    { id: 'settings', label: 'Réglages' },
  ],
};

type Props = {
  space: Space;
  active: string | null;
  badge: number;
  bottomInset: number;
  onPress: (tab: string) => void;
};

export function TabBar({ space, active, badge, bottomInset, onPress }: Props) {
  return (
    <View
      accessibilityRole="tablist"
      style={[styles.bar, { height: TAB_HEIGHT[space] + bottomInset, paddingBottom: bottomInset }]}
    >
      {TABS[space].map((tab) => {
        const on = tab.id === active;
        const color = on ? colors.primary : INACTIVE;
        return (
          <Pressable
            key={tab.id}
            accessibilityRole="tab"
            accessibilityLabel={tab.label}
            accessibilityState={{ selected: on }}
            onPress={() => onPress(tab.id)}
            style={styles.tab}
          >
            <View>
              <Icon tab={tab.id} space={space} color={color} />
              {space === 'magasin' && tab.id === 'promos' && badge > 0 ? (
                <View style={styles.badge}><Text style={styles.badgeText}>{badge}</Text></View>
              ) : null}
            </View>
            <Text style={[styles.label, { color }]}>{tab.label}</Text>
          </Pressable>
        );
      })}
    </View>
  );
}

const styles = StyleSheet.create({
  bar: {
    position: 'absolute',
    left: 0,
    right: 0,
    bottom: 0,
    flexDirection: 'row',
    backgroundColor: 'rgba(255,255,255,0.97)',
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: colors.line,
  },
  tab: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: 3 },
  label: { fontFamily: fonts.medium, fontSize: 11.5 },
  badge: {
    position: 'absolute',
    top: -5,
    right: -11,
    minWidth: 17,
    height: 17,
    paddingHorizontal: 4,
    borderRadius: 9,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.primary,
  },
  badgeText: { fontFamily: fonts.bold, fontSize: 10, color: '#fff' },
});
