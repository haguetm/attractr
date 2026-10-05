// Screen 5: current situation (declarative).

import { SITUATIONS, withSituation } from '@attractr/shared';
import { useTranslation } from 'react-i18next';
import { Button, Choice, Screen } from '../../components/ui';
import { useOnboarding } from '../../features/onboarding/OnboardingProvider';

export default function SituationScreen() {
  const { t } = useTranslation();
  const { goNext, progress, intent, setIntent } = useOnboarding();

  return (
    <Screen
      progress={progress('situation')}
      title={t('situation.title')}
      footer={<Button label={t('common.continue')} onPress={() => void goNext('situation')} disabled={!intent.situation} />}
    >
      {SITUATIONS.map((s) => (
        <Choice
          key={s}
          label={t(`situation.${s}`)}
          description={t(`situation.${s}Description`)}
          selected={intent.situation === s}
          onPress={() => setIntent(withSituation(intent, s))}
        />
      ))}
    </Screen>
  );
}
