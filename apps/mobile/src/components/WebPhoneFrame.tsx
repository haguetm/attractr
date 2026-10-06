import type { ReactNode } from 'react';
import { Platform, StyleSheet, View } from 'react-native';
import { colors } from '../theme';

// The app is mobile-only: on web (dev preview in a desktop browser), render it inside
// a phone-sized frame instead of stretching it across the whole window.
const PHONE_WIDTH = 390;
const PHONE_HEIGHT = 844;

export function WebPhoneFrame({ children }: { children: ReactNode }) {
  if (Platform.OS !== 'web') return <>{children}</>;
  return (
    <View style={styles.backdrop}>
      <View style={styles.phone}>{children}</View>
    </View>
  );
}

const styles = StyleSheet.create({
  backdrop: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.navy,
  },
  phone: {
    width: '100%',
    maxWidth: PHONE_WIDTH,
    height: '100%',
    maxHeight: PHONE_HEIGHT,
    overflow: 'hidden',
    borderRadius: 32,
    backgroundColor: colors.cream,
  },
});
