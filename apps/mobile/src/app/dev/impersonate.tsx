// "Tester en tant que" (spec §13): sign in as a seed profile to see its feed.
// Development only: hidden from production builds, refused by the server elsewhere.

import { ageOn } from '@attractr/shared';
import { Redirect, router } from 'expo-router';
import { useEffect, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { ActivityIndicator, StyleSheet, Text, View } from 'react-native';
import { DrinkIcon } from '../../components/DrinkIcon';
import { Button, Choice, ErrorText, Note, Screen, Section } from '../../components/ui';
import { useSession } from '../../features/session/SessionProvider';
import { api, type SeedProfileSummary } from '../../lib/api';
import { DEV_TOOLS_ENABLED } from '../../lib/devTools';
import { errorMessage } from '../../lib/errors';
import { supabase } from '../../lib/supabase';
import { useSubmit } from '../../lib/useSubmit';
import { colors } from '../../theme';

const CITY_BY_DEPARTMENT: Record<string, string> = {
  '75': 'Paris', '13': 'Marseille', '69': 'Lyon', '31': 'Toulouse', '06': 'Nice',
  '44': 'Nantes', '34': 'Montpellier', '67': 'Strasbourg', '33': 'Bordeaux', '59': 'Lille',
};

export default function ImpersonateScreen() {
  const { t } = useTranslation();
  const { refreshProfile } = useSession();
  const [profiles, setProfiles] = useState<SeedProfileSummary[] | null>(null);
  const { busy, error, run, setError } = useSubmit();

  useEffect(() => {
    if (!DEV_TOOLS_ENABLED) return;
    api.devListSeedProfiles().then((r) => setProfiles(r.profiles)).catch((e) => {
      setProfiles([]);
      setError(e);
    });
  }, [setError]);

  if (!DEV_TOOLS_ENABLED) return <Redirect href="/" />;

  const loginAs = (id: string) =>
    run(async () => {
      const { tokenHash } = await api.devImpersonate(id);
      const { error: otpError } = await supabase.auth.verifyOtp({ token_hash: tokenHash, type: 'email' });
      if (otpError) throw otpError;
      await refreshProfile();
      router.replace('/');
    });

  const byCity = new Map<string, SeedProfileSummary[]>();
  for (const p of profiles ?? []) {
    const city = CITY_BY_DEPARTMENT[p.departmentCode ?? ''] ?? p.departmentCode ?? '?';
    byCity.set(city, [...(byCity.get(city) ?? []), p]);
  }

  return (
    <Screen
      title={t('dev.title')}
      subtitle={t('dev.subtitle')}
      footer={<Button label={t('common.back')} variant="ghost" onPress={() => router.back()} />}
    >
      {profiles === null ? <ActivityIndicator color={colors.coral} /> : null}
      {profiles?.length === 0 && error ? <Note>{t('dev.unavailable')}</Note> : null}
      {[...byCity.entries()].map(([city, list]) => (
        <Section key={city} title={city}>
          {list.map((p) => (
            <Choice
              key={p.id}
              label={`${p.firstName}, ${ageOn(p.birthDate, new Date())} · ${t(`gender.${p.gender}`)}`}
              description={p.verified ? t('dev.verified') : t('dev.pending')}
              selected={false}
              disabled={busy}
              onPress={() => loginAs(p.id)}
              leading={
                <View style={styles.drinks}>
                  {p.drinks.map((d) => <DrinkIcon key={d} drink={d} size={18} />)}
                </View>
              }
            />
          ))}
        </Section>
      ))}
      {busy ? <Text>{t('common.loading')}</Text> : null}
      <ErrorText message={error ? errorMessage(t, error) : null} />
    </Screen>
  );
}

const styles = StyleSheet.create({ drinks: { flexDirection: 'row' } });
