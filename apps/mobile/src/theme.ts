// Palette taken from the Attractr logo (coral + navy on cream).
export const colors = {
  coral: '#F25459',
  coralSoft: '#FDE3E2',
  navy: '#1F2A4A',
  navySoft: '#E6E8EF',
  cream: '#FDF5EC',
  white: '#FFFFFF',
  text: '#1F2A4A',
  textMuted: '#6B6F80',
  border: '#E8DCCD',
  error: '#B3261E',
  success: '#2E7D4F',
} as const;

export const spacing = { xs: 4, sm: 8, md: 16, lg: 24, xl: 32 } as const;
export const radius = { sm: 8, md: 14, lg: 22, pill: 999 } as const;

export const font = {
  title: { fontSize: 28, fontWeight: '700' as const, color: colors.text },
  subtitle: { fontSize: 16, color: colors.textMuted, lineHeight: 22 },
  body: { fontSize: 16, color: colors.text, lineHeight: 22 },
  label: { fontSize: 14, fontWeight: '600' as const, color: colors.text },
  small: { fontSize: 13, color: colors.textMuted, lineHeight: 18 },
};
