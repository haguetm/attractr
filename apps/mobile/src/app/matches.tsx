// Open matches, most recent activity first, with the 24 h countdown for matches
// that have no message yet. Free users only learn that likes are waiting (spec §10).

import { isUrgent, timeLeft } from '@attractr/shared';
import { Image } from 'expo-image';
import { router, useFocusEffect } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { ActivityIndicator, Pressable, StyleSheet, Text, View } from 'react-native';
import { avatarColor } from '../components/ProfileCardView';
import { Button, ErrorText, Note, Screen } from '../components/ui';
import { useSession } from '../features/session/SessionProvider';
import { api, type MatchSummary } from '../lib/api';
import { errorMessage } from '../lib/errors';
import { supabase } from '../lib/supabase';
import { colors, font, radius, spacing } from '../theme';

export default function MatchesScreen() {
  const { t } = useTranslation();
  const premium = !!useSession().profile?.premium.active;
  const [matches, setMatches] = useState<MatchSummary[] | null>(null);
  const [likesWaiting, setLikesWaiting] = useState(0);
  const [outingCards, setOutingCards] = useState(0);
  const [error, setError] = useState<unknown>(null);

  const load = useCallback(async () => {
    try {
      const [list, count, cards] = await Promise.all([api.getMyMatches(), api.getLikesReceivedCount(), api.getMyOutingInvitations()]);
      setMatches(list);
      setLikesWaiting(count);
      setOutingCards(cards.filter((c) => c.status === 'planned').length);
    } catch (e) {
      setError(e);
    }
  }, []);

  useFocusEffect(
    useCallback(() => {
      void load();
    }, [load]),
  );

  // New messages and matches refresh the list (RLS limits events to the user's rows).
  useEffect(() => {
    const channel = supabase
      .channel('matches-list')
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'messages' }, () => void load())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'matches' }, () => void load())
      .subscribe();
    return () => {
      void supabase.removeChannel(channel);
    };
  }, [load]);

  return (
    <Screen title={t('matches.title')} footer={<Button label={t('common.back')} variant="ghost" onPress={() => router.back()} />}>
      {likesWaiting > 0 ? (
        <View style={styles.likes}>
          <Text style={font.label}>{t('matches.likesReceived')}</Text>
          <Text style={font.small}>{t('matches.likesReceivedHint')}</Text>
          <Button label={t('matches.seeLikes')} variant="secondary" onPress={() => router.push(premium ? '/likes' : '/premium')} />
        </View>
      ) : null}

      <Button label={t('matches.groups')} variant="secondary" onPress={() => router.push('/groups')} />

      {outingCards > 0 ? (
        <Button label={`${t('outings.link')} (${outingCards})`} variant="secondary" onPress={() => router.push('/outings')} />
      ) : null}

      {matches === null && !error ? <ActivityIndicator color={colors.coral} /> : null}
      {matches?.length === 0 ? (
        <>
          <Note>{t('matches.empty')}</Note>
          <Button label={t('matches.backToFeed')} variant="secondary" onPress={() => router.back()} />
        </>
      ) : null}

      {matches?.map((m) => <MatchRow key={m.match_id} match={m} />)}
      <ErrorText message={error ? errorMessage(t, error) : null} />
    </Screen>
  );
}

function MatchRow({ match }: { match: MatchSummary }) {
  const { t } = useTranslation();
  const [photoUrl, setPhotoUrl] = useState<string | null>(null);

  useEffect(() => {
    if (!match.other.photo_path) return;
    void supabase.storage.from('photos').createSignedUrl(match.other.photo_path, 3600)
      .then(({ data }) => setPhotoUrl(data?.signedUrl ?? null));
  }, [match.other.photo_path]);

  const left = match.first_message_deadline ? timeLeft(match.first_message_deadline) : null;
  const subtitle = left
    ? t('matches.timeLeft', { hours: left.hours, minutes: left.minutes })
    : match.last_message
      ? match.last_message.mine ? t('matches.you', { body: match.last_message.body }) : match.last_message.body
      : t('matches.newMatch');

  return (
    <Pressable
      accessibilityRole="button"
      onPress={() => router.push({ pathname: '/chat/[conversationId]', params: { conversationId: match.conversation_id, matchId: match.match_id } })}
      style={styles.row}
    >
      {photoUrl ? (
        <Image source={{ uri: photoUrl }} style={styles.avatar} contentFit="cover" />
      ) : (
        <View style={[styles.avatar, styles.initialsBox, { backgroundColor: avatarColor(match.other.id) }]}>
          <Text style={styles.initials}>{match.other.first_name.slice(0, 1).toUpperCase()}</Text>
        </View>
      )}
      <View style={styles.rowText}>
        <Text style={font.label}>{match.other.first_name}, {match.other.age}</Text>
        <Text numberOfLines={1} style={[font.small, left && isUrgent(left) ? styles.urgent : null]}>{subtitle}</Text>
      </View>
      {match.unread_count > 0 ? (
        <Text style={styles.unread}>{t('matches.unread', { count: match.unread_count })}</Text>
      ) : match.my_turn ? (
        <Text style={styles.turn}>{t('matches.yourTurn')}</Text>
      ) : null}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  likes: { padding: spacing.md, borderRadius: radius.md, backgroundColor: colors.coralSoft, gap: 4 },
  row: { flexDirection: 'row', alignItems: 'center', gap: spacing.md, padding: spacing.sm, borderRadius: radius.md, backgroundColor: colors.white },
  avatar: { width: 56, height: 56, borderRadius: 28 },
  initialsBox: { alignItems: 'center', justifyContent: 'center' },
  initials: { color: colors.white, fontWeight: '800', fontSize: 22 },
  rowText: { flex: 1, gap: 2 },
  urgent: { color: colors.coral, fontWeight: '600' },
  unread: { fontSize: 12, fontWeight: '700', color: colors.white, backgroundColor: colors.coral, paddingHorizontal: 8, paddingVertical: 3, borderRadius: radius.pill, overflow: 'hidden' },
  turn: { fontSize: 12, fontWeight: '700', color: colors.navy },
});
