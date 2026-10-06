// Discovery feed (spec §4-5): only compatible profiles, one at a time. A like targets
// a photo or an answer; the main button likes the first photo (or answer).

import { timeLeft } from '@attractr/shared';
import { Image } from 'expo-image';
import { type Href, router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { ActivityIndicator, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { ProfileCardView } from '../components/ProfileCardView';
import { Button, ErrorText, Note } from '../components/ui';
import { useSession } from '../features/session/SessionProvider';
import { api, type Feed, type LikeQuota, type LikeTarget, type ProfileCard } from '../lib/api';
import { DEV_TOOLS_ENABLED } from '../lib/devTools';
import { errorCode, errorMessage } from '../lib/errors';
import { useSubmit } from '../lib/useSubmit';
import { colors, font, radius, spacing } from '../theme';

const defaultTarget = (card: ProfileCard): LikeTarget | null =>
  card.photos[0]
    ? { kind: 'photo', ref: card.photos[0].id }
    : card.prompts[0]
      ? { kind: 'prompt', ref: card.prompts[0].question_code }
      : null;

export default function FeedScreen() {
  const { t } = useTranslation();
  const { profile, refreshProfile } = useSession();
  const [feed, setFeed] = useState<Feed | null>(null);
  const [index, setIndex] = useState(0);
  const [quota, setQuota] = useState<LikeQuota | null>(null);
  const [unread, setUnread] = useState(0);
  const [loading, setLoading] = useState(true);
  const { busy, error, run, setError } = useSubmit();

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const [nextFeed, nextQuota, matches] = await Promise.all([api.getFeed(), api.getLikeQuota(), api.getMyMatches()]);
      setFeed(nextFeed);
      setQuota(nextQuota);
      setUnread(matches.reduce((sum, m) => sum + m.unread_count, 0));
      setIndex(0);
    } catch (e) {
      // Suspended (or paused/closed) meanwhile: let the entry gate pick the right screen.
      if (errorCode(e) === 'profile_not_active') {
        const p = await refreshProfile().catch(() => null);
        if (p?.status === 'suspended' || p?.status === 'closed') {
          router.replace('/suspended');
          return;
        }
      }
      setError(e);
    } finally {
      setLoading(false);
    }
  }, [setError, refreshProfile]);

  // Reload when coming back from search preferences, a chat or a match.
  useFocusEffect(
    useCallback(() => {
      void load();
    }, [load]),
  );

  const card = feed?.cards[index];
  const next = async () => {
    if (index + 1 < (feed?.cards.length ?? 0)) setIndex(index + 1);
    else await load();
  };

  const [canRewind, setCanRewind] = useState(false);

  const pass = () =>
    run(async () => {
      if (!card) return;
      await api.passProfile(card.id);
      setCanRewind(true);
      await next();
    });

  // Premium: bring back the last passed profile in front of the queue.
  const rewind = () =>
    run(async () => {
      const back = await api.rewindLastPass();
      setCanRewind(false);
      setFeed((f) => (f ? { ...f, cards: [back, ...f.cards.slice(index).filter((c) => c.id !== back.id)] } : f));
      setIndex(0);
    });

  const like = (target: LikeTarget | null) =>
    run(async () => {
      if (!card || !target) return;
      try {
        const result = await api.likeProfile(card.id, target);
        setQuota(result.quota);
        if (result.matched && result.match_id) {
          router.push({ pathname: '/match/[matchId]', params: { matchId: result.match_id, new: '1' } });
        }
        await next();
      } catch (e) {
        if (errorCode(e) === 'like_quota_reached') setQuota(await api.getLikeQuota());
        throw e;
      }
    });

  const quotaLeft = quota && !quota.unlimited ? quota : null;
  const outOfLikes = quotaLeft !== null && quotaLeft.remaining <= 0;
  const reset = quotaLeft?.next_reset_at ? timeLeft(quotaLeft.next_reset_at) : null;

  return (
    <SafeAreaView style={styles.safe} edges={['top']}>
      <View style={styles.header}>
        <Image source={require('../../assets/images/logo.png')} style={styles.logo} contentFit="contain" />
        <View style={styles.headerActions}>
          <HeaderLink label={t('feed.matches')} badge={unread} onPress={() => router.push('/matches')} />
          <HeaderLink label={t('feed.boost')} badge={profile?.boost_credits} onPress={() => router.push('/boost')} />
          <HeaderLink label={t('feed.search')} onPress={() => router.push('/search')} />
          <HeaderLink label={t('feed.settings')} onPress={() => router.push('/settings')} />
        </View>
      </View>

      {profile?.is_seed && DEV_TOOLS_ENABLED ? (
        <Pressable accessibilityRole="button" onPress={() => router.push('/dev/impersonate' as Href)} style={styles.testBanner}>
          <Text style={styles.testBannerText}>{t('feed.testBanner', { name: profile.first_name })}</Text>
          <Text style={[styles.testBannerText, styles.bold]}>{t('feed.switchProfile')}</Text>
        </Pressable>
      ) : null}

      <ScrollView contentContainerStyle={styles.content}>
        {loading ? (
          <ActivityIndicator color={colors.coral} style={styles.loader} />
        ) : card ? (
          <>
            {feed?.passport ? <Note>{t('feed.passport', { label: feed.passport })}</Note> : null}
            {feed?.widened && feed.radius_km ? <Note>{t('feed.widened', { km: feed.radius_km })}</Note> : null}
            <ProfileCardView
              card={card}
              alcoholFree={profile?.alcohol_free_icons ?? false}
              onLike={like}
              likeDisabled={busy || outOfLikes}
            />
            <Pressable
              accessibilityRole="button"
              onPress={() => router.push({ pathname: '/report/[userId]', params: { userId: card.id, name: card.first_name } })}
            >
              <Text style={[font.small, styles.center, styles.reportLink]}>{t('safety.reportOrBlock')}</Text>
            </Pressable>
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
        <View style={styles.footer}>
          <View style={styles.actions}>
            <View style={styles.flex}>
              <Button label={t('feed.pass')} variant="secondary" onPress={pass} disabled={busy} />
            </View>
            <View style={styles.flex}>
              <Button label={t('feed.like')} onPress={() => like(defaultTarget(card))} loading={busy} disabled={outOfLikes} />
            </View>
          </View>
          {canRewind && profile?.premium.active ? (
            <Button label={t('feed.rewind')} variant="ghost" onPress={rewind} disabled={busy} />
          ) : null}
          {outOfLikes && reset ? (
            <Text style={[font.small, styles.center]}>
              {t('feed.quotaReached', { hours: reset.hours, minutes: reset.minutes })} {t('feed.quotaPremium')}
            </Text>
          ) : quotaLeft ? (
            <Text style={[font.small, styles.center]}>{t('feed.likesLeft', { count: quotaLeft.remaining })}</Text>
          ) : null}
        </View>
      ) : null}
    </SafeAreaView>
  );
}

function HeaderLink({ label, onPress, badge }: { label: string; onPress: () => void; badge?: number }) {
  return (
    <Pressable accessibilityRole="button" onPress={onPress} hitSlop={8} style={styles.headerLinkRow}>
      <Text style={styles.headerLink}>{label}</Text>
      {badge ? <Text style={styles.badge}>{badge > 9 ? '9+' : badge}</Text> : null}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: colors.cream },
  flex: { flex: 1 },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: spacing.lg, paddingVertical: spacing.sm },
  logo: { width: 44, height: 44 },
  headerActions: { flexDirection: 'row', gap: spacing.md },
  headerLinkRow: { flexDirection: 'row', alignItems: 'center', gap: 4 },
  headerLink: { color: colors.navy, fontWeight: '700', fontSize: 15 },
  badge: { minWidth: 18, textAlign: 'center', fontSize: 11, fontWeight: '800', color: colors.white, backgroundColor: colors.coral, borderRadius: radius.pill, paddingHorizontal: 5, overflow: 'hidden' },
  testBanner: { flexDirection: 'row', justifyContent: 'space-between', marginHorizontal: spacing.lg, padding: spacing.sm, borderRadius: radius.sm, backgroundColor: colors.navy },
  testBannerText: { color: colors.white, fontSize: 13 },
  bold: { fontWeight: '700' },
  content: { padding: spacing.lg, gap: spacing.md, paddingBottom: spacing.xl },
  loader: { marginTop: spacing.xl },
  center: { textAlign: 'center' },
  reportLink: { textDecorationLine: 'underline' },
  waiting: { alignItems: 'center', gap: spacing.md, marginTop: spacing.xl },
  footer: { paddingHorizontal: spacing.lg, paddingTop: spacing.sm, paddingBottom: spacing.md, gap: spacing.xs },
  actions: { flexDirection: 'row', gap: spacing.md },
});
