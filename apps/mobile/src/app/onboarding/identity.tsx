// Screen 2: first name, gender, sought genders. Sought genders are sensitive: they
// are only sent once the separate consent (screen 3) exists.
// With a couple account, this is still the person's own profile: the shared profile comes later.

import { GENDERS, type Gender } from '@attractr/shared';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { useEffect, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { Button, Choice, ErrorText, Field, Note, Screen, Section } from '../../components/ui';
import { useOnboarding } from '../../features/onboarding/OnboardingProvider';
import { useSession } from '../../features/session/SessionProvider';
import { api } from '../../lib/api';
import { errorMessage } from '../../lib/errors';
import { WANTS_COUPLE_KEY } from '../../lib/referral';
import { useSubmit } from '../../lib/useSubmit';

export default function IdentityScreen() {
  const { t } = useTranslation();
  const { profile, refreshProfile } = useSession();
  const { goNext, progress, seeking, setSeeking } = useOnboarding();
  const [firstName, setFirstName] = useState(profile?.first_name ?? '');
  const [gender, setGender] = useState<Gender | null>(profile?.gender ?? null);
  const [detail, setDetail] = useState(profile?.gender_detail ?? '');
  const [couple, setCouple] = useState(false);
  const { busy, error, run } = useSubmit();

  useEffect(() => {
    void AsyncStorage.getItem(WANTS_COUPLE_KEY)
      .then((v) => setCouple(v === '1'))
      .catch(() => undefined);
  }, []);

  const toggleSeeking = (g: Gender) =>
    setSeeking(seeking.includes(g) ? seeking.filter((x) => x !== g) : [...seeking, g]);

  const submit = () =>
    run(async () => {
      await api.setIdentity(firstName.trim(), gender!, detail.trim() || null);
      // Consent already given (resumed onboarding): save sought genders now.
      if (profile?.consents.sensitive_data) await api.setSeeking(seeking);
      await refreshProfile();
      await goNext('identity');
    });

  return (
    <Screen
      progress={progress('identity')}
      title={t(couple ? 'identity.titleCouple' : 'identity.title')}
      footer={
        <Button
          label={t('common.continue')}
          onPress={submit}
          loading={busy}
          disabled={!firstName.trim() || !gender || seeking.length === 0}
        />
      }
    >
      {couple && <Note>{t('identity.coupleHint')}</Note>}
      <Field label={t('identity.firstName')} value={firstName} onChangeText={setFirstName} maxLength={40} autoComplete="given-name" />

      <Section title={t('identity.gender')}>
        {GENDERS.map((g) => (
          <Choice key={g} label={t(`gender.${g}`)} selected={gender === g} onPress={() => setGender(g)} />
        ))}
        <Field value={detail} onChangeText={setDetail} placeholder={t('identity.genderDetail')} maxLength={40} />
      </Section>

      <Section title={t('identity.seeking')}>
        {GENDERS.map((g) => (
          <Choice key={g} multiple label={t(`seekingGender.${g}`)} selected={seeking.includes(g)} onPress={() => toggleSeeking(g)} />
        ))}
        <Note>{t('identity.seekingHint')}</Note>
      </Section>

      <ErrorText message={error ? errorMessage(t, error) : null} />
    </Screen>
  );
}
