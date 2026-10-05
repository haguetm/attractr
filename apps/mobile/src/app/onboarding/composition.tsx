// Screen 7b: polyamory "Je cherche" (optional, multiple choice).

import { COMPOSITIONS, type Composition, GENDERS, type Gender } from '@attractr/shared';
import { useTranslation } from 'react-i18next';
import { Button, Choice, ErrorText, Screen, Section } from '../../components/ui';
import { useOnboarding } from '../../features/onboarding/OnboardingProvider';
import { errorMessage } from '../../lib/errors';
import { useSubmit } from '../../lib/useSubmit';

export default function CompositionScreen() {
  const { t } = useTranslation();
  const { goNext, progress, intent, setIntent } = useOnboarding();
  const { busy, error, run } = useSubmit();
  const kinds = intent.composition?.kinds ?? [];
  const threePlusGenders = intent.composition?.threePlusGenders ?? null;

  const update = (nextKinds: Composition[], nextGenders: Gender[] | null) =>
    setIntent({
      ...intent,
      composition: nextKinds.length
        ? { kinds: nextKinds, threePlusGenders: nextKinds.includes('three_plus') ? nextGenders : null }
        : null,
    });

  const toggleKind = (k: Composition) =>
    update(kinds.includes(k) ? kinds.filter((x) => x !== k) : [...kinds, k], threePlusGenders);

  const toggleGender = (g: Gender) => {
    const current = threePlusGenders ?? [];
    const next = current.includes(g) ? current.filter((x) => x !== g) : [...current, g];
    update(kinds, next.length ? next : null);
  };

  return (
    <Screen
      progress={progress('composition')}
      title={t('composition.title')}
      subtitle={t('composition.subtitle')}
      footer={<Button label={kinds.length ? t('common.continue') : t('common.skip')} onPress={() => run(() => goNext('composition'))} loading={busy} />}
    >
      {COMPOSITIONS.map((k) => (
        <Choice key={k} multiple label={t(`composition.${k}`)} selected={kinds.includes(k)} onPress={() => toggleKind(k)} />
      ))}
      {kinds.includes('three_plus') ? (
        <Section title={t('composition.threePlusGenders')}>
          <Choice multiple label={t('composition.anyGender')} selected={threePlusGenders === null} onPress={() => update(kinds, null)} />
          {GENDERS.map((g) => (
            <Choice key={g} multiple label={t(`gender.${g}`)} selected={!!threePlusGenders?.includes(g)} onPress={() => toggleGender(g)} />
          ))}
        </Section>
      ) : null}
      <ErrorText message={error ? errorMessage(t, error) : null} />
    </Screen>
  );
}
