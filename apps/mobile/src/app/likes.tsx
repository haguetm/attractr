// Who liked you (Premium, spec §10): verified profiles waiting for an answer.

import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { StyleSheet, Text, View } from 'react-native';
import { ProfileCardView } from '../components/ProfileCardView';
import { Button, ErrorText, Note, Screen } from '../components/ui';
import { useSession } from '../features/session/SessionProvider';
import { api, type LikeReceived, type LikeTarget } from '../lib/api';
import { errorMessage } from '../lib/errors';
import { useSubmit } from '../lib/useSubmit';
import { font, spacing } from '../theme';

export default function LikesScreen() {
  const { t } = useTranslation();
  const { profile } = useSession();
  const [likes, setLikes] = useState<LikeReceived[] | null>(null);
  const { busy, error, run, setError } = useSubmit();

  const load = useCallback(() => {
    void api.getLikesReceived().then(setLikes).catch((e) => {
      setLikes([]);
      setError(e);
    });
  }, [setError]);
  useFocusEffect(load);

  const likeBack = (card: LikeReceived, target?: LikeTarget) =>
    run(async () => {
      const t0 = target ?? (card.photos[0] ? { kind: 'photo' as const, ref: card.photos[0].id } : { kind: 'prompt' as const, ref: card.prompts[0]!.question_code });
      const result = await api.likeProfile(card.id, t0);
      if (result.match_id) router.push({ pathname: '/match/[matchId]', params: { matchId: result.match_id, new: '1' } });
      load();
    });

  const pass = (card: LikeReceived) =>
    run(async () => {
      await api.passProfile(card.id);
      load();
    });

  if (profile && !profile.premium.active) {
    return (
      <Screen title={t('likes.title')} footer={<Button label={t('premium.discover')} onPress={() => router.replace('/premium')} />}>
        <Note>{t('premium.locked')}</Note>
      </Screen>
    );
  }

  return (
    <Screen title={t('likes.title')} subtitle={t('likes.subtitle')} footer={<Button label={t('common.back')} variant="ghost" onPress={() => router.back()} />}>
      {likes?.length === 0 && !error ? <Note>{t('likes.empty')}</Note> : null}
      {likes?.map((card) => (
        <View key={card.id} style={styles.item}>
          <Text style={font.small}>{t(card.liked_target.kind === 'photo' ? 'likes.likedPhoto' : 'likes.likedAnswer')}</Text>
          <ProfileCardView card={card} alcoholFree={profile?.alcohol_free_icons ?? false} onLike={(target) => likeBack(card, target)} likeDisabled={busy} />
          <View style={styles.actions}>
            <View style={styles.flex}><Button label={t('likes.pass')} variant="secondary" onPress={() => pass(card)} disabled={busy} /></View>
            <View style={styles.flex}><Button label={t('likes.likeBack')} onPress={() => likeBack(card)} disabled={busy} /></View>
          </View>
        </View>
      ))}
      <ErrorText message={error ? errorMessage(t, error) : null} />
    </Screen>
  );
}

const styles = StyleSheet.create({
  flex: { flex: 1 },
  item: { gap: spacing.sm, marginBottom: spacing.lg },
  actions: { flexDirection: 'row', gap: spacing.sm },
});
