// Screen 4: individual or couple account. Couple accounts arrive in phase 9.

import { useTranslation } from 'react-i18next';
import { Button, Choice, Screen } from '../../components/ui';
import { useOnboarding } from '../../features/onboarding/OnboardingProvider';

export default function AccountTypeScreen() {
  const { t } = useTranslation();
  const { goNext, progress } = useOnboarding();

  return (
    <Screen
      progress={progress('account_type')}
      title={t('accountType.title')}
      footer={<Button label={t('common.continue')} onPress={() => void goNext('account_type')} />}
    >
      <Choice label={t('accountType.individual')} description={t('accountType.individualDescription')} selected onPress={() => undefined} />
      <Choice
        label={t('accountType.couple')}
        description={t('accountType.coupleDescription')}
        selected={false}
        disabled
        badge={t('accountType.comingSoon')}
        onPress={() => undefined}
      />
    </Screen>
  );
}
