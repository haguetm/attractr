// Search filters (spec §4, §10). Free: around me (radius), département or région, age,
// drinks. Premium: verified only, recently active, education, height, interests,
// composition sought, and the passport (search around another city).

import { COMPOSITIONS, DRINKS, type Drink } from '@attractr/shared';
import { router } from 'expo-router';
import { useEffect, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { StyleSheet, Text, View } from 'react-native';
import { DrinkIcon } from '../components/DrinkIcon';
import { Button, Checkbox, Chip, Chips, Choice, ErrorText, Field, Note, Screen, Section } from '../components/ui';
import { useSession } from '../features/session/SessionProvider';
import { api, EDUCATION_LEVELS, type EducationLevel, type SearchMode, type SearchPreferences } from '../lib/api';
import { errorMessage } from '../lib/errors';
import { supabase } from '../lib/supabase';
import { useSubmit } from '../lib/useSubmit';
import { font, spacing } from '../theme';

const RADII = [5, 10, 25, 50, 100, 200, 300];
const MODES: SearchMode[] = ['radius', 'department', 'region'];

const toggle = <T,>(list: T[] | null, value: T): T[] | null => {
  const current = list ?? [];
  const next = current.includes(value) ? current.filter((x) => x !== value) : [...current, value];
  return next.length ? next : null;
};

export default function SearchScreen() {
  const { t } = useTranslation();
  const { profile, refreshProfile } = useSession();
  const [prefs, setPrefs] = useState<SearchPreferences | null>(profile?.search ?? null);
  const [maxRadius, setMaxRadius] = useState(300);
  const [interestCatalog, setInterestCatalog] = useState<string[]>([]);
  const [passportQuery, setPassportQuery] = useState('');
  const { busy, error, run } = useSubmit();
  const premium = !!profile?.premium.active;

  useEffect(() => {
    void api.configInt('feed.max_radius_km').then(setMaxRadius).catch(() => undefined);
    void supabase.from('interests').select('code').eq('active', true).order('sort_order')
      .then(({ data }) => setInterestCatalog((data ?? []).map((r) => r.code as string)));
  }, []);

  if (!prefs || !profile) return null;
  const update = (patch: Partial<SearchPreferences>) => setPrefs({ ...prefs, ...patch });
  const modeAvailable = (m: SearchMode) =>
    m === 'radius' || (m === 'department' ? !!profile.department_code : !!profile.region_code);

  const save = () =>
    run(async () => {
      await api.setSearchPreferences(prefs, premium);
      await refreshProfile();
      router.back();
    });

  const setPassport = () =>
    run(async () => {
      const { label } = await api.setPassport(passportQuery);
      const p = await refreshProfile();
      if (p) setPrefs({ ...prefs, mode: 'radius', passport_label: label ?? p.search.passport_label });
      setPassportQuery('');
    });

  const clearPassport = () =>
    run(async () => {
      await api.clearPassport();
      await refreshProfile();
      update({ passport_label: null });
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
          <Choice key={m} label={t(`search.${m}`)} selected={prefs.mode === m} onPress={() => update({ mode: m })} disabled={!!prefs.passport_label && m !== 'radius'} />
        ))}
        {prefs.mode === 'radius' ? (
          <Chips>
            {RADII.filter((r) => r <= maxRadius).map((r) => (
              <Chip key={r} label={t('search.radiusValue', { km: r })} selected={prefs.radius_km === r} onPress={() => update({ radius_km: r })} />
            ))}
          </Chips>
        ) : null}
      </Section>

      <Section title={t('search.age')}>
        <Text style={font.body}>{t('search.ageRange', { min: prefs.age_min, max: prefs.age_max })}</Text>
        <Stepper value={prefs.age_min} min={18} max={prefs.age_max} onChange={(age_min) => update({ age_min })} />
        <Stepper value={prefs.age_max} min={prefs.age_min} max={99} onChange={(age_max) => update({ age_max })} />
      </Section>

      <Section title={t('search.drinks')}>
        <Chips>
          {DRINKS.map((d) => (
            <Chip
              key={d}
              label={t(`drinks.${d}`)}
              selected={(prefs.drinks ?? []).includes(d)}
              onPress={() => update({ drinks: toggle<Drink>(prefs.drinks, d) })}
              leading={<DrinkIcon drink={d} alcoholFree={profile.alcohol_free_icons} size={18} />}
            />
          ))}
        </Chips>
        <Note>{t('search.drinksHint')}</Note>
      </Section>

      <Section title={`${t('search.passport')}${premium ? '' : ` · ${t('premium.locked')}`}`}>
        <Note>{prefs.passport_label ? t('search.passportSet', { label: prefs.passport_label }) : t('search.passportHint')}</Note>
        {premium ? (
          prefs.passport_label ? (
            <Button label={t('search.passportClear')} variant="secondary" onPress={clearPassport} disabled={busy} />
          ) : (
            <>
              <Field value={passportQuery} onChangeText={setPassportQuery} placeholder={t('search.passportPlaceholder')} />
              <Button label={t('search.passportApply')} variant="secondary" onPress={setPassport} disabled={busy || passportQuery.trim().length < 2} />
            </>
          )
        ) : null}
      </Section>

      <Section title={`${t('search.premiumFilters')}${premium ? '' : ` · ${t('premium.locked')}`}`}>
        {premium ? (
          <>
            <Checkbox label={t('search.verifiedOnly')} checked={prefs.verified_only} onToggle={() => update({ verified_only: !prefs.verified_only })} />
            <Checkbox label={t('search.recentlyActive')} checked={prefs.recently_active} onToggle={() => update({ recently_active: !prefs.recently_active })} />
            <Text style={font.label}>{t('search.education')}</Text>
            <Chips>
              {EDUCATION_LEVELS.map((e) => (
                <Chip key={e} label={t(`details.educationLevels.${e}`)} selected={(prefs.education_levels ?? []).includes(e)}
                  onPress={() => update({ education_levels: toggle<EducationLevel>(prefs.education_levels, e) })} />
              ))}
            </Chips>
            <Text style={font.label}>{t('search.height')}</Text>
            <Text style={font.small}>
              {prefs.height_min || prefs.height_max
                ? t('search.heightRange', { min: prefs.height_min ?? 120, max: prefs.height_max ?? 230 })
                : t('search.anyHeight')}
            </Text>
            <Stepper value={prefs.height_min ?? 120} min={120} max={prefs.height_max ?? 230} onChange={(v) => update({ height_min: v === 120 ? null : v })} />
            <Stepper value={prefs.height_max ?? 230} min={prefs.height_min ?? 120} max={230} onChange={(v) => update({ height_max: v === 230 ? null : v })} />
            <Text style={font.label}>{t('search.interests')}</Text>
            <Chips>
              {interestCatalog.map((code) => (
                <Chip key={code} label={t(`details.interestLabels.${code}`)} selected={(prefs.interests ?? []).includes(code)}
                  onPress={() => update({ interests: toggle(prefs.interests, code) })} />
              ))}
            </Chips>
            <Text style={font.label}>{t('search.compositions')}</Text>
            <Chips>
              {COMPOSITIONS.map((c) => (
                <Chip key={c} label={t(`composition.${c}`)} selected={(prefs.compositions ?? []).includes(c)}
                  onPress={() => update({ compositions: toggle(prefs.compositions, c) })} />
              ))}
            </Chips>
          </>
        ) : (
          <Button label={t('premium.discover')} variant="secondary" onPress={() => router.push('/premium')} />
        )}
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
  stepper: { flexDirection: 'row', alignItems: 'center', gap: spacing.md },
  stepperValue: { minWidth: 40, textAlign: 'center', fontWeight: '700' },
});
