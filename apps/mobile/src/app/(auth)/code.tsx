import { router, useLocalSearchParams } from 'expo-router';
import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import { Button, ErrorText, Field, Screen } from '../../components/ui';
import { useSubmit } from '../../lib/useSubmit';
import { useSession } from '../../features/session/SessionProvider';
import { AppError, errorMessage } from '../../lib/errors';
import { supabase } from '../../lib/supabase';

export default function CodeScreen() {
  const { t } = useTranslation();
  const { phone } = useLocalSearchParams<{ phone: string }>();
  const { refreshProfile } = useSession();
  const [code, setCode] = useState('');
  const { busy, error, run } = useSubmit();

  const verify = () =>
    run(async () => {
      const { error: verifyError } = await supabase.auth.verifyOtp({ phone, token: code.trim(), type: 'sms' });
      if (verifyError) throw new AppError('invalid_otp');
      await refreshProfile();
      router.replace('/');
    });

  return (
    <Screen
      title={t('auth.codeTitle')}
      subtitle={t('auth.codeSubtitle', { phone })}
      footer={
        <>
          <Button label={t('auth.verify')} onPress={verify} loading={busy} disabled={code.trim().length < 6} />
          <Button label={t('auth.changeNumber')} variant="ghost" onPress={() => router.back()} />
        </>
      }
    >
      <Field
        value={code}
        onChangeText={setCode}
        placeholder={t('auth.codePlaceholder')}
        keyboardType="number-pad"
        autoComplete="sms-otp"
        textContentType="oneTimeCode"
        maxLength={6}
        onSubmitEditing={verify}
      />
      <ErrorText message={error ? errorMessage(t, error) : null} />
    </Screen>
  );
}
