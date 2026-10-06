import '../i18n';

import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { WebPhoneFrame } from '../components/WebPhoneFrame';
import { ActivityTracker } from '../features/session/ActivityTracker';
import { PushRegistration } from '../features/session/PushRegistration';
import { SessionProvider } from '../features/session/SessionProvider';
import { colors } from '../theme';

export default function RootLayout() {
  return (
    <SafeAreaProvider>
      <SessionProvider>
        <StatusBar style="dark" />
        <PushRegistration />
        <ActivityTracker />
        <WebPhoneFrame>
          <Stack screenOptions={{ headerShown: false, contentStyle: { backgroundColor: colors.cream } }} />
        </WebPhoneFrame>
      </SessionProvider>
    </SafeAreaProvider>
  );
}
