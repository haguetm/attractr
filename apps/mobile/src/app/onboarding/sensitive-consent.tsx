// Screen 3: separate GDPR consent for sensitive data (art. 9), withdrawable in one tap.

import { router } from 'expo-router';
import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import { Text } from 'react-native';
import { Button, ErrorText, Note, Screen } from '../../components/ui';
import { useOnboarding } from '../../features/onboarding/OnboardingProvider';
import { stepPath } from '../../features/onboarding/routes';
import { useSession } from '../../features/session/SessionProvider';
import { api } from '../../lib/api';
import { errorMessage } from '../../lib/errors';
import { useSubmit } from '../../lib/useSubmit';
import { font } from '../../theme';

export default function SensitiveConsentScreen() {
  const { t } = useTranslation();
  const { refreshProfile } = useSession();
  const { goNext, progress, seeking } = useOnboarding();
  const [refused, setRefused] = useState(false);
  const { busy, error, run } = useSubmit();

  const accept = () =>
    run(async () => {
      // Sought genders are lost if the app was restarted after screen 2: ask again.
      if (seeking.length === 0) {
        router.replace(stepPath('identity'));
        return;
      }
      const versions = await api.latestConsentVersions();
      await api.grantConsent('sensitive_data', versions.sensitive_data);
      await api.setSeeking(seeking);
      await refreshProfile();
      await goNext('sensitive_consent');
    });

  return (
    <Screen
      progress={progress('sensitive_consent')}
      title={t('sensitiveConsent.title')}
      footer={
        <>
          <Button label={t('sensitiveConsent.accept')} onPress={accept} loading={busy} />
          <Button label={t('sensitiveConsent.refuse')} variant="ghost" onPress={() => setRefused(true)} />
        </>
      }
    >
      <Text style={font.body}>{t('sensitiveConsent.intro')}</Text>
      <Text style={font.body}>{t('sensitiveConsent.items')}</Text>
      <Text style={font.body}>{t('sensitiveConsent.protection')}</Text>
      <Text style={font.body}>{t('sensitiveConsent.withdraw')}</Text>
      {refused ? <Note>{t('sensitiveConsent.refusedInfo')}</Note> : null}
      <ErrorText message={error ? errorMessage(t, error) : null} />
    </Screen>
  );
}
