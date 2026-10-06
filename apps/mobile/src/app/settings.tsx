// Settings: search preferences, compliance actions (withdraw sensitive-data consent,
// delete account), sign out, and development tools in dev builds.

import { router } from 'expo-router';
import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import { Button, ErrorText, Note, Screen, Section } from '../components/ui';
import { useSession } from '../features/session/SessionProvider';
import { api } from '../lib/api';
import { DEV_TOOLS_ENABLED } from '../lib/devTools';
import { errorMessage } from '../lib/errors';
import { useSubmit } from '../lib/useSubmit';

type Pending = 'withdraw' | 'delete' | null;

export default function SettingsScreen() {
  const { t } = useTranslation();
  const { profile, refreshProfile, signOut } = useSession();
  const [confirming, setConfirming] = useState<Pending>(null);
  const { busy, error, run } = useSubmit();

  const confirm = () =>
    run(async () => {
      if (confirming === 'withdraw') {
        await api.withdrawConsent('sensitive_data');
        await refreshProfile();
      } else if (confirming === 'delete') {
        await api.deleteAccount();
        await signOut();
        router.replace('/');
      }
      setConfirming(null);
    });

  const leave = () =>
    run(async () => {
      await signOut();
      router.replace('/');
    });

  return (
    <Screen title={t('settings.title')} footer={<Button label={t('common.back')} variant="ghost" onPress={() => router.back()} />}>
      {profile?.verification_status === 'pending' ? <Note>{t('settings.pendingVerification')}</Note> : null}

      <Button label={t('settings.searchPreferences')} variant="secondary" onPress={() => router.push('/search')} />

      <Section title={t('settings.title')}>
        {confirming ? (
          <>
            <Note>{t(confirming === 'withdraw' ? 'settings.withdrawSensitiveConfirm' : 'settings.deleteAccountConfirm')}</Note>
            <Button label={t('settings.confirm')} variant="danger" onPress={confirm} loading={busy} />
            <Button label={t('common.cancel')} variant="ghost" onPress={() => setConfirming(null)} />
          </>
        ) : (
          <>
            {profile?.consents.sensitive_data ? (
              <Button label={t('settings.withdrawSensitive')} variant="secondary" onPress={() => setConfirming('withdraw')} />
            ) : null}
            <Button label={t('settings.deleteAccount')} variant="danger" onPress={() => setConfirming('delete')} />
            <Button label={t('settings.signOut')} variant="ghost" onPress={leave} />
          </>
        )}
      </Section>

      {DEV_TOOLS_ENABLED ? (
        <Section title={t('settings.devTools')}>
          <Button label={t('dev.title')} variant="secondary" onPress={() => router.push('/dev/impersonate')} />
        </Section>
      ) : null}

      <ErrorText message={error ? errorMessage(t, error) : null} />
    </Screen>
  );
}
