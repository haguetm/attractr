// Discovery feed (spec §4): only compatible profiles, one at a time. Likes come in
// phase 4; "Passer" hides a profile for feed.pass_recycle_days.

import { Image } from 'expo-image';
import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { ActivityIndicator, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { ProfileCardView } from '../components/ProfileCardView';
import { Button, ErrorText, Note } from '../components/ui';
import { useSession } from '../features/session/SessionProvider';
import { api, type Feed } from '../lib/api';
import { DEV_TOOLS_ENABLED } from '../lib/devTools';
import { errorMessage } from '../lib/errors';
import { useSubmit } from '../lib/useSubmit';
import { colors, font, radius, spacing } from '../theme';

export default function FeedScreen() {
  const { t } = useTranslation();
  const { profile } = useSession();
  const [feed, setFeed] = useState<Feed | null>(null);
  const [index, setIndex] = useState(0);
  const [loading, setLoading] = useState(true);
  const { busy, error, run, setError } = useSubmit();

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      setFeed(await api.getFeed());
      setIndex(0);
    } catch (e) {
      setError(e);
    } finally {
      setLoading(false);
    }
  }, [setError]);

  // Reload when coming back from the search preferences.
  useFocusEffect(
    useCallback(() => {
      void load();
    }, [load]),
  );

  const card = feed?.cards[index];

  const pass = () =>
    run(async () => {
      if (!card) return;
      await api.passProfile(card.id);
      if (index + 1 < (feed?.cards.length ?? 0)) setIndex(index + 1);
      else await load();
    });

  return (
    <SafeAreaView style={styles.safe} edges={['top']}>
      <View style={styles.header}>
        <Image source={require('../../assets/images/logo.png')} style={styles.logo} contentFit="contain" />
        <View style={styles.headerActions}>
          <HeaderLink label={t('feed.search')} onPress={() => router.push('/search')} />
          <HeaderLink label={t('feed.settings')} onPress={() => router.push('/settings')} />
        </View>
      </View>

      {profile?.is_seed && DEV_TOOLS_ENABLED ? (
        <Pressable accessibilityRole="button" onPress={() => router.push('/dev/impersonate')} style={styles.testBanner}>
          <Text style={styles.testBannerText}>{t('feed.testBanner', { name: profile.first_name })}</Text>
          <Text style={[styles.testBannerText, styles.bold]}>{t('feed.switchProfile')}</Text>
        </Pressable>
      ) : null}

      <ScrollView contentContainerStyle={styles.content}>
        {loading ? (
          <ActivityIndicator color={colors.coral} style={styles.loader} />
        ) : card ? (
          <>
            {feed?.widened && feed.radius_km ? <Note>{t('feed.widened', { km: feed.radius_km })}</Note> : null}
            <ProfileCardView card={card} alcoholFree={profile?.alcohol_free_icons ?? false} />
            <Text style={[font.small, styles.center]}>{t('feed.disclaimer')}</Text>
          </>
        ) : !error ? (
          <View style={styles.waiting}>
            <Text style={font.title}>{t('feed.waitingTitle')}</Text>
            <Text style={[font.subtitle, styles.center]}>{t('feed.waitingBody')}</Text>
            <Button label={t('feed.refresh')} variant="secondary" onPress={() => void load()} />
          </View>
        ) : null}
        <ErrorText message={error ? errorMessage(t, error) : null} />
      </ScrollView>

      {card ? (
        <View style={styles.actions}>
          <View style={styles.flex}>
            <Button label={t('feed.pass')} variant="secondary" onPress={pass} loading={busy} />
          </View>
          <View style={styles.flex}>
            <Button label={t('feed.like')} onPress={() => undefined} disabled />
          </View>
        </View>
      ) : null}
      {card ? <Text style={[font.small, styles.center, styles.likeSoon]}>{t('feed.likeSoon')}</Text> : null}
    </SafeAreaView>
  );
}

function HeaderLink({ label, onPress }: { label: string; onPress: () => void }) {
  return (
    <Pressable accessibilityRole="button" onPress={onPress} hitSlop={8}>
      <Text style={styles.headerLink}>{label}</Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: colors.cream },
  flex: { flex: 1 },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: spacing.lg, paddingVertical: spacing.sm },
  logo: { width: 44, height: 44 },
  headerActions: { flexDirection: 'row', gap: spacing.lg },
  headerLink: { color: colors.navy, fontWeight: '700', fontSize: 15 },
  testBanner: { flexDirection: 'row', justifyContent: 'space-between', marginHorizontal: spacing.lg, padding: spacing.sm, borderRadius: radius.sm, backgroundColor: colors.navy },
  testBannerText: { color: colors.white, fontSize: 13 },
  bold: { fontWeight: '700' },
  content: { padding: spacing.lg, gap: spacing.md, paddingBottom: spacing.xl },
  loader: { marginTop: spacing.xl },
  center: { textAlign: 'center' },
  waiting: { alignItems: 'center', gap: spacing.md, marginTop: spacing.xl },
  actions: { flexDirection: 'row', gap: spacing.md, paddingHorizontal: spacing.lg, paddingTop: spacing.sm },
  likeSoon: { paddingBottom: spacing.md, paddingTop: spacing.xs },
});
