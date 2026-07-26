/**
 * Input — champ texte / téléphone.
 *
 *  • label optionnel au-dessus, placeholder, état focus (bordure magenta).
 *  • `type="tel"` ouvre le clavier numérique (keyboardType="phone-pad").
 *  • `prefix` : contenu à gauche dans le cadre (ex. indicatif « 🇫🇷 +33 »).
 *  • error : la maquette (statique) ne montre pas d'état erreur — DÉRIVÉ, bordure
 *    + message en `danger` (placeholder à valider, cf. colors.ts).
 */
import { useState, type ReactNode } from 'react';
import {
  StyleSheet,
  Text,
  TextInput,
  View,
  type KeyboardTypeOptions,
  type ViewStyle,
} from 'react-native';
import { colors, radius, spacing, text } from '../theme';

type Props = {
  value: string;
  onChangeText: (v: string) => void;
  label?: string;
  placeholder?: string;
  type?: 'text' | 'tel';
  error?: string;
  prefix?: ReactNode;
};

export function Input({
  value,
  onChangeText,
  label,
  placeholder,
  type = 'text',
  error,
  prefix,
}: Props) {
  const [focused, setFocused] = useState(false);

  const keyboardType: KeyboardTypeOptions = type === 'tel' ? 'phone-pad' : 'default';

  const frameStyle: ViewStyle = {
    borderColor: error ? colors.danger : focused ? colors.primary : colors.line,
    backgroundColor: error || focused ? colors.primarySurface : colors.surface,
  };

  return (
    <View>
      {label ? <Text style={[text.label, styles.label]}>{label}</Text> : null}
      <View style={[styles.frame, frameStyle]}>
        {prefix ? <View style={styles.prefix}>{prefix}</View> : null}
        <TextInput
          value={value}
          onChangeText={onChangeText}
          placeholder={placeholder}
          placeholderTextColor={colors.faint}
          keyboardType={keyboardType}
          onFocus={() => setFocused(true)}
          onBlur={() => setFocused(false)}
          style={[text.bodyStrong, styles.input]}
        />
      </View>
      {error ? <Text style={[text.caption, styles.error]}>{error}</Text> : null}
    </View>
  );
}

const styles = StyleSheet.create({
  label: { color: colors.ink, marginBottom: spacing.s },
  frame: {
    flexDirection: 'row',
    alignItems: 'center',
    borderWidth: 1.5,
    borderRadius: radius.md,
    paddingHorizontal: spacing.ml,
  },
  prefix: { marginRight: spacing.s },
  input: {
    flex: 1,
    color: colors.ink,
    paddingVertical: 14,
  },
  error: { color: colors.danger, marginTop: spacing.sm },
});
