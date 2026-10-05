import { normalizePhone } from '@attractr/shared';
import { Image } from 'expo-image';
import { router } from 'expo-router';
import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import { StyleSheet } from 'react-native';
import { Button, ErrorText, Field, Screen } from '../../components/ui';
import { useSubmit } from '../../lib/useSubmit';
import { AppError, errorMessage } from '../../lib/errors';
import { supabase } from '../../lib/supabase';

export default function PhoneScreen() {
  const { t } = useTranslation();
  const [input, setInput] = useState('');
  const { busy, error, run } = useSubmit();

  const send = () =>
    run(async () => {
      const phone = normalizePhone(input);
      if (!phone) throw new AppError('invalid_phone');
      const { error: otpError } = await supabase.auth.signInWithOtp({ phone });
      if (otpError) throw otpError;
      router.push({ pathname: '/code', params: { phone } });
    });

  return (
    <Screen
      title={t('auth.phoneTitle')}
      subtitle={t('auth.phoneSubtitle')}
      footer={<Button label={t('auth.sendCode')} onPress={send} loading={busy} disabled={input.trim().length < 6} />}
    >
      <Image source={require('../../../assets/images/logo.png')} style={styles.logo} contentFit="contain" />
      <Field
        value={input}
        onChangeText={setInput}
        placeholder={t('auth.phonePlaceholder')}
        keyboardType="phone-pad"
        autoComplete="tel"
        textContentType="telephoneNumber"
        onSubmitEditing={send}
      />
      <ErrorText message={error ? errorMessage(t, error) : null} />
    </Screen>
  );
}

const styles = StyleSheet.create({ logo: { width: 120, height: 120, alignSelf: 'center' } });
