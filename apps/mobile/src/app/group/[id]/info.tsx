// Group details: members, newcomers to approve (first name and main photo only), invite a
// match, report or block a member (blocking makes you leave, Q17), leave the group.

import { Image } from 'expo-image';
import { router, useFocusEffect, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { avatarColor } from '../../../components/ProfileCardView';
import { Button, ErrorText, Note, Screen, Section } from '../../../components/ui';
import { api, type GroupDetail } from '../../../lib/api';
import { errorMessage } from '../../../lib/errors';
import { signedPhotoUrl } from '../../../lib/upload';
import { useSubmit } from '../../../lib/useSubmit';
import { colors, font, radius, spacing } from '../../../theme';

export default function GroupInfoScreen() {
  const { t } = useTranslation();
  const { id } = useLocalSearchParams<{ id: string }>();
  const [group, setGroup] = useState<GroupDetail | null>(null);
  const [candidates, setCandidates] = useState<{ id: string; first_name: string }[]>([]);
  const [confirmLeave, setConfirmLeave] = useState(false);
  const [note, setNote] = useState<string | null>(null);
  const { busy, error, run } = useSubmit();

  const load = useCallback(() => {
    void api.getGroup(id).then(setGroup).catch(() => router.dismissTo('/groups'));
    void api.getGroupInviteCandidates(id).then(setCandidates).catch(() => setCandidates([]));
  }, [id]);
  useFocusEffect(load);

  if (!group) return null;
  const full = group.members.length + group.invitations.length >= group.max_members;

  const act = (action: () => Promise<unknown>, done?: string) =>
    run(async () => {
      await action();
      setNote(done ?? null);
      load();
    });

  const leave = () =>
    run(async () => {
      await api.leaveGroup(group.id);
      router.dismissTo('/groups');
    });

  return (
    <Screen
      title={group.name}
      subtitle={t(`groups.kind.${group.kind}`)}
      footer={
        confirmLeave ? (
          <>
            <Note>{t('group.leaveConfirm')}</Note>
            <Button label={t('group.leave')} variant="danger" onPress={leave} loading={busy} />
            <Button label={t('common.cancel')} variant="ghost" onPress={() => setConfirmLeave(false)} />
          </>
        ) : (
          <>
            <Button label={t('group.leave')} variant="danger" onPress={() => setConfirmLeave(true)} />
            <Button label={t('common.back')} variant="ghost" onPress={() => router.back()} />
          </>
        )
      }
    >
      <Section title={t('group.members', { count: group.members.length, max: group.max_members })}>
        {group.members.map((m) => (
          <View key={m.id} style={styles.row}>
            <Avatar id={m.id} name={m.first_name} path={m.photo_path} />
            <Text style={[font.body, styles.flex]}>
              {m.first_name}{m.is_admin ? ` · ${t('group.admin')}` : ''}{m.me ? ` · ${t('group.you')}` : ''}
            </Text>
            {!m.me ? (
              <>
                <Pressable accessibilityRole="button" onPress={() => router.push({ pathname: '/report/[userId]', params: { userId: m.id, name: m.first_name, conversationId: group.conversation_id } })}>
                  <Text style={styles.link}>{t('group.report')}</Text>
                </Pressable>
                <Pressable accessibilityRole="button" onPress={() => run(async () => { await api.blockProfile(m.id); router.dismissTo('/groups'); })}>
                  <Text style={styles.link}>{t('group.block')}</Text>
                </Pressable>
              </>
            ) : null}
          </View>
        ))}
        <Note>{t('group.blockHint')}</Note>
      </Section>

      {group.invitations.length ? (
        <Section title={t('group.pending')}>
          {group.invitations.map((i) => (
            <View key={i.id} style={styles.card}>
              <View style={styles.row}>
                <Avatar id={i.id} name={i.first_name} path={i.photo_path} />
                <View style={styles.flex}>
                  <Text style={font.body}>{i.first_name}</Text>
                  <Text style={font.small}>{t('group.invitedBy', { name: i.invited_by })}{i.invitee_accepted ? '' : ` · ${t('group.waitingInvitee')}`}</Text>
                </View>
              </View>
              {i.can_vote ? (
                i.my_vote === null ? (
                  <View style={styles.actions}>
                    <View style={styles.flex}><Button label={t('group.approve')} onPress={() => act(() => api.voteGroupInvitation(i.id, true))} disabled={busy} /></View>
                    <View style={styles.flex}><Button label={t('group.reject')} variant="secondary" onPress={() => act(() => api.voteGroupInvitation(i.id, false))} disabled={busy} /></View>
                  </View>
                ) : (
                  <Note>{t('group.voted')}</Note>
                )
              ) : null}
            </View>
          ))}
        </Section>
      ) : null}

      {!full ? (
        <Section title={t('group.invite')}>
          <Note>{t(group.kind === 'romantic' ? 'group.inviteHintRomantic' : 'group.inviteHintFriends')}</Note>
          {candidates.length === 0 ? <Note>{t('group.noCandidates')}</Note> : null}
          {candidates.map((c) => (
            <Button key={c.id} label={`${t('group.invite')} : ${c.first_name}`} variant="secondary" onPress={() => act(() => api.inviteToGroup(group.id, c.id), t('group.inviteSent'))} disabled={busy} />
          ))}
          {note ? <Note>{note}</Note> : null}
        </Section>
      ) : null}

      <ErrorText message={error ? errorMessage(t, error) : null} />
    </Screen>
  );
}

function Avatar({ id, name, path }: { id: string; name: string; path: string | null }) {
  const [url, setUrl] = useState<string | null>(null);
  useEffect(() => {
    if (path) void signedPhotoUrl(path).then(setUrl);
  }, [path]);
  return url ? (
    <Image source={{ uri: url }} style={styles.avatar} contentFit="cover" />
  ) : (
    <View style={[styles.avatar, styles.initials, { backgroundColor: avatarColor(id) }]}>
      <Text style={styles.initialsText}>{name.slice(0, 1).toUpperCase()}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  flex: { flex: 1 },
  row: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
  card: { gap: spacing.sm, padding: spacing.sm, borderRadius: radius.md, backgroundColor: colors.white },
  actions: { flexDirection: 'row', gap: spacing.sm },
  link: { color: colors.coral, fontWeight: '600', marginLeft: spacing.sm },
  avatar: { width: 40, height: 40, borderRadius: 20 },
  initials: { alignItems: 'center', justifyContent: 'center' },
  initialsText: { color: colors.white, fontWeight: '800' },
});
