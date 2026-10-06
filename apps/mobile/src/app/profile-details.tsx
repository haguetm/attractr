// Optional profile details used by the Premium filters: education, height, interests.

import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { Text, View } from 'react-native';
import { Button, Chip, Chips, ErrorText, Screen, Section } from '../components/ui';
import { useSession } from '../features/session/SessionProvider';
import { api, EDUCATION_LEVELS, type EducationLevel } from '../lib/api';
import { errorMessage } from '../lib/errors';
import { supabase } from '../lib/supabase';
import { useSubmit } from '../lib/useSubmit';
import { font, spacing } from '../theme';

const MAX_INTERESTS = 5;

export default function ProfileDetailsScreen() {
  const { t } = useTranslation();
  const { profile, refreshProfile } = useSession();
  const [education, setEducation] = useState<EducationLevel | null>(profile?.education_level ?? null);
  const [height, setHeight] = useState<number | null>(profile?.height_cm ?? null);
  const [interests, setInterests] = useState<string[]>(profile?.interests ?? []);
  const [catalog, setCatalog] = useState<string[]>([]);
  const { busy, error, run } = useSubmit();

  useFocusEffect(useCallback(() => {
    void supabase.from('interests').select('code').eq('active', true).order('sort_order')
      .then(({ data }) => setCatalog((data ?? []).map((r) => r.code as string)));
  }, []));

  const toggle = (code: string) =>
    setInterests(interests.includes(code) ? interests.filter((i) => i !== code) : interests.length < MAX_INTERESTS ? [...interests, code] : interests);

  const save = () =>
    run(async () => {
      await api.setDetails(education, height, interests);
      await refreshProfile();
      router.back();
    });

  return (
    <Screen
      title={t('details.title')}
      subtitle={t('details.subtitle')}
      footer={
        <>
          <Button label={t('details.save')} onPress={save} loading={busy} />
          <Button label={t('common.cancel')} variant="ghost" onPress={() => router.back()} />
        </>
      }
    >
      <Section title={t('details.education')}>
        <Chips>
          {EDUCATION_LEVELS.map((e) => (
            <Chip key={e} label={t(`details.educationLevels.${e}`)} selected={education === e} onPress={() => setEducation(education === e ? null : e)} />
          ))}
        </Chips>
      </Section>
      <Section title={t('details.height')}>
        <View style={{ flexDirection: 'row', alignItems: 'center', gap: spacing.md }}>
          <Chip label="−" selected={false} onPress={() => setHeight(Math.max(120, (height ?? 170) - 1))} />
          <Text style={[font.body, { minWidth: 90, textAlign: 'center' }]}>{height ? t('details.heightValue', { cm: height }) : t('details.noHeight')}</Text>
          <Chip label="+" selected={false} onPress={() => setHeight(Math.min(230, (height ?? 169) + 1))} />
          {height ? <Chip label="✕" selected={false} onPress={() => setHeight(null)} /> : null}
        </View>
      </Section>
      <Section title={t('details.interests')}>
        <Chips>
          {catalog.map((code) => (
            <Chip key={code} label={t(`details.interestLabels.${code}`)} selected={interests.includes(code)} onPress={() => toggle(code)} />
          ))}
        </Chips>
      </Section>
      <ErrorText message={error ? errorMessage(t, error) : null} />
    </Screen>
  );
}
