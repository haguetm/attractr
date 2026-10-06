// Create a group (Premium creator, spec §8): romantic (needs a romantic drink) or friends
// (needs the Bière), and for friends groups who approves newcomers (Q18).

import { isRomantic } from '@attractr/shared';
import { router } from 'expo-router';
import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import { Button, Choice, ErrorText, Field, Screen, Section } from '../../components/ui';
import { useSession } from '../../features/session/SessionProvider';
import { api, type GroupKind } from '../../lib/api';
import { errorMessage } from '../../lib/errors';
import { useSubmit } from '../../lib/useSubmit';

export default function NewGroupScreen() {
  const { t } = useTranslation();
  const { profile } = useSession();
  const drinks = profile?.drinks ?? [];
  const canRomantic = drinks.some(isRomantic);
  const canFriends = drinks.includes('beer');
  const [kind, setKind] = useState<GroupKind>(canRomantic ? 'romantic' : 'friends');
  const [name, setName] = useState('');
  const [mode, setMode] = useState<'majority' | 'admin'>('majority');
  const { busy, error, run } = useSubmit();

  const create = () =>
    run(async () => {
      const id = await api.createGroup(kind, name, mode);
      router.replace({ pathname: '/group/[id]/info', params: { id } });
    });

  return (
    <Screen
      title={t('groupNew.title')}
      footer={
        <>
          <Button label={t('groupNew.create')} onPress={create} loading={busy} disabled={name.trim().length < 2} />
          <Button label={t('common.cancel')} variant="ghost" onPress={() => router.back()} />
        </>
      }
    >
      <Section title={t('groupNew.kind')}>
        <Choice
          label={t('groupNew.romantic')}
          description={canRomantic ? t('groupNew.romanticHint') : t('groupNew.needRomantic')}
          selected={kind === 'romantic'}
          disabled={!canRomantic}
          onPress={() => setKind('romantic')}
        />
        <Choice
          label={t('groupNew.friends')}
          description={canFriends ? t('groupNew.friendsHint') : t('groupNew.needBeer')}
          selected={kind === 'friends'}
          disabled={!canFriends}
          onPress={() => setKind('friends')}
        />
      </Section>
      <Field label={t('groupNew.name')} value={name} onChangeText={setName} placeholder={t('groupNew.namePlaceholder')} maxLength={40} />
      {kind === 'friends' ? (
        <Section title={t('groupNew.approval')}>
          <Choice label={t('groupNew.majority')} selected={mode === 'majority'} onPress={() => setMode('majority')} />
          <Choice label={t('groupNew.admin')} selected={mode === 'admin'} onPress={() => setMode('admin')} />
        </Section>
      ) : null}
      <ErrorText message={error ? errorMessage(t, error) : null} />
    </Screen>
  );
}
