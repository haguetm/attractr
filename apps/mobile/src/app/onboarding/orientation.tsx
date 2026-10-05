// Screen 11: optional orientation label, hideable, no effect on matching.
// Leaving this screen completes the onboarding.

import { useEffect, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { Button, Checkbox, Choice, ErrorText, Screen } from '../../components/ui';
import { useOnboarding } from '../../features/onboarding/OnboardingProvider';
import { useSession } from '../../features/session/SessionProvider';
import { api } from '../../lib/api';
import { errorMessage } from '../../lib/errors';
import { supabase } from '../../lib/supabase';
import { useSubmit } from '../../lib/useSubmit';

export default function OrientationScreen() {
  const { t } = useTranslation();
  const { profile } = useSession();
  const { goNext, progress, switches } = useOnboarding();
  const [labels, setLabels] = useState<string[]>([]);
  const [label, setLabel] = useState<string | null>(profile?.sensitive.orientation ?? null);
  const [visible, setVisible] = useState(profile?.sensitive.orientation_visible ?? false);
  const { busy, error, run } = useSubmit();

  useEffect(() => {
    void supabase
      .from('orientation_labels')
      .select('code')
      .eq('active', true)
      .order('sort_order')
      .then(({ data }) => setLabels((data ?? []).map((l) => l.code as string)));
  }, []);

  const finish = (save: boolean) =>
    run(async () => {
      if (save) await api.setOrientation(label, visible);
      await goNext('orientation');
    });

  return (
    <Screen
      progress={progress('orientation')}
      title={t('orientation.title')}
      subtitle={t('orientation.subtitle')}
      footer={
        <>
          <Button label={t('orientation.finish')} onPress={() => finish(true)} loading={busy} />
          <Button label={t('common.skip')} variant="ghost" onPress={() => finish(false)} disabled={busy} />
        </>
      }
    >
      {switches.orientationEnabled && labels.map((code) => (
        <Choice key={code} label={t(`orientation.labels.${code}`)} selected={label === code} onPress={() => setLabel(label === code ? null : code)} />
      ))}
      {label ? <Checkbox label={t('orientation.visible')} checked={visible} onToggle={() => setVisible(!visible)} /> : null}
      <ErrorText message={error ? errorMessage(t, error) : null} />
    </Screen>
  );
}
