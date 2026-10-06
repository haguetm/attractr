// First screen: individual or couple account, asked before anything else so the first name
// screen can say whose name it asks for. A couple account is built from two individual
// verified accounts (spec §6): everyone finishes their own signup first; with "couple",
// the app opens the couple screen afterwards to invite the partner.

import AsyncStorage from '@react-native-async-storage/async-storage';
import { useEffect, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { Button, Choice, Screen } from '../../components/ui';
import { useOnboarding } from '../../features/onboarding/OnboardingProvider';
import { WANTS_COUPLE_KEY } from '../../lib/referral';

export default function AccountTypeScreen() {
  const { t } = useTranslation();
  const { goNext, progress } = useOnboarding();
  const [couple, setCouple] = useState(false);

  // Resumed onboarding: keep the earlier answer.
  useEffect(() => {
    void AsyncStorage.getItem(WANTS_COUPLE_KEY)
      .then((v) => setCouple(v === '1'))
      .catch(() => undefined);
  }, []);

  const next = async () => {
    if (couple) await AsyncStorage.setItem(WANTS_COUPLE_KEY, '1').catch(() => undefined);
    else await AsyncStorage.removeItem(WANTS_COUPLE_KEY).catch(() => undefined);
    await goNext('account_type');
  };

  return (
    <Screen progress={progress('account_type')} title={t('accountType.title')} footer={<Button label={t('common.continue')} onPress={() => void next()} />}>
      <Choice label={t('accountType.individual')} description={t('accountType.individualDescription')} selected={!couple} onPress={() => setCouple(false)} />
      <Choice label={t('accountType.couple')} description={t('accountType.coupleDescription')} selected={couple} onPress={() => setCouple(true)} />
    </Screen>
  );
}
