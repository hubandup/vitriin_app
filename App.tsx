/**
 * Vitriin — page de démonstration du design system.
 * Tous les composants, toutes les variantes, sur un écran scrollable.
 * À voir sur téléphone via Expo Go : `npx expo start` puis scan du QR code.
 */
import { useState, type ReactNode } from 'react';
import { StyleSheet, Text, View } from 'react-native';
import { StatusBar } from 'expo-status-bar';
import { LinearGradient } from 'expo-linear-gradient';
import {
  useFonts,
  DMSans_400Regular,
  DMSans_500Medium,
  DMSans_600SemiBold,
  DMSans_700Bold,
} from '@expo-google-fonts/dm-sans';
import { RacingSansOne_400Regular } from '@expo-google-fonts/racing-sans-one';

import {
  Screen,
  Button,
  Input,
  Card,
  Badge,
  Avatar,
  ChannelIcon,
} from './src/components';
import { colors, fonts, gradients, radius, shadows, spacing, text } from './src/theme';

export default function App() {
  const [fontsLoaded] = useFonts({
    DMSans_400Regular,
    DMSans_500Medium,
    DMSans_600SemiBold,
    DMSans_700Bold,
    RacingSansOne_400Regular,
  });

  const [phone, setPhone] = useState('6 12 34 56 78');
  const [name, setName] = useState('');
  const [loading, setLoading] = useState(false);

  if (!fontsLoaded) return null;

  return (
    <Screen scroll>
      <StatusBar style="dark" />

      {/* En-tête / logo */}
      <View style={styles.header}>
        <LinearGradient
          colors={[...gradients.brand]}
          start={{ x: 0, y: 0 }}
          end={{ x: 1, y: 1 }}
          style={[styles.logo, shadows.glow]}
        >
          <Text style={styles.logoLetter}>V</Text>
        </LinearGradient>
        <Text style={styles.wordmark}>Vitriin</Text>
        <Text style={[text.small, styles.muted]}>Design System · mobile</Text>
      </View>

      {/* Couleurs */}
      <Section title="Couleurs" eyebrow="Marque">
        <View style={styles.swatchRow}>
          <Swatch color={colors.primary} name="primary" hex="#e5087e" onDark />
          <Swatch color={colors.violet} name="violet" hex="#951b81" onDark />
          <Swatch color={colors.teal} name="teal" hex="#0c9875" onDark />
          <Swatch color={colors.cream} name="cream" hex="#f5ecd3" />
        </View>
        <LinearGradient
          colors={[...gradients.brand]}
          start={{ x: 0, y: 0 }}
          end={{ x: 1, y: 0 }}
          style={styles.gradientBar}
        >
          <Text style={styles.gradientLabel}>dégradé signature — magenta → violet</Text>
        </LinearGradient>
      </Section>

      {/* Typographie */}
      <Section title="Typographie" eyebrow="DM Sans + Racing Sans One">
        <Text style={text.titleXL}>Titre d'écran</Text>
        <Text style={text.h1}>Titre de page</Text>
        <Text style={text.h2}>En-tête de section</Text>
        <Text style={text.body}>Corps de texte — DM Sans 15/400, le lisible du quotidien.</Text>
        <Text style={[text.caption, styles.muted]}>Métadonnée · 12/500</Text>
        <Text style={[text.eyebrow, styles.muted]}>Eyebrow</Text>
        <View style={styles.promoRow}>
          <Text style={[text.promo, styles.promoInk]}>-30%</Text>
          <Text style={[text.promo, styles.promoInk]}>29€</Text>
          <Text style={[text.caption, styles.muted]}>Racing Sans One — chiffres promo</Text>
        </View>
      </Section>

      {/* Boutons */}
      <Section title="Boutons" eyebrow="4 variantes · états">
        <View style={styles.stack}>
          <Button label="Publier maintenant" onPress={() => {}} />
          <Button
            label={loading ? 'Publication…' : 'Tester le loading'}
            loading={loading}
            onPress={() => {
              setLoading(true);
              setTimeout(() => setLoading(false), 1600);
            }}
          />
          <Button label="Indisponible" disabled />
          <Button label="Passer en mode commerçant" variant="secondary" onPress={() => {}} />
          <Button label="Plus tard" variant="ghost" onPress={() => {}} />
          <Button label="Se déconnecter" variant="danger" onPress={() => {}} />
          <View style={styles.inlineRow}>
            <Button label="Petit" size="sm" fullWidth={false} onPress={() => {}} />
            <Button label="Petit ghost" size="sm" variant="ghost" fullWidth={false} onPress={() => {}} />
          </View>
        </View>
      </Section>

      {/* Champs */}
      <Section title="Champs" eyebrow="text · tel · erreur">
        <View style={styles.stack}>
          <Input
            label="Numéro de téléphone"
            type="tel"
            value={phone}
            onChangeText={setPhone}
            prefix={<Text style={text.bodyStrong}>🇫🇷 +33</Text>}
          />
          <Input
            label="Nom du commerce"
            placeholder="Ex : Boulangerie du Marché"
            value={name}
            onChangeText={setName}
          />
          <Input
            label="Code d'enseigne"
            value="ENS-000"
            onChangeText={() => {}}
            error="Ce code n'existe pas. Vérifie l'e-mail reçu."
          />
        </View>
      </Section>

      {/* Cartes */}
      <Section title="Cartes" eyebrow="standard · compact">
        <View style={styles.stack}>
          <Card>
            <Text style={text.h2}>Carte standard</Text>
            <Text style={[text.small, styles.muted, styles.mt6]}>
              Surface blanche, bordure discrète, ombre douce. Le socle des écrans.
            </Text>
          </Card>
          <Card variant="compact" onPress={() => {}}>
            <View style={styles.cardRow}>
              <Avatar initial="B" size="M" />
              <View style={styles.flex1}>
                <Text style={text.bodyStrong}>Carte compact</Text>
                <Text style={[text.caption, styles.muted]}>Pressable · ligne de liste</Text>
              </View>
              <Badge label="Active" variant="active" />
            </View>
          </Card>
        </View>
      </Section>

      {/* Badges */}
      <Section title="Badges" eyebrow="statuts · étiquettes">
        <View style={styles.wrap}>
          <Badge label="Active" variant="active" />
          <Badge label="Programmée" variant="scheduled" />
          <Badge label="Brouillon" variant="draft" />
          <Badge label="Expirée" variant="expired" />
          <Badge label="Boulangerie" variant="category" />
          <Badge label="12 actives" variant="count" />
          <Badge label="Actif" variant="active" dot />
        </View>
      </Section>

      {/* Avatars */}
      <Section title="Avatars" eyebrow="S · M · L · image">
        <View style={styles.avatarRow}>
          <Avatar initial="B" size="S" />
          <Avatar initial="L" size="M" color="#b8956e" />
          <Avatar initial="C" size="L" color={colors.primary} />
          <Avatar
            size="L"
            uri="https://images.unsplash.com/photo-1509440159596-0249088772ff?w=200"
          />
        </View>
      </Section>

      {/* Icônes de canaux */}
      <Section title="Canaux" eyebrow="couleurs officielles · connecté / non connecté">
        <Text style={[text.caption, styles.muted, styles.mb10]}>Connecté (solid)</Text>
        <View style={styles.channelRow}>
          <ChannelIcon channel="facebook" />
          <ChannelIcon channel="instagram" />
          <ChannelIcon channel="tiktok" />
          <ChannelIcon channel="whatsapp" />
          <ChannelIcon channel="google" />
        </View>
        <Text style={[text.caption, styles.muted, styles.mb10, styles.mt16]}>Non connecté (outline)</Text>
        <View style={styles.channelRow}>
          <ChannelIcon channel="facebook" variant="outline" />
          <ChannelIcon channel="instagram" variant="outline" />
          <ChannelIcon channel="tiktok" variant="outline" />
          <ChannelIcon channel="whatsapp" variant="outline" />
          <ChannelIcon channel="google" variant="outline" />
        </View>
      </Section>

      <Text style={[text.caption, styles.muted, styles.footer]}>
        Vitriin · fin de la démonstration
      </Text>
    </Screen>
  );
}

function Section({
  title,
  eyebrow,
  children,
}: {
  title: string;
  eyebrow: string;
  children: ReactNode;
}) {
  return (
    <View style={styles.section}>
      <Text style={[text.eyebrow, styles.sectionEyebrow]}>{eyebrow}</Text>
      <Text style={[text.h1, styles.sectionTitle]}>{title}</Text>
      {children}
    </View>
  );
}

function Swatch({
  color,
  name,
  hex,
  onDark = false,
}: {
  color: string;
  name: string;
  hex: string;
  onDark?: boolean;
}) {
  const fg = onDark ? '#FFFFFF' : colors.ink;
  return (
    <View style={[styles.swatch, { backgroundColor: color }]}>
      <Text style={[styles.swatchName, { color: fg }]}>{name}</Text>
      <Text style={[styles.swatchHex, { color: fg }]}>{hex}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  header: { alignItems: 'center', paddingTop: spacing.xxl, paddingBottom: spacing.s },
  logo: {
    width: 62,
    height: 62,
    borderRadius: 19,
    alignItems: 'center',
    justifyContent: 'center',
  },
  logoLetter: { fontFamily: fonts.promo, color: '#FFFFFF', fontSize: 34, lineHeight: 40 },
  wordmark: { fontFamily: fonts.promo, fontSize: 28, color: colors.ink, marginTop: spacing.m },
  muted: { color: colors.muted },

  section: { paddingTop: spacing.x5 },
  sectionEyebrow: { color: colors.primary },
  sectionTitle: { marginTop: spacing.xs, marginBottom: spacing.l },

  swatchRow: { flexDirection: 'row', gap: spacing.s, marginBottom: spacing.m },
  swatch: {
    flex: 1,
    height: 74,
    borderRadius: radius.md,
    padding: spacing.s,
    justifyContent: 'flex-end',
  },
  swatchName: { fontFamily: fonts.bold, fontSize: 12 },
  swatchHex: { fontFamily: fonts.regular, fontSize: 10, opacity: 0.85 },
  gradientBar: {
    height: 44,
    borderRadius: radius.md,
    alignItems: 'center',
    justifyContent: 'center',
  },
  gradientLabel: { fontFamily: fonts.semibold, color: '#FFFFFF', fontSize: 12 },

  promoRow: { flexDirection: 'row', alignItems: 'baseline', gap: spacing.m, marginTop: spacing.m },
  promoInk: { color: colors.ink },

  stack: { gap: spacing.m },
  inlineRow: { flexDirection: 'row', gap: spacing.m },

  cardRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.m },
  flex1: { flex: 1 },
  mt6: { marginTop: spacing.sm },
  mt16: { marginTop: spacing.l },
  mb10: { marginBottom: spacing.ms },

  wrap: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.s },
  avatarRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.l },
  channelRow: { flexDirection: 'row', gap: spacing.m, alignItems: 'center' },

  footer: { textAlign: 'center', paddingVertical: spacing.x5 },
});
