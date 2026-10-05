// Screen 7: relationship structure (only with a romantic drink).

import { structureChoices, withStructure } from '@attractr/shared';
import { useTranslation } from 'react-i18next';
import { Button, Choice, ErrorText, Screen } from '../../components/ui';
import { useOnboarding } from '../../features/onboarding/OnboardingProvider';
import { errorMessage } from '../../lib/errors';
import { useSubmit } from '../../lib/useSubmit';

export default function StructureScreen() {
  const { t } = useTranslation();
  const { goNext, progress, intent, setIntent } = useOnboarding();
  const { busy, error, run } = useSubmit();

  return (
    <Screen
      progress={progress('structure')}
      title={t('structure.title')}
      subtitle={t('structure.subtitle')}
      footer={<Button label={t('common.continue')} onPress={() => run(() => goNext('structure'))} loading={busy} disabled={!intent.structure} />}
    >
      {structureChoices(intent.situation).map((s) => (
        <Choice key={s} label={t(`structure.${s}`)} selected={intent.structure === s} onPress={() => setIntent(withStructure(intent, s))} />
      ))}
      <ErrorText message={error ? errorMessage(t, error) : null} />
    </Screen>
  );
}
