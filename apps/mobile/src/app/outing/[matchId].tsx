// The matched pair's view of their outing: details, participants, each side's
// invitations and answers; invite my friends; cancel. Logistics stay in the match chat.

import { outingState } from '@attractr/shared';
import { router, useFocusEffect, useLocalSearchParams } from 'expo-router';
import { useCallback, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { StyleSheet, Text, View } from 'react-native';
import { Button, Checkbox, ErrorText, Note, Screen, Section } from '../../components/ui';
import { api, type MatchOuting, type MyFriends } from '../../lib/api';
import { errorMessage } from '../../lib/errors';
import { formatDateTime } from '../../lib/format';
import { useSubmit } from '../../lib/useSubmit';
import { colors, font, radius, spacing } from '../../theme';

export default function MatchOutingScreen() {
  const { t } = useTranslation();
  const { matchId } = useLocalSearchParams<{ matchId: string }>();
  const [outing, setOuting] = useState<MatchOuting | null | undefined>(undefined);
  const [friends, setFriends] = useState<MyFriends | null>(null);
  const [selected, setSelected] = useState<string[]>([]);
  const { busy, error, run } = useSubmit();

  const load = useCallback(() => {
    void api.getMatchOuting(matchId).then(setOuting).catch(() => setOuting(null));
    void api.getMyFriends().then(setFriends).catch(() => undefined);
  }, [matchId]);
  useFocusEffect(load);

  if (outing === null) {
    return (
      <Screen title={t('outing.manageTitle')} footer={<Button label={t('outing.propose')} onPress={() => router.replace({ pathname: '/outing/new', params: { matchId } })} />} />
    );
  }
  if (!outing) return null;

  const state = outingState(outing.participants, outing.min_participants, outing.max_participants);
  const planned = outing.status === 'planned';
  const invitedIds = new Set(outing.invitations.map((i) => i.friend_id).filter(Boolean));
  const invitable = (friends?.friends ?? []).filter((f) => !invitedIds.has(f.id));

  const invite = () =>
    run(async () => {
      await api.inviteToOuting(outing.id, selected);
      setSelected([]);
      load();
    });

  const cancel = () =>
    run(async () => {
      await api.cancelOuting(outing.id);
      load();
    });

  return (
    <Screen
      title={t('outing.manageTitle')}
      footer={
        <>
          {planned ? <Button label={t('outing.cancel')} variant="danger" onPress={cancel} disabled={busy} /> : null}
          {outing.status === 'past' && !outing.my_feedback_given ? (
            <Button label={t('outing.feedback')} onPress={() => router.push({ pathname: '/outing/feedback', params: { outingId: outing.id } })} />
          ) : null}
          <Button label={t('common.back')} variant="ghost" onPress={() => router.back()} />
        </>
      }
    >
      <View style={styles.card}>
        <Text style={styles.when}>{formatDateTime(outing.starts_at)}</Text>
        <Text style={font.body}>{outing.place}</Text>
        <Text style={font.small}>{t('outing.participants', { count: outing.participants, max: outing.max_participants })}</Text>
      </View>
      {outing.status === 'cancelled' ? <Note>{t('outing.cancelled')}</Note> : null}
      {outing.status === 'past' ? <Note>{outing.my_feedback_given ? t('outing.feedbackGiven') : t('outing.past')}</Note> : null}
      {planned && state === 'waiting' ? <Note>{t('outing.waiting', { min: outing.min_participants })}</Note> : null}
      {planned && state === 'full' ? <Note>{t('outing.full')}</Note> : null}

      {outing.invitations.length ? (
        <Section title={t('outing.invited')}>
          {outing.invitations.map((i, index) => (
            <Text key={`${i.first_name}-${index}`} style={font.body}>
              {i.first_name} ({i.mine ? t('outing.yours') : t('outing.theirs')}) · {t(`outing.response.${i.response}`)}
            </Text>
          ))}
        </Section>
      ) : null}

      {planned && state !== 'full' ? (
        <Section title={t('outing.inviteFriends')}>
          {invitable.length === 0 ? <Note>{t('outing.noFriends')}</Note> : null}
          {invitable.map((f) => (
            <Checkbox
              key={f.id}
              label={f.first_name}
              checked={selected.includes(f.id)}
              onToggle={() => setSelected(selected.includes(f.id) ? selected.filter((x) => x !== f.id) : [...selected, f.id])}
            />
          ))}
          {invitable.length ? <Button label={t('outing.invite')} variant="secondary" onPress={invite} disabled={busy || selected.length === 0} /> : null}
        </Section>
      ) : null}

      <Note>{t('outing.logistics')}</Note>
      <ErrorText message={error ? errorMessage(t, error) : null} />
    </Screen>
  );
}

const styles = StyleSheet.create({
  card: { gap: spacing.xs, padding: spacing.md, borderRadius: radius.lg, backgroundColor: colors.white },
  when: { fontSize: 18, fontWeight: '700', color: colors.coral, textTransform: 'capitalize' },
});
