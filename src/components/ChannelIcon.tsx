/**
 * ChannelIcon — Facebook, Instagram, TikTok, WhatsApp, Google Business.
 *
 * Couleurs OFFICIELLES des marques (channelColors), jamais les nôtres.
 *  • variant `solid`   : tuile pleine couleur de marque, glyphe blanc (compte connecté).
 *  • variant `outline` : tuile blanche, bordure + glyphe couleur de marque (non connecté).
 *
 * Note : pas de react-native-svg (dépendance non autorisée). Les glyphes sont
 * composés en Views/Text — reconnaissables, mais approximatifs. Pour des logos
 * officiels au pixel près, ajouter react-native-svg. Les COULEURS, elles, sont
 * exactes.
 *
 * ⚠️ Google Business : la maquette ne contient que le logo Google Sign-in
 * (multicolore), pas de mark « Business » dédié. Rendu ici en 'G' Google-blue,
 * à confirmer.
 */
import { Platform, StyleSheet, Text, View, type ViewStyle } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { channelColors } from '../theme';

type Channel = 'facebook' | 'instagram' | 'tiktok' | 'whatsapp' | 'google';

type Props = {
  channel: Channel;
  size?: number;
  variant?: 'solid' | 'outline';
};

const BRAND: Record<Channel, string> = {
  facebook: channelColors.facebook,
  instagram: channelColors.instagramSolid,
  tiktok: channelColors.tiktok,
  whatsapp: channelColors.whatsapp,
  google: channelColors.google,
};

export function ChannelIcon({ channel, size = 46, variant = 'solid' }: Props) {
  const brand = BRAND[channel];
  const glyphColor = variant === 'solid' ? '#FFFFFF' : brand;
  const tile: ViewStyle = {
    width: size,
    height: size,
    borderRadius: size * 0.28,
    alignItems: 'center',
    justifyContent: 'center',
  };

  const content = <Glyph channel={channel} color={glyphColor} size={size} />;

  // Instagram connecté = dégradé officiel.
  if (channel === 'instagram' && variant === 'solid') {
    return (
      <LinearGradient
        colors={[...channelColors.instagram]}
        start={{ x: 0, y: 1 }}
        end={{ x: 1, y: 0 }}
        style={tile}
      >
        {content}
      </LinearGradient>
    );
  }

  const surface: ViewStyle =
    variant === 'solid'
      ? { backgroundColor: brand }
      : { backgroundColor: '#FFFFFF', borderWidth: 2, borderColor: brand };

  return <View style={[tile, surface]}>{content}</View>;
}

/** Glyphes composés (pas de SVG). */
function Glyph({ channel, color, size }: { channel: Channel; color: string; size: number }) {
  const s = size;
  switch (channel) {
    case 'facebook':
      return <Text style={[styles.serif, { color, fontSize: s * 0.6 }]}>f</Text>;
    case 'tiktok':
      return <Text style={{ color, fontSize: s * 0.5 }}>♪</Text>;
    case 'google':
      return <Text style={[styles.sansBold, { color, fontSize: s * 0.5 }]}>G</Text>;
    case 'whatsapp':
      // Bulle de discussion : carré arrondi blanc dont un coin est équarri (queue).
      return (
        <View
          style={{
            width: s * 0.5,
            height: s * 0.5,
            borderRadius: s * 0.18,
            borderBottomLeftRadius: 0,
            borderWidth: Math.max(2, s * 0.07),
            borderColor: color,
          }}
        />
      );
    case 'instagram':
      // Objectif : carré arrondi + cercle + point en haut à droite.
      return (
        <View
          style={{
            width: s * 0.52,
            height: s * 0.52,
            borderRadius: s * 0.17,
            borderWidth: Math.max(2, s * 0.06),
            borderColor: color,
            alignItems: 'center',
            justifyContent: 'center',
          }}
        >
          <View
            style={{
              width: s * 0.24,
              height: s * 0.24,
              borderRadius: s * 0.12,
              borderWidth: Math.max(2, s * 0.06),
              borderColor: color,
            }}
          />
          <View
            style={{
              position: 'absolute',
              top: s * 0.03,
              right: s * 0.03,
              width: s * 0.06,
              height: s * 0.06,
              borderRadius: s * 0.03,
              backgroundColor: color,
            }}
          />
        </View>
      );
  }
}

const styles = StyleSheet.create({
  serif: {
    fontFamily: Platform.select({ ios: 'Georgia', android: 'serif', default: 'serif' }),
    fontWeight: '700',
  },
  sansBold: { fontWeight: '700' },
});
