// Placeholder home until the feed (phase 3). Exposes the compliance actions that
// already exist: withdraw sensitive-data consent, delete account, sign out.

import { router } from 'expo-router';
import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import { Button, ErrorText, Note, Screen, Section } from '../components/ui';
import { useSession } from '../features/session/SessionProvider';
import { api } from '../lib/api';
import { errorMessage } from '../lib/errors';
import { useSubmit } from '../lib/useSubmit';

type Pending = 'withdraw' | 'delete' | null;

export default function HomeScreen() {
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

  const leave = () => run(async () => {
    await signOut();
    router.replace('/');
  });

  return (
    <Screen title={t('home.title')} subtitle={t('home.subtitle')}>
      {profile?.verification_status === 'pending' ? <Note>{t('home.pendingVerification')}</Note> : null}

      <Section title={t('home.settings')}>
        {confirming ? (
          <>
            <Note>{t(confirming === 'withdraw' ? 'home.withdrawSensitiveConfirm' : 'home.deleteAccountConfirm')}</Note>
            <Button label={t('home.confirm')} variant="danger" onPress={confirm} loading={busy} />
            <Button label={t('common.cancel')} variant="ghost" onPress={() => setConfirming(null)} />
          </>
        ) : (
          <>
            {profile?.consents.sensitive_data ? (
              <Button label={t('home.withdrawSensitive')} variant="secondary" onPress={() => setConfirming('withdraw')} />
            ) : null}
            <Button label={t('home.deleteAccount')} variant="danger" onPress={() => setConfirming('delete')} />
            <Button label={t('home.signOut')} variant="ghost" onPress={leave} />
          </>
        )}
      </Section>
      <ErrorText message={error ? errorMessage(t, error) : null} />
    </Screen>
  );
}
