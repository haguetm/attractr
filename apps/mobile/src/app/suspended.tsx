// Shown while the account is suspended (possible minor under review, or sanctions).
// The user can still sign out or delete the account.

import { router } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { Text } from 'react-native';
import { Button, ErrorText, Note, Screen } from '../components/ui';
import { useSession } from '../features/session/SessionProvider';
import { api } from '../lib/api';
import { errorMessage } from '../lib/errors';
import { useSubmit } from '../lib/useSubmit';
import { font } from '../theme';

export default function SuspendedScreen() {
  const { t } = useTranslation();
  const { profile, signOut } = useSession();
  const { busy, error, run } = useSubmit();

  const leave = () =>
    run(async () => {
      await signOut();
      router.replace('/');
    });

  const remove = () =>
    run(async () => {
      await api.deleteAccount();
      await signOut();
      router.replace('/');
    });

  return (
    <Screen
      title={t('suspended.title')}
      footer={
        <>
          <Button label={t('suspended.signOut')} variant="secondary" onPress={leave} disabled={busy} />
          <Button label={t('suspended.deleteAccount')} variant="danger" onPress={remove} loading={busy} />
        </>
      }
    >
      <Text style={font.body}>{t('suspended.body')}</Text>
      {profile?.verification_in_review ? <Note>{t('suspended.verification')}</Note> : null}
      <Note>{t('suspended.contact')}</Note>
      <ErrorText message={error ? errorMessage(t, error) : null} />
    </Screen>
  );
}
