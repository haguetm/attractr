// Screen 1: age (18+), terms, privacy, optional referral code (spec §3).

import { isAdult, parseBirthDate } from '@attractr/shared';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { useEffect, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { StyleSheet, View } from 'react-native';
import { Button, Checkbox, ErrorText, Field, Screen, Section } from '../../components/ui';
import { useOnboarding } from '../../features/onboarding/OnboardingProvider';
import { useSession } from '../../features/session/SessionProvider';
import { api } from '../../lib/api';
import { AppError, errorMessage } from '../../lib/errors';
import { PENDING_REFERRAL_KEY } from '../../lib/referral';
import { useSubmit } from '../../lib/useSubmit';

export default function AgeScreen() {
  const { t } = useTranslation();
  const { profile } = useSession();
  const { goNext, progress } = useOnboarding();
  const [day, setDay] = useState('');
  const [month, setMonth] = useState('');
  const [year, setYear] = useState('');
  const [terms, setTerms] = useState(false);
  const [privacy, setPrivacy] = useState(false);
  const [referral, setReferral] = useState('');
  const [befriend, setBefriend] = useState(false);
  const { busy, error, run } = useSubmit();

  // Code kept from a referral link (attractr://r/CODE).
  useEffect(() => {
    void AsyncStorage.getItem(PENDING_REFERRAL_KEY).then((code) => code && setReferral(code)).catch(() => undefined);
  }, []);

  const lockedBirthDate = profile?.birth_date ?? null;
  const birthDate = lockedBirthDate ?? parseBirthDate(Number(day), Number(month), Number(year));
  const typed = lockedBirthDate !== null || (day !== '' && month !== '' && year.length === 4);
  const dateError = typed && !birthDate ? t('age.invalidDate') : birthDate && !isAdult(birthDate) ? t('age.underage') : null;

  const submit = () =>
    run(async () => {
      if (!birthDate || !isAdult(birthDate)) throw new AppError('underage');
      const versions = await api.latestConsentVersions();
      if (!lockedBirthDate) await api.setBirthDate(birthDate);
      await api.grantConsent('terms', versions.terms);
      await api.grantConsent('privacy', versions.privacy);
      if (referral.trim()) await api.setReferralCode(referral, befriend);
      await AsyncStorage.removeItem(PENDING_REFERRAL_KEY).catch(() => undefined);
      await goNext('age');
    });

  return (
    <Screen
      progress={progress('age')}
      title={t('age.title')}
      subtitle={t('age.subtitle')}
      footer={
        <Button
          label={t('common.continue')}
          onPress={submit}
          loading={busy}
          disabled={!birthDate || !!dateError || !terms || !privacy}
        />
      }
    >
      <Section title={t('age.birthDate')}>
        {lockedBirthDate ? (
          <Field value={lockedBirthDate.split('-').reverse().join('/')} editable={false} />
        ) : (
          <View style={styles.dateRow}>
            <Field value={day} onChangeText={setDay} placeholder={t('age.day')} keyboardType="number-pad" maxLength={2} style={styles.small} accessibilityLabel={t('age.day')} />
            <Field value={month} onChangeText={setMonth} placeholder={t('age.month')} keyboardType="number-pad" maxLength={2} style={styles.small} accessibilityLabel={t('age.month')} />
            <Field value={year} onChangeText={setYear} placeholder={t('age.year')} keyboardType="number-pad" maxLength={4} style={styles.large} accessibilityLabel={t('age.year')} />
          </View>
        )}
        <ErrorText message={dateError} />
      </Section>

      <Checkbox label={t('age.acceptTerms')} checked={terms} onToggle={() => setTerms(!terms)} />
      <Checkbox label={t('age.acceptPrivacy')} checked={privacy} onToggle={() => setPrivacy(!privacy)} />

      <Section title={`${t('age.referralCode')} (${t('common.optional').toLowerCase()})`}>
        <Field value={referral} onChangeText={setReferral} placeholder={t('age.referralPlaceholder')} autoCapitalize="characters" maxLength={32} />
        {referral.trim() ? (
          <Checkbox label={t('age.befriendReferrer')} checked={befriend} onToggle={() => setBefriend(!befriend)} />
        ) : null}
      </Section>

      <ErrorText message={error ? errorMessage(t, error) : null} />
    </Screen>
  );
}

const styles = StyleSheet.create({
  dateRow: { flexDirection: 'row', gap: 12 },
  small: { width: 70, textAlign: 'center' },
  large: { width: 100, textAlign: 'center' },
});
