// First screen: the sign-in methods enabled for this build (lib/auth.ts).

import { Image } from 'expo-image';
import { router } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { StyleSheet } from 'react-native';
import { Button, ErrorText, Note, Screen } from '../../components/ui';
import { useSession } from '../../features/session/SessionProvider';
import { ENABLED_AUTH_METHODS, signInWithProvider } from '../../lib/auth';
import { errorMessage } from '../../lib/errors';
import { useSubmit } from '../../lib/useSubmit';

export default function SignInScreen() {
  const { t } = useTranslation();
  const { refreshProfile } = useSession();
  const { busy, error, run } = useSubmit();

  const withProvider = (provider: 'google' | 'apple') =>
    run(async () => {
      if (!(await signInWithProvider(provider))) return;
      await refreshProfile();
      router.replace('/');
    });

  const buttons = {
    apple: <Button key="apple" label={t('auth.withApple')} onPress={() => withProvider('apple')} loading={busy} />,
    google: <Button key="google" label={t('auth.withGoogle')} variant="secondary" onPress={() => withProvider('google')} disabled={busy} />,
    email: <Button key="email" label={t('auth.withEmail')} variant="secondary" onPress={() => router.push('/email')} disabled={busy} />,
    phone: <Button key="phone" label={t('auth.withPhone')} variant="secondary" onPress={() => router.push('/phone')} disabled={busy} />,
  };

  return (
    <Screen title={t('auth.signInTitle')} subtitle={t('auth.signInSubtitle')}>
      <Image source={require('../../../assets/images/logo.png')} style={styles.logo} contentFit="contain" />
      {(['apple', 'google', 'email', 'phone'] as const).filter((m) => ENABLED_AUTH_METHODS.includes(m)).map((m) => buttons[m])}
      <Note>{t('auth.phoneNote')}</Note>
      <ErrorText message={error ? errorMessage(t, error) : null} />
    </Screen>
  );
}

const styles = StyleSheet.create({ logo: { width: 140, height: 140, alignSelf: 'center' } });
