/**
 * ChannelIcon — Facebook, Instagram, TikTok, WhatsApp, Google Business.
 *
 * Couleurs OFFICIELLES des marques (channelColors), jamais les nôtres.
 *  • variant `solid`   : tuile pleine couleur de marque, glyphe blanc (compte connecté).
 *  • variant `outline` : tuile blanche, bordure + glyphe couleur de marque (non connecté).
 *
 * Facebook et Instagram : tracés OFFICIELS (channelPaths, Simple Icons) dessinés
 * avec react-native-svg, comme sur l'app web (BUG-011, MOD-077). Facebook = logo
 * rond bleu sans tuile ; Instagram = glyphe blanc sur tuile en dégradé.
 * TikTok, WhatsApp, Google : glyphes composés en attendant leurs tracés.
 *
 * ⚠️ Google Business : la maquette ne contient que le logo Google Sign-in
 * (multicolore), pas de mark « Business » dédié. Rendu ici en 'G' Google-blue,
 * à confirmer.
 */
import { StyleSheet, Text, View, type ViewStyle } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import Svg, { Circle, Path } from 'react-native-svg';
import { channelColors, channelPaths, colors } from '../theme';

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

  // Facebook : le logo rond officiel EST l'icône (pas de tuile). Gris quand non connecté.
  if (channel === 'facebook') {
    return (
      <Svg width={size} height={size} viewBox="0 0 24 24" accessibilityLabel="Facebook">
        <Circle cx={12} cy={12} r={11.4} fill="#FFFFFF" />
        <Path d={channelPaths.facebook} fill={variant === 'solid' ? brand : colors.faint} />
      </Svg>
    );
  }

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
      return (
        <Svg width={s * 0.58} height={s * 0.58} viewBox="0 0 24 24" accessibilityLabel="Instagram">
          <Path d={channelPaths.instagram} fill={color} />
        </Svg>
      );
  }
}

const styles = StyleSheet.create({
  sansBold: { fontWeight: '700' },
});
