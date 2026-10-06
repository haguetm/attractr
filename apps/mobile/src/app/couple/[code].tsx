// Couple invitation link (attractr://couple/CODE). Path B: the partner signs up first
// (age, selfie, consents), then opens the link again to link both accounts.

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

export default function CoupleLinkScreen() {
  const { t } = useTranslation();
  const { code } = useLocalSearchParams<{ code: string }>();
  const { session, profile } = useSession();
  const [name, setName] = useState<string | null | undefined>(undefined);
  const [done, setDone] = useState(false);
  const { busy, error, run } = useSubmit();
  const onboarding = !profile || profile.status === 'onboarding';

  useEffect(() => {
    if (session) void api.previewCoupleInvitation(code).then((p) => setName(p?.first_name ?? null)).catch(() => setName(null));
  }, [code, session]);

  if (!session || onboarding) {
    return (
      <Screen title={t('couple.linkTitle')} footer={<Button label={t('common.continue')} onPress={() => router.replace('/')} />}>
        <Note>{t('couple.finishSignup')}</Note>
      </Screen>
    );
  }

  return (
    <Screen
      title={t('couple.linkTitle')}
      footer={
        done || name === null ? (
          <Button label={t('common.continue')} onPress={() => router.replace('/couple')} />
        ) : (
          <Button label={t('couple.accept')} onPress={() => run(async () => { await api.acceptCoupleInvitation(code); setDone(true); })} loading={busy} disabled={!name} />
        )
      }
    >
      {name ? <Text style={font.body}>{t('couple.linkBody', { name })}</Text> : null}
      {name === null ? <Note>{t('couple.linkInvalid')}</Note> : null}
      {done ? <Note>{t('couple.linkDone')}</Note> : null}
      <ErrorText message={error ? errorMessage(t, error) : null} />
    </Screen>
  );
}
