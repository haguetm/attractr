// Outing invitations received as a friend (spec §7): a card with the day, place,
// time and the two first names, "je viens" / "je ne viens pas". No profile access.

import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { StyleSheet, Text, View } from 'react-native';
import { Button, ErrorText, Note, Screen } from '../components/ui';
import { api, type OutingCard } from '../lib/api';
import { errorMessage } from '../lib/errors';
import { formatDateTime } from '../lib/format';
import { useSubmit } from '../lib/useSubmit';
import { colors, font, radius, spacing } from '../theme';

export default function OutingsScreen() {
  const { t } = useTranslation();
  const [cards, setCards] = useState<OutingCard[] | null>(null);
  const { busy, error, run } = useSubmit();

  const load = useCallback(() => {
    void api.getMyOutingInvitations().then(setCards).catch(() => setCards([]));
  }, []);
  useFocusEffect(load);

  const answer = (id: string, going: boolean) =>
    run(async () => {
      await api.respondToOuting(id, going);
      load();
    });

  return (
    <Screen title={t('outings.title')} footer={<Button label={t('common.back')} variant="ghost" onPress={() => router.back()} />}>
      {cards?.length === 0 ? <Note>{t('outings.empty')}</Note> : null}
      {cards?.map((c) => (
        <View key={c.outing_id} style={styles.card}>
          <Text style={font.label}>{t('outings.card', { a: c.matched_first_names[0], b: c.matched_first_names[1] })}</Text>
          <Text style={styles.when}>{formatDateTime(c.starts_at)}</Text>
          <Text style={font.body}>{c.place}</Text>
          <Text style={font.small}>
            {t('outings.invitedBy', { name: c.invited_by })} · {t('outings.participants', { count: c.participants })}
          </Text>
          {c.status === 'cancelled' ? (
            <Note>{t('outing.cancelled')}</Note>
          ) : c.status === 'past' ? (
            c.response === 'going' && !c.my_feedback_given ? (
              <Button label={t('outing.feedback')} variant="secondary" onPress={() => router.push({ pathname: '/outing/feedback', params: { outingId: c.outing_id } })} />
            ) : (
              <Note>{t('outing.past')}</Note>
            )
          ) : (
            <View style={styles.actions}>
              <View style={styles.flex}>
                <Button label={c.response === 'going' ? `✓ ${t('outings.youGo')}` : t('outings.going')} onPress={() => answer(c.outing_id, true)} disabled={busy || c.response === 'going'} />
              </View>
              <View style={styles.flex}>
                <Button label={c.response === 'not_going' ? t('outings.youDontGo') : t('outings.notGoing')} variant="secondary" onPress={() => answer(c.outing_id, false)} disabled={busy || c.response === 'not_going'} />
              </View>
            </View>
          )}
        </View>
      ))}
      <ErrorText message={error ? errorMessage(t, error) : null} />
    </Screen>
  );
}

const styles = StyleSheet.create({
  flex: { flex: 1 },
  card: { gap: spacing.sm, padding: spacing.md, borderRadius: radius.lg, backgroundColor: colors.white },
  when: { fontSize: 17, fontWeight: '700', color: colors.coral, textTransform: 'capitalize' },
  actions: { flexDirection: 'row', gap: spacing.sm },
});
