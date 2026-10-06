// Settings: search preferences, pause mode, blocking (contacts, blocked list),
// compliance actions (withdraw sensitive-data consent, delete account), sign out,
// and development tools in dev builds.

import { contactDigestInput } from '@attractr/shared';
import { Contact, ContactField, requestPermissionsAsync } from 'expo-contacts';
import { CryptoDigestAlgorithm, digestStringAsync } from 'expo-crypto';
import { type Href, router } from 'expo-router';
import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import { Button, ErrorText, Note, Screen, Section } from '../components/ui';
import { useSession } from '../features/session/SessionProvider';
import { api } from '../lib/api';
import { DEV_TOOLS_ENABLED } from '../lib/devTools';
import { errorMessage } from '../lib/errors';
import { useSubmit } from '../lib/useSubmit';

type Pending = 'withdraw' | 'delete' | null;

/** SHA-256 of each contact number (E.164 digits), computed on the device (Q23). */
async function contactDigests(): Promise<string[] | null> {
  const permission = await requestPermissionsAsync();
  if (!permission.granted) return null;
  const contacts = await Contact.getAllDetails([ContactField.PHONES]);
  const inputs = new Set<string>();
  for (const c of contacts) {
    for (const phone of c.phones ?? []) {
      const input = phone.number ? contactDigestInput(phone.number) : null;
      if (input) inputs.add(input);
    }
  }
  return Promise.all([...inputs].slice(0, 5000).map((s) => digestStringAsync(CryptoDigestAlgorithm.SHA256, s)));
}

export default function SettingsScreen() {
  const { t } = useTranslation();
  const { profile, refreshProfile, signOut } = useSession();
  const [confirming, setConfirming] = useState<Pending>(null);
  const [note, setNote] = useState<string | null>(null);
  const { busy, error, run } = useSubmit();
  const paused = profile?.status === 'paused';

  const confirm = () =>
    run(async () => {
      if (confirming === 'withdraw') {
        await api.withdrawConsent('sensitive_data');
        await refreshProfile();
      } else if (confirming === 'delete') {
        await api.deleteAccount();
        await signOut();
        router.replace('/');
      }
      setConfirming(null);
    });

  const togglePause = () =>
    run(async () => {
      await api.setPaused(!paused);
      await refreshProfile();
    });

  const blockContacts = () =>
    run(async () => {
      const digests = await contactDigests();
      if (!digests) {
        setNote(t('settings.contactsPermission'));
        return;
      }
      await api.blockContacts(digests);
      setNote(t('settings.contactsDone'));
    });

  const leave = () =>
    run(async () => {
      await signOut();
      router.replace('/');
    });

  return (
    <Screen title={t('settings.title')} footer={<Button label={t('common.back')} variant="ghost" onPress={() => router.back()} />}>
      {profile?.warnings ? <Note>{t('settings.warning')}</Note> : null}
      {profile?.verification_status === 'pending' ? <Note>{t('settings.pendingVerification')}</Note> : null}

      <Button label={t('settings.premium')} onPress={() => router.push('/premium')} />
      <Button label={t('settings.searchPreferences')} variant="secondary" onPress={() => router.push('/search')} />
      <Button label={t('settings.details')} variant="secondary" onPress={() => router.push('/profile-details')} />
      <Button label={t('settings.referral')} variant="secondary" onPress={() => router.push('/referral')} />
      {profile?.premium.active ? (
        <Button label={t('settings.stats')} variant="secondary" onPress={() => router.push('/stats')} />
      ) : null}
      <Button label={t('settings.friends')} variant="secondary" onPress={() => router.push('/friends')} />
      <Button label={t('settings.groups')} variant="secondary" onPress={() => router.push('/groups')} />
      <Button label={t('settings.outings')} variant="secondary" onPress={() => router.push('/outings')} />

      {profile?.premium.active ? (
        <Section title={t('settings.incognito')}>
          <Note>{t('settings.incognitoHint')}</Note>
          <Button
            label={profile.incognito ? t('settings.incognitoOff') : t('settings.incognitoOn')}
            variant="secondary"
            onPress={() => run(async () => { await api.setIncognito(!profile.incognito); await refreshProfile(); })}
            disabled={busy}
          />
        </Section>
      ) : null}

      <Section title={t('settings.pause')}>
        <Note>{paused ? t('settings.paused') : t('settings.pauseHint')}</Note>
        <Button label={paused ? t('settings.pauseOff') : t('settings.pauseOn')} variant="secondary" onPress={togglePause} disabled={busy} />
      </Section>

      <Section title={t('settings.contacts')}>
        <Note>{t('settings.contactsHint')}</Note>
        <Button label={t('settings.contactsBlock')} variant="secondary" onPress={blockContacts} disabled={busy} />
        <Button label={t('settings.contactsUnblock')} variant="ghost" onPress={() => run(api.unblockContacts)} disabled={busy} />
        <Button label={t('settings.blockedList')} variant="ghost" onPress={() => router.push('/blocked')} />
        {note ? <Note>{note}</Note> : null}
      </Section>

      <Section title={t('settings.title')}>
        {confirming ? (
          <>
            <Note>{t(confirming === 'withdraw' ? 'settings.withdrawSensitiveConfirm' : 'settings.deleteAccountConfirm')}</Note>
            <Button label={t('settings.confirm')} variant="danger" onPress={confirm} loading={busy} />
            <Button label={t('common.cancel')} variant="ghost" onPress={() => setConfirming(null)} />
          </>
        ) : (
          <>
            {profile?.consents.sensitive_data ? (
              <Button label={t('settings.withdrawSensitive')} variant="secondary" onPress={() => setConfirming('withdraw')} />
            ) : null}
            <Button label={t('settings.deleteAccount')} variant="danger" onPress={() => setConfirming('delete')} />
            <Button label={t('settings.signOut')} variant="ghost" onPress={leave} />
          </>
        )}
      </Section>

      {DEV_TOOLS_ENABLED ? (
        <Section title={t('settings.devTools')}>
          <Button label={t('dev.title')} variant="secondary" onPress={() => router.push('/dev/impersonate' as Href)} />
        </Section>
      ) : null}

      <ErrorText message={error ? errorMessage(t, error) : null} />
    </Screen>
  );
}
