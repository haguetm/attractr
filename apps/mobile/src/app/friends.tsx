// Friends (spec §7): added by single-use link or by pseudo, never from the address
// book; accepted on both sides; verified accounts only; list visible to its owner.

import { router, useFocusEffect } from 'expo-router';
import { type ReactNode, useCallback, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { Share, StyleSheet, Text, View } from 'react-native';
import { Button, ErrorText, Field, Note, Screen, Section } from '../components/ui';
import { useSession } from '../features/session/SessionProvider';
import { api, type FriendSummary, type MyFriends } from '../lib/api';
import { errorMessage } from '../lib/errors';
import { friendInviteLink } from '../lib/format';
import { useSubmit } from '../lib/useSubmit';
import { colors, font, radius, spacing } from '../theme';

export default function FriendsScreen() {
  const { t } = useTranslation();
  const { profile } = useSession();
  const [data, setData] = useState<MyFriends | null>(null);
  const [username, setUsername] = useState('');
  const [toAdd, setToAdd] = useState('');
  const [note, setNote] = useState<string | null>(null);
  const { busy, error, run } = useSubmit();
  const verified = profile?.verification_status === 'verified';

  const load = useCallback(() => {
    void api.getMyFriends().then((d) => {
      setData(d);
      setUsername((current) => current || d.username || '');
    }).catch(() => undefined);
  }, []);
  useFocusEffect(load);

  const act = (action: () => Promise<unknown>, done?: string) =>
    run(async () => {
      await action();
      setNote(done ?? null);
      load();
    });

  const share = () =>
    run(async () => {
      const code = await api.createFriendInvite();
      await Share.share({ message: t('friends.shareMessage', { link: friendInviteLink(code) }) });
    });

  return (
    <Screen
      title={t('friends.title')}
      subtitle={t('friends.subtitle')}
      footer={<Button label={t('common.back')} variant="ghost" onPress={() => router.back()} />}
    >
      {!verified ? <Note>{t('friends.verificationNeeded')}</Note> : null}
      {data ? <Text style={font.small}>{t('friends.count', { count: data.friends.length, max: data.max })}</Text> : null}

      <Section title={t('friends.username')}>
        <Field value={username} onChangeText={setUsername} placeholder={t('friends.usernamePlaceholder')} autoCapitalize="none" maxLength={20} hint={t('friends.usernameHint')} />
        <Button label={t('friends.saveUsername')} variant="secondary" onPress={() => act(() => api.setUsername(username))} disabled={busy || username.trim().length < 3} />
      </Section>

      <Section title={t('friends.inviteLink')}>
        <Note>{t('friends.inviteLinkHint')}</Note>
        <Button label={t('friends.inviteLink')} onPress={share} disabled={busy || !verified} />
      </Section>

      <Section title={t('friends.addByUsername')}>
        <Field value={toAdd} onChangeText={setToAdd} placeholder={t('friends.addPlaceholder')} autoCapitalize="none" maxLength={20} />
        <Button
          label={t('friends.send')}
          variant="secondary"
          onPress={() => act(async () => { await api.requestFriend(toAdd); setToAdd(''); }, t('friends.requestSent'))}
          disabled={busy || !verified || toAdd.trim().length < 3}
        />
        {note ? <Note>{note}</Note> : null}
      </Section>

      {data?.incoming.length ? (
        <Section title={t('friends.incoming')}>
          {data.incoming.map((f) => (
            <FriendRow key={f.id} friend={f}>
              <Button label={t('friends.accept')} onPress={() => act(() => api.respondFriendRequest(f.id, true))} disabled={busy} />
              <Button label={t('friends.decline')} variant="ghost" onPress={() => act(() => api.respondFriendRequest(f.id, false))} disabled={busy} />
            </FriendRow>
          ))}
        </Section>
      ) : null}

      {data?.outgoing.length ? (
        <Section title={t('friends.outgoing')}>
          {data.outgoing.map((f) => <FriendRow key={f.id} friend={f} />)}
        </Section>
      ) : null}

      <Section title={t('friends.title')}>
        {data && data.friends.length === 0 ? <Note>{t('friends.empty')}</Note> : null}
        {data?.friends.map((f) => (
          <FriendRow key={f.id} friend={f}>
            <Button label={t('friends.remove')} variant="ghost" onPress={() => act(() => api.removeFriend(f.id))} disabled={busy} />
          </FriendRow>
        ))}
        <Note>{t('friends.noRules')}</Note>
      </Section>

      <ErrorText message={error ? errorMessage(t, error) : null} />
    </Screen>
  );
}

function FriendRow({ friend, children }: { friend: FriendSummary; children?: ReactNode }) {
  return (
    <View style={styles.row}>
      <View style={styles.flex}>
        <Text style={font.label}>{friend.first_name}</Text>
        {friend.username ? <Text style={font.small}>@{friend.username}</Text> : null}
      </View>
      {children}
    </View>
  );
}

const styles = StyleSheet.create({
  flex: { flex: 1 },
  row: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, padding: spacing.sm, borderRadius: radius.md, backgroundColor: colors.white },
});
