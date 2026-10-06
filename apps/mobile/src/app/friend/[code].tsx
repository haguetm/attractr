// Opened from a friend link (attractr://friend/CODE). Shows the owner's first name
// only, then creates the friendship once confirmed.

import { router, useLocalSearchParams } from 'expo-router';
import { useEffect, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { Text } from 'react-native';
import { Button, ErrorText, Note, Screen } from '../../components/ui';
import { useSession } from '../../features/session/SessionProvider';
import { api } from '../../lib/api';
import { errorMessage } from '../../lib/errors';
import { useSubmit } from '../../lib/useSubmit';
import { font } from '../../theme';

export default function FriendInviteScreen() {
  const { t } = useTranslation();
  const { code } = useLocalSearchParams<{ code: string }>();
  const { session } = useSession();
  const [name, setName] = useState<string | null | undefined>(undefined);
  const [done, setDone] = useState(false);
  const { busy, error, run } = useSubmit();

  useEffect(() => {
    if (!session) return;
    void api.previewFriendInvite(code).then((p) => setName(p?.first_name ?? null)).catch(() => setName(null));
  }, [code, session]);

  // Not signed in yet: sign in first, then open the link again.
  if (!session) {
    return (
      <Screen title={t('friendInvite.title')} footer={<Button label={t('common.continue')} onPress={() => router.replace('/')} />} />
    );
  }

  return (
    <Screen
      title={t('friendInvite.title')}
      footer={
        done || name === null ? (
          <Button label={t('common.continue')} onPress={() => router.replace('/friends')} />
        ) : (
          <Button label={t('friendInvite.accept')} onPress={() => run(async () => { await api.acceptFriendInvite(code); setDone(true); })} loading={busy} disabled={!name} />
        )
      }
    >
      {name ? <Text style={font.body}>{t('friendInvite.body', { name })}</Text> : null}
      {name === null ? <Note>{t('friendInvite.invalid')}</Note> : null}
      {done ? <Note>{t('friendInvite.done')}</Note> : null}
      <ErrorText message={error ? errorMessage(t, error) : null} />
    </Screen>
  );
}
