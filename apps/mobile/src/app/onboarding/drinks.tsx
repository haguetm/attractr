// Screen 6: one drink, or beer plus one other (spec §1). Explanatory subtitles are
// shown here only; the rest of the app shows the icon alone.

import { type Drink, canAddBeer, mainDrinkChoices, withDrinks } from '@attractr/shared';
import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import { Button, Checkbox, Choice, ErrorText, Note, Screen } from '../../components/ui';
import { DrinkIcon } from '../../components/DrinkIcon';
import { useOnboarding } from '../../features/onboarding/OnboardingProvider';
import { useSession } from '../../features/session/SessionProvider';
import { api } from '../../lib/api';
import { errorMessage } from '../../lib/errors';
import { useSubmit } from '../../lib/useSubmit';

export default function DrinksScreen() {
  const { t } = useTranslation();
  const { profile } = useSession();
  const { goNext, progress, intent, setIntent } = useOnboarding();
  const [alcoholFree, setAlcoholFree] = useState(profile?.alcohol_free_icons ?? false);
  const { busy, error, run } = useSubmit();

  const main = intent.drinks.find((d) => d !== 'beer') ?? (intent.drinks.includes('beer') ? 'beer' : null);
  const withBeer = main !== 'beer' && intent.drinks.includes('beer');

  const choose = (drink: Drink) => setIntent(withDrinks(intent, drink === 'beer' ? ['beer'] : withBeer ? ['beer', drink] : [drink]));
  const toggleBeer = () => main && main !== 'beer' && setIntent(withDrinks(intent, withBeer ? [main] : ['beer', main]));

  const submit = () =>
    run(async () => {
      if (profile && alcoholFree !== profile.alcohol_free_icons) await api.setAlcoholFreeIcons(alcoholFree, profile.id);
      await goNext('drinks');
    });

  return (
    <Screen
      progress={progress('drinks')}
      title={t('drinks.title')}
      subtitle={t('drinks.subtitle')}
      footer={<Button label={t('common.continue')} onPress={submit} loading={busy} disabled={!main} />}
    >
      {mainDrinkChoices(intent.situation).map((d) => (
        <Choice
          key={d}
          label={t(`drinks.${d}`)}
          description={t(`drinks.${d}Subtitle`)}
          selected={main === d}
          onPress={() => choose(d)}
          leading={<DrinkIcon drink={d} alcoholFree={alcoholFree} />}
        />
      ))}
      {canAddBeer(intent.situation, main) ? (
        <Checkbox label={t('drinks.addBeer')} checked={withBeer} onToggle={toggleBeer} />
      ) : null}
      <Note>{t('drinks.disclaimer')}</Note>
      <Checkbox label={t('drinks.alcoholFreeIcons')} checked={alcoholFree} onToggle={() => setAlcoholFree(!alcoholFree)} />
      <ErrorText message={error ? errorMessage(t, error) : null} />
    </Screen>
  );
}
