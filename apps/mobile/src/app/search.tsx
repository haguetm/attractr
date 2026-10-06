// Free search filters (spec §4, §10): around me (radius), département or région,
// age range, drinks. The passport (searching elsewhere) is Premium, phase 7.

import { DRINKS, type Drink } from '@attractr/shared';
import { router } from 'expo-router';
import { useEffect, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { StyleSheet, Text, View } from 'react-native';
import { DrinkIcon } from '../components/DrinkIcon';
import { Button, Chip, Choice, ErrorText, Note, Screen, Section } from '../components/ui';
import { useSession } from '../features/session/SessionProvider';
import { api, type SearchMode, type SearchPreferences } from '../lib/api';
import { errorMessage } from '../lib/errors';
import { useSubmit } from '../lib/useSubmit';
import { font, spacing } from '../theme';

const RADII = [5, 10, 25, 50, 100, 200, 300];
const MODES: SearchMode[] = ['radius', 'department', 'region'];

export default function SearchScreen() {
  const { t } = useTranslation();
  const { profile, refreshProfile } = useSession();
  const [prefs, setPrefs] = useState<SearchPreferences | null>(profile?.search ?? null);
  const [maxRadius, setMaxRadius] = useState(300);
  const { busy, error, run } = useSubmit();

  useEffect(() => {
    void api.configInt('feed.max_radius_km').then(setMaxRadius).catch(() => undefined);
  }, []);

  if (!prefs || !profile) return null;
  const update = (patch: Partial<SearchPreferences>) => setPrefs({ ...prefs, ...patch });
  const selectedDrinks = prefs.drinks ?? [];
  const toggleDrink = (d: Drink) => {
    const next = selectedDrinks.includes(d) ? selectedDrinks.filter((x) => x !== d) : [...selectedDrinks, d];
    update({ drinks: next.length ? next : null });
  };
  const modeAvailable = (m: SearchMode) =>
    m === 'radius' || (m === 'department' ? !!profile.department_code : !!profile.region_code);

  const save = () =>
    run(async () => {
      await api.setSearchPreferences(prefs);
      await refreshProfile();
      router.back();
    });

  return (
    <Screen
      title={t('search.title')}
      footer={
        <>
          <Button label={t('search.save')} onPress={save} loading={busy} />
          <Button label={t('common.back')} variant="ghost" onPress={() => router.back()} />
        </>
      }
    >
      <Section title={t('search.area')}>
        {MODES.filter(modeAvailable).map((m) => (
          <Choice key={m} label={t(`search.${m}`)} selected={prefs.mode === m} onPress={() => update({ mode: m })} />
        ))}
        {prefs.mode === 'radius' ? (
          <View style={styles.chips}>
            {RADII.filter((r) => r <= maxRadius).map((r) => (
              <Chip key={r} label={t('search.radiusValue', { km: r })} selected={prefs.radius_km === r} onPress={() => update({ radius_km: r })} />
            ))}
          </View>
        ) : null}
        <Note>{t('search.passportSoon')}</Note>
      </Section>

      <Section title={t('search.age')}>
        <Text style={font.body}>{t('search.ageRange', { min: prefs.age_min, max: prefs.age_max })}</Text>
        <Stepper value={prefs.age_min} min={18} max={prefs.age_max} onChange={(age_min) => update({ age_min })} />
        <Stepper value={prefs.age_max} min={prefs.age_min} max={99} onChange={(age_max) => update({ age_max })} />
      </Section>

      <Section title={t('search.drinks')}>
        <View style={styles.chips}>
          {DRINKS.map((d) => (
            <Chip
              key={d}
              label={t(`drinks.${d}`)}
              selected={selectedDrinks.includes(d)}
              onPress={() => toggleDrink(d)}
              leading={<DrinkIcon drink={d} alcoholFree={profile.alcohol_free_icons} size={18} />}
            />
          ))}
        </View>
        <Note>{t('search.drinksHint')}</Note>
      </Section>

      <ErrorText message={error ? errorMessage(t, error) : null} />
    </Screen>
  );
}

function Stepper(props: { value: number; min: number; max: number; onChange: (v: number) => void }) {
  return (
    <View style={styles.stepper}>
      <Chip label="−" selected={false} onPress={() => props.onChange(Math.max(props.min, props.value - 1))} />
      <Text style={[font.body, styles.stepperValue]}>{props.value}</Text>
      <Chip label="+" selected={false} onPress={() => props.onChange(Math.min(props.max, props.value + 1))} />
    </View>
  );
}

const styles = StyleSheet.create({
  chips: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm },
  stepper: { flexDirection: 'row', alignItems: 'center', gap: spacing.md },
  stepperValue: { minWidth: 32, textAlign: 'center', fontWeight: '700' },
});
