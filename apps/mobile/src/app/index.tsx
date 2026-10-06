// Entry gate: sends the user to login, to the onboarding screen to resume, or home.

import { resumeStep } from '@attractr/shared';
import { Image } from 'expo-image';
import { type Href, Redirect } from 'expo-router';
import { useEffect, useState } from 'react';
import { ActivityIndicator, StyleSheet, View } from 'react-native';
import { progressFromProfile, stepPath } from '../features/onboarding/routes';
import { useSession } from '../features/session/SessionProvider';
import { api } from '../lib/api';
import { colors } from '../theme';

export default function Index() {
  const { session, profile, loading, refreshProfile } = useSession();
  const [target, setTarget] = useState<Href | null>(null);

  useEffect(() => {
    if (loading) return;
    if (!session) {
      setTarget('/phone');
      return;
    }
    let cancelled = false;
    (async () => {
      const p = profile ?? (await refreshProfile());
      if (!p || cancelled) return;
      const minPhotos = await api.configInt('photos.min_count').catch(() => 2);
      const step = resumeStep(progressFromProfile(p, minPhotos));
      if (!cancelled) setTarget(step === 'done' ? '/feed' : (stepPath(step) as Href));
    })().catch(() => setTarget('/phone'));
    return () => {
      cancelled = true;
    };
  }, [loading, session, profile, refreshProfile]);

  if (target) return <Redirect href={target} />;
  return (
    <View style={styles.container}>
      <Image source={require('../../assets/images/logo.png')} style={styles.logo} contentFit="contain" />
      <ActivityIndicator color={colors.coral} />
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: colors.cream, gap: 24 },
  logo: { width: 180, height: 180 },
});
