// Small set of UI primitives shared by every screen.

import type { ReactNode } from 'react';
import {
  ActivityIndicator,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  type TextInputProps,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { colors, font, radius, spacing } from '../theme';

export function Screen(props: {
  title: string;
  subtitle?: string;
  progress?: string;
  children?: ReactNode;
  footer?: ReactNode;
}) {
  return (
    <SafeAreaView style={styles.safe} edges={['top', 'bottom']}>
      <KeyboardAvoidingView style={styles.flex} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
        <ScrollView contentContainerStyle={styles.content} keyboardShouldPersistTaps="handled">
          {props.progress ? <Text style={font.small}>{props.progress}</Text> : null}
          <Text style={[font.title, styles.title]} accessibilityRole="header">{props.title}</Text>
          {props.subtitle ? <Text style={[font.subtitle, styles.subtitle]}>{props.subtitle}</Text> : null}
          {props.children}
        </ScrollView>
        {props.footer ? <View style={styles.footer}>{props.footer}</View> : null}
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

export function Button(props: {
  label: string;
  onPress: () => void;
  disabled?: boolean;
  loading?: boolean;
  variant?: 'primary' | 'secondary' | 'ghost' | 'danger';
}) {
  const variant = props.variant ?? 'primary';
  const inactive = props.disabled || props.loading;
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityState={{ disabled: !!inactive, busy: !!props.loading }}
      onPress={props.onPress}
      disabled={inactive}
      style={({ pressed }) => [
        styles.button,
        styles[`button_${variant}`],
        inactive && styles.buttonDisabled,
        pressed && styles.buttonPressed,
      ]}
    >
      {props.loading ? (
        <ActivityIndicator color={variant === 'primary' ? colors.white : colors.navy} />
      ) : (
        <Text style={[styles.buttonLabel, styles[`buttonLabel_${variant}`]]}>{props.label}</Text>
      )}
    </Pressable>
  );
}

/** Selectable card used for single and multiple choices. */
export function Choice(props: {
  label: string;
  description?: string;
  selected: boolean;
  onPress: () => void;
  disabled?: boolean;
  leading?: ReactNode;
  badge?: string;
  multiple?: boolean;
}) {
  return (
    <Pressable
      accessibilityRole={props.multiple ? 'checkbox' : 'radio'}
      accessibilityState={{ checked: props.selected, disabled: !!props.disabled }}
      onPress={props.onPress}
      disabled={props.disabled}
      style={[styles.choice, props.selected && styles.choiceSelected, props.disabled && styles.choiceDisabled]}
    >
      {props.leading ? <View style={styles.choiceLeading}>{props.leading}</View> : null}
      <View style={styles.flex}>
        <Text style={[font.body, styles.choiceLabel]}>{props.label}</Text>
        {props.description ? <Text style={font.small}>{props.description}</Text> : null}
      </View>
      {props.badge ? <Text style={styles.badge}>{props.badge}</Text> : null}
    </Pressable>
  );
}

export function Checkbox(props: { label: string; checked: boolean; onToggle: () => void }) {
  return (
    <Pressable
      accessibilityRole="checkbox"
      accessibilityState={{ checked: props.checked }}
      onPress={props.onToggle}
      style={styles.checkboxRow}
    >
      <View style={[styles.checkbox, props.checked && styles.checkboxChecked]}>
        {props.checked ? <Text style={styles.checkmark}>✓</Text> : null}
      </View>
      <Text style={[font.body, styles.flex]}>{props.label}</Text>
    </Pressable>
  );
}

export function Field(props: TextInputProps & { label?: string; hint?: string }) {
  const { label, hint, style, ...input } = props;
  return (
    <View style={styles.field}>
      {label ? <Text style={font.label}>{label}</Text> : null}
      <TextInput placeholderTextColor={colors.textMuted} style={[styles.input, style]} {...input} />
      {hint ? <Text style={font.small}>{hint}</Text> : null}
    </View>
  );
}

export function ErrorText({ message }: { message: string | null }) {
  if (!message) return null;
  return <Text accessibilityRole="alert" style={styles.error}>{message}</Text>;
}

export function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <View style={styles.section}>
      <Text style={font.label}>{title}</Text>
      {children}
    </View>
  );
}

/** Compact selectable pill (filters, day and time choices). */
export function Chip(props: { label: string; selected: boolean; onPress: () => void; leading?: ReactNode; disabled?: boolean }) {
  return (
    <Pressable
      accessibilityRole="checkbox"
      accessibilityState={{ checked: props.selected, disabled: !!props.disabled }}
      onPress={props.onPress}
      disabled={props.disabled}
      style={[styles.chip, props.selected && styles.chipSelected, props.disabled && styles.choiceDisabled]}
    >
      {props.leading}
      <Text style={[styles.chipLabel, props.selected && styles.chipLabelSelected]}>{props.label}</Text>
    </Pressable>
  );
}

export function Chips({ children }: { children: ReactNode }) {
  return <View style={styles.chips}>{children}</View>;
}

export function Note({ children }: { children: ReactNode }) {
  return <Text style={[font.small, styles.note]}>{children}</Text>;
}

const styles = StyleSheet.create({
  flex: { flex: 1 },
  safe: { flex: 1, backgroundColor: colors.cream },
  content: { padding: spacing.lg, gap: spacing.md, paddingBottom: spacing.xl },
  title: { marginTop: spacing.sm },
  subtitle: { marginBottom: spacing.sm },
  footer: { paddingHorizontal: spacing.lg, paddingBottom: spacing.md, paddingTop: spacing.sm, gap: spacing.sm },
  button: { minHeight: 52, borderRadius: radius.pill, alignItems: 'center', justifyContent: 'center', paddingHorizontal: spacing.lg },
  button_primary: { backgroundColor: colors.coral },
  button_secondary: { backgroundColor: colors.white, borderWidth: 1.5, borderColor: colors.navy },
  button_ghost: { backgroundColor: 'transparent' },
  button_danger: { backgroundColor: colors.white, borderWidth: 1.5, borderColor: colors.error },
  buttonDisabled: { opacity: 0.45 },
  buttonPressed: { opacity: 0.8 },
  buttonLabel: { fontSize: 16, fontWeight: '700' },
  buttonLabel_primary: { color: colors.white },
  buttonLabel_secondary: { color: colors.navy },
  buttonLabel_ghost: { color: colors.navy },
  buttonLabel_danger: { color: colors.error },
  choice: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.md, padding: spacing.md,
    borderRadius: radius.md, backgroundColor: colors.white, borderWidth: 1.5, borderColor: colors.border,
  },
  choiceSelected: { borderColor: colors.coral, backgroundColor: colors.coralSoft },
  choiceDisabled: { opacity: 0.5 },
  choiceLeading: { width: 36, alignItems: 'center' },
  choiceLabel: { fontWeight: '600' },
  badge: { fontSize: 12, color: colors.navy, backgroundColor: colors.navySoft, paddingHorizontal: 8, paddingVertical: 2, borderRadius: radius.pill, overflow: 'hidden' },
  checkboxRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.md, paddingVertical: spacing.xs },
  checkbox: { width: 26, height: 26, borderRadius: 7, borderWidth: 2, borderColor: colors.navy, alignItems: 'center', justifyContent: 'center', backgroundColor: colors.white },
  checkboxChecked: { backgroundColor: colors.navy },
  checkmark: { color: colors.white, fontWeight: '800' },
  field: { gap: spacing.xs },
  input: {
    minHeight: 50, borderRadius: radius.md, borderWidth: 1.5, borderColor: colors.border,
    backgroundColor: colors.white, paddingHorizontal: spacing.md, fontSize: 16, color: colors.text,
  },
  error: { color: colors.error, fontSize: 14 },
  section: { gap: spacing.sm, marginTop: spacing.sm },
  note: { fontStyle: 'italic' },
  chips: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm },
  chip: { flexDirection: 'row', alignItems: 'center', gap: 6, paddingHorizontal: 14, paddingVertical: 8, borderRadius: radius.pill, borderWidth: 1.5, borderColor: colors.border, backgroundColor: colors.white },
  chipSelected: { borderColor: colors.coral, backgroundColor: colors.coralSoft },
  chipLabel: { color: colors.text, fontWeight: '600' },
  chipLabelSelected: { color: colors.coral },
});
