// Screen 10b: verification selfie, taken with the front camera (never from the
// gallery), then checked server-side (liveness, age estimate, duplicate face).

import * as ImagePicker from 'expo-image-picker';
import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import { Button, ErrorText, Note, Screen } from '../../components/ui';
import { useOnboarding } from '../../features/onboarding/OnboardingProvider';
import { useSession } from '../../features/session/SessionProvider';
import { api, type SelfieOutcome } from '../../lib/api';
import { errorMessage } from '../../lib/errors';
import { uploadImage } from '../../lib/upload';
import { useSubmit } from '../../lib/useSubmit';

export default function SelfieScreen() {
  const { t } = useTranslation();
  const { profile, refreshProfile } = useSession();
  const { goNext, progress } = useOnboarding();
  const [denied, setDenied] = useState(false);
  const [outcome, setOutcome] = useState<SelfieOutcome | null>(null);
  const { busy, error, run } = useSubmit();

  const status = profile?.verification_status;
  const canContinue = outcome === 'verified' || outcome === 'review' || status === 'verified' || (status === 'pending' && outcome !== 'retake');

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
      try {
        setOutcome((await api.verifySelfie()).outcome);
      } catch {
        // The submission stays pending; it will be checked again later.
        setOutcome('review');
      }
      await refreshProfile();
    });

  const message =
    outcome === 'verified' || status === 'verified' ? t('selfie.verified')
      : outcome === 'retake' ? t('selfie.retake')
        : outcome === 'review' || status === 'pending' ? t('selfie.review')
          : null;

  return (
    <Screen
      progress={progress('selfie')}
      title={t('selfie.title')}
      subtitle={t('selfie.subtitle')}
      footer={
        canContinue ? (
          <Button label={t('common.continue')} onPress={() => run(() => goNext('selfie'))} loading={busy} />
        ) : (
          <Button label={outcome === 'retake' ? t('selfie.retake') : t('selfie.take')} onPress={take} loading={busy} />
        )
      }
    >
      {busy ? <Note>{t('selfie.verifying')}</Note> : null}
      {message ? <Note>{message}</Note> : null}
      {denied ? <Note>{t('selfie.permission')}</Note> : null}
      <ErrorText message={error ? errorMessage(t, error) : null} />
    </Screen>
  );
}
