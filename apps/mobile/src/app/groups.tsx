// My group chats and the invitations I received (spec §8). Invitation only: there is no
// public group and no group search.

import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { Button, ErrorText, Note, Screen, Section } from '../components/ui';
import { useSession } from '../features/session/SessionProvider';
import { api, type GroupInvitationCard, type GroupSummary } from '../lib/api';
import { errorMessage } from '../lib/errors';
import { useSubmit } from '../lib/useSubmit';
import { colors, font, radius, spacing } from '../theme';

export default function GroupsScreen() {
  const { t } = useTranslation();
  const { profile } = useSession();
  const [groups, setGroups] = useState<GroupSummary[] | null>(null);
  const [invitations, setInvitations] = useState<GroupInvitationCard[]>([]);
  const [note, setNote] = useState<string | null>(null);
  const { busy, error, run } = useSubmit();

  const load = useCallback(() => {
    void api.getMyGroups().then(setGroups).catch(() => setGroups([]));
    void api.getMyGroupInvitations().then(setInvitations).catch(() => undefined);
  }, []);
  useFocusEffect(load);

  const respond = (id: string, accept: boolean) =>
    run(async () => {
      const outcome = await api.respondGroupInvitation(id, accept);
      setNote(outcome === 'joined' ? t('groups.joined') : outcome === 'waiting_for_group' ? t('groups.waiting') : outcome === 'declined' ? null : t('groups.cancelled'));
      load();
    });

  return (
    <Screen
      title={t('groups.title')}
      subtitle={t('groups.subtitle')}
      footer={
        <>
          <Button
            label={profile?.premium.active ? t('groups.create') : t('groups.createPremium')}
            onPress={() => router.push(profile?.premium.active ? '/group/new' : '/premium')}
          />
          <Button label={t('common.back')} variant="ghost" onPress={() => router.back()} />
        </>
      }
    >
      {invitations.length ? (
        <Section title={t('groups.invitations')}>
          {invitations.map((inv) => (
            <View key={inv.id} style={styles.card}>
              <Text style={font.label}>{t('groups.invitationCard', { name: inv.invited_by.first_name, group: inv.name })}</Text>
              <Text style={font.small}>
                {t(`groups.kind.${inv.kind}`)} · {t('groups.invitationMembers', { count: inv.size, names: inv.member_first_names.join(', ') })}
              </Text>
              {inv.invited_by.match_id ? (
                <Pressable accessibilityRole="button" onPress={() => router.push({ pathname: '/match/[matchId]', params: { matchId: inv.invited_by.match_id! } })}>
                  <Text style={styles.link}>{t('groups.seeInviter', { name: inv.invited_by.first_name })}</Text>
                </Pressable>
              ) : null}
              {inv.accepted ? (
                <Note>{t('groups.waiting')}</Note>
              ) : (
                <View style={styles.actions}>
                  <View style={styles.flex}><Button label={t('groups.join')} onPress={() => respond(inv.id, true)} disabled={busy} /></View>
                  <View style={styles.flex}><Button label={t('groups.decline')} variant="secondary" onPress={() => respond(inv.id, false)} disabled={busy} /></View>
                </View>
              )}
            </View>
          ))}
        </Section>
      ) : null}
      {note ? <Note>{note}</Note> : null}

      {groups?.length === 0 ? <Note>{t('groups.empty')}</Note> : null}
      {groups?.map((g) => (
        <Pressable key={g.id} accessibilityRole="button" onPress={() => router.push({ pathname: '/group/[id]', params: { id: g.id } })} style={styles.card}>
          <View style={styles.row}>
            <Text style={[font.label, styles.flex]}>{g.name}</Text>
            {g.unread_count ? <Text style={styles.badge}>{g.unread_count}</Text> : null}
          </View>
          <Text style={font.small}>
            {t(`groups.kind.${g.kind}`)} · {t('groups.members', { count: g.members })}
            {g.pending_votes ? ` · ${t('groups.pendingVotes', { count: g.pending_votes })}` : ''}
          </Text>
          {g.last_message ? <Text numberOfLines={1} style={font.small}>{g.last_message.sender} : {g.last_message.body}</Text> : null}
        </Pressable>
      ))}
      <ErrorText message={error ? errorMessage(t, error) : null} />
    </Screen>
  );
}

const styles = StyleSheet.create({
  flex: { flex: 1 },
  card: { gap: spacing.xs, padding: spacing.md, borderRadius: radius.md, backgroundColor: colors.white },
  row: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
  actions: { flexDirection: 'row', gap: spacing.sm },
  link: { color: colors.coral, fontWeight: '600' },
  badge: { fontSize: 12, fontWeight: '700', color: colors.white, backgroundColor: colors.coral, paddingHorizontal: 8, paddingVertical: 2, borderRadius: radius.pill, overflow: 'hidden' },
});
