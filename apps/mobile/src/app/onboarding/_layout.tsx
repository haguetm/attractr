import { Stack } from 'expo-router';
import { OnboardingProvider } from '../../features/onboarding/OnboardingProvider';
import { colors } from '../../theme';

export default function OnboardingLayout() {
  return (
    <OnboardingProvider>
      <Stack screenOptions={{ headerShown: false, contentStyle: { backgroundColor: colors.cream } }} />
    </OnboardingProvider>
  );
}
