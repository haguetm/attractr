// Screen 8: "Ouvert aux couples" (only with a romantic drink). Last intent screen:
// leaving it saves situation, drinks, structure and composition together.

import { useTranslation } from 'react-i18next';
import { Button, Choice, ErrorText, Screen } from '../../components/ui';
import { useOnboarding } from '../../features/onboarding/OnboardingProvider';
import { errorMessage } from '../../lib/errors';
import { useSubmit } from '../../lib/useSubmit';

export default function OpenToCouplesScreen() {
  const { t } = useTranslation();
  const { goNext, progress, intent, setIntent } = useOnboarding();
  const { busy, error, run } = useSubmit();

  return (
    <Screen
      progress={progress('open_to_couples')}
      title={t('openToCouples.title')}
      subtitle={t('openToCouples.subtitle')}
      footer={<Button label={t('common.continue')} onPress={() => run(() => goNext('open_to_couples'))} loading={busy} />}
    >
      <Choice label={t('openToCouples.yes')} selected={intent.openToCouples} onPress={() => setIntent({ ...intent, openToCouples: true })} />
      <Choice label={t('openToCouples.no')} selected={!intent.openToCouples} onPress={() => setIntent({ ...intent, openToCouples: false })} />
      <ErrorText message={error ? errorMessage(t, error) : null} />
    </Screen>
  );
}
