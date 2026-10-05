// Screen 10b: verification selfie, taken with the front camera (never from the
// gallery). Verification and age estimate run server-side in phase 5.

import * as ImagePicker from 'expo-image-picker';
import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import { Button, ErrorText, Note, Screen } from '../../components/ui';
import { useOnboarding } from '../../features/onboarding/OnboardingProvider';
import { useSession } from '../../features/session/SessionProvider';
import { api } from '../../lib/api';
import { errorMessage } from '../../lib/errors';
import { uploadImage } from '../../lib/upload';
import { useSubmit } from '../../lib/useSubmit';

export default function SelfieScreen() {
  const { t } = useTranslation();
  const { profile, refreshProfile } = useSession();
  const { goNext, progress } = useOnboarding();
  const [denied, setDenied] = useState(false);
  const { busy, error, run } = useSubmit();
  const submitted = profile?.verification_status === 'pending' || profile?.verification_status === 'verified';

  const take = () =>
    run(async () => {
      const permission = await ImagePicker.requestCameraPermissionsAsync();
      if (!permission.granted) {
        setDenied(true);
        return;
      }
      const result = await ImagePicker.launchCameraAsync({
        mediaTypes: ['images'],
        cameraType: ImagePicker.CameraType.front,
        quality: 0.8,
      });
      if (result.canceled || !result.assets[0]) return;
      const asset = result.assets[0];
      const path = await uploadImage('selfies', profile!.id, asset.uri, asset.mimeType);
      await api.submitSelfie(path);
      await refreshProfile();
    });

  return (
    <Screen
      progress={progress('selfie')}
      title={t('selfie.title')}
      subtitle={t('selfie.subtitle')}
      footer={
        submitted ? (
          <Button label={t('common.continue')} onPress={() => run(() => goNext('selfie'))} loading={busy} />
        ) : (
          <Button label={t('selfie.take')} onPress={take} loading={busy} />
        )
      }
    >
      {submitted ? <Note>{t('selfie.submitted')}</Note> : null}
      {denied ? <Note>{t('selfie.permission')}</Note> : null}
      <ErrorText message={error ? errorMessage(t, error) : null} />
    </Screen>
  );
}
