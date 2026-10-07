// Phone number for accounts created with email, Google or Apple: it is what "bloquer mes
// contacts" matches. Verified by an SMS code when auth.phone_verification_required
// (production), declared without check in the free beta. Only digests reach the server.

import { normalizePhone } from '@attractr/shared';
import { useEffect, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { Button, ErrorText, Field, Note, Screen } from '../../components/ui';
import { useOnboarding } from '../../features/onboarding/OnboardingProvider';
import { useSession } from '../../features/session/SessionProvider';
import { api } from '../../lib/api';
import { AppError, errorMessage } from '../../lib/errors';
import { supabase } from '../../lib/supabase';
import { useSubmit } from '../../lib/useSubmit';

export default function PhoneStepScreen() {
  const { t } = useTranslation();
  const { refreshProfile } = useSession();
  const { goNext, progress } = useOnboarding();
  const [verify, setVerify] = useState<boolean | null>(null);
  const [input, setInput] = useState('');
  const [sentTo, setSentTo] = useState<string | null>(null);
  const [code, setCode] = useState('');
  const { busy, error, run } = useSubmit();

  useEffect(() => {
    void api.configBool('auth.phone_verification_required').then(setVerify).catch(() => setVerify(true));
  }, []);

  const submitNumber = () =>
    run(async () => {
      const phone = normalizePhone(input);
      if (!phone) throw new AppError('invalid_phone');
      if (verify) {
        const { error: updateError } = await supabase.auth.updateUser({ phone });
        if (updateError) throw updateError;
        setSentTo(phone);
        return;
      }
      await api.setPhone(phone);
      await refreshProfile();
      await goNext('phone');
    });

  const submitCode = () =>
    run(async () => {
      const { error: verifyError } = await supabase.auth.verifyOtp({ phone: sentTo!, token: code.trim(), type: 'phone_change' });
      if (verifyError) throw new AppError('invalid_otp');
      await refreshProfile();
      await goNext('phone');
    });

  if (sentTo) {
    return (
      <Screen
        progress={progress('phone')}
        title={t('auth.codeTitle')}
        subtitle={t('auth.codeSubtitle', { destination: sentTo })}
        footer={
          <>
            <Button label={t('auth.verify')} onPress={submitCode} loading={busy} disabled={code.trim().length < 6} />
            <Button label={t('auth.changeNumber')} variant="ghost" onPress={() => setSentTo(null)} />
          </>
        }
      >
        <Field value={code} onChangeText={setCode} placeholder={t('auth.codePlaceholder')} keyboardType="number-pad"
          autoComplete="sms-otp" textContentType="oneTimeCode" maxLength={10} onSubmitEditing={submitCode} />
        <ErrorText message={error ? errorMessage(t, error) : null} />
      </Screen>
    );
  }

  return (
    <Screen
      progress={progress('phone')}
      title={t('phoneStep.title')}
      subtitle={t('phoneStep.subtitle')}
      footer={<Button label={t('common.continue')} onPress={submitNumber} loading={busy} disabled={verify === null || input.trim().length < 6} />}
    >
      <Field value={input} onChangeText={setInput} placeholder={t('auth.phonePlaceholder')} keyboardType="phone-pad"
        autoComplete="tel" textContentType="telephoneNumber" onSubmitEditing={submitNumber} />
      <Note>{t(verify ? 'phoneStep.verifiedHint' : 'phoneStep.declaredHint')}</Note>
      <ErrorText message={error ? errorMessage(t, error) : null} />
    </Screen>
  );
}
