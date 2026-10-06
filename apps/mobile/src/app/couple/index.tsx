// Couple account (spec §6): invite a partner (link or pseudo), set up the shared profile
// (open or closed, drinks, what you look for, shared bio), shared photos approved by both,
// likes to approve, individual profile visibility (open couples), leave in one tap.

import { DRINKS, type Drink, GENDERS, type Gender, STRUCTURES, type Structure } from '@attractr/shared';
import { Image } from 'expo-image';
import * as ImagePicker from 'expo-image-picker';
import { router, useFocusEffect } from 'expo-router';
import { type ReactNode, useCallback, useEffect, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { Share, StyleSheet, Text, View } from 'react-native';
import { DrinkIcon } from '../../components/DrinkIcon';
import { Button, Checkbox, Chip, Chips, Choice, ErrorText, Field, Note, Screen, Section } from '../../components/ui';
import { useSession } from '../../features/session/SessionProvider';
import { api, type CoupleKind, type MyCouple } from '../../lib/api';
import { errorMessage } from '../../lib/errors';
import { coupleLink } from '../../lib/format';
import { signedPhotoUrl, uploadImage } from '../../lib/upload';
import { useSubmit } from '../../lib/useSubmit';
import { colors, font, radius, spacing } from '../../theme';

const toggle = <T,>(list: T[], v: T) => (list.includes(v) ? list.filter((x) => x !== v) : [...list, v]);

export default function CoupleScreen() {
  const { t } = useTranslation();
  const { profile } = useSession();
  const [data, setData] = useState<MyCouple | null>(null);
  const [username, setUsername] = useState('');
  const [note, setNote] = useState<string | null>(null);
  const [confirmLeave, setConfirmLeave] = useState(false);
  const { busy, error, run } = useSubmit();

  const load = useCallback(() => {
    void api.getMyCouple().then(setData).catch(() => undefined);
  }, []);
  useFocusEffect(load);

  const act = (action: () => Promise<unknown>, done?: string) =>
    run(async () => {
      await action();
      setNote(done ?? null);
      load();
    });

  const couple = data?.couple;

  if (!couple) {
    return (
      <Screen title={t('couple.title')} subtitle={t('couple.intro')} footer={<Button label={t('common.back')} variant="ghost" onPress={() => router.back()} />}>
        {data?.invitations.length ? (
          <Section title={t('couple.requests')}>
            {data.invitations.map((i) => (
              <View key={i.id} style={styles.card}>
                <Text style={font.body}>{t('couple.requestFrom', { name: i.from })}</Text>
                <Button label={t('couple.accept')} onPress={() => act(() => api.respondCoupleRequest(i.id, true))} disabled={busy} />
                <Button label={t('couple.refuse')} variant="ghost" onPress={() => act(() => api.respondCoupleRequest(i.id, false))} disabled={busy} />
              </View>
            ))}
          </Section>
        ) : null}
        <Section title={t('couple.invite')}>
          <Note>{t('couple.inviteLinkHint')}</Note>
          <Button
            label={t('couple.invite')}
            onPress={() => run(async () => {
              const code = await api.createCoupleInvitation();
              await Share.share({ message: t('couple.shareMessage', { link: coupleLink(code) }) });
            })}
            disabled={busy}
          />
          <Field label={t('couple.byUsername')} value={username} onChangeText={setUsername} placeholder={t('couple.usernamePlaceholder')} autoCapitalize="none" />
          <Button label={t('couple.send')} variant="secondary" onPress={() => act(() => api.requestCoupleByUsername(username), t('couple.sent'))} disabled={busy || username.trim().length < 3} />
          {note ? <Note>{note}</Note> : null}
        </Section>
        <ErrorText message={error ? errorMessage(t, error) : null} />
      </Screen>
    );
  }

  const partner = couple.partner.first_name;
  const photoReady = couple.photos.some((p) => p.partner_approved && p.moderation_status === 'approved');

  return (
    <Screen
      title={couple.name}
      subtitle={couple.status === 'published' ? t('couple.published') : t('couple.setupTitle')}
      footer={
        confirmLeave ? (
          <>
            <Note>{t('couple.leaveConfirm')}</Note>
            <Button label={t('couple.leave')} variant="danger" onPress={() => run(async () => { await api.leaveCouple(); router.back(); })} loading={busy} />
            <Button label={t('common.cancel')} variant="ghost" onPress={() => setConfirmLeave(false)} />
          </>
        ) : (
          <>
            <Button label={t('couple.leave')} variant="danger" onPress={() => setConfirmLeave(true)} />
            <Button label={t('common.back')} variant="ghost" onPress={() => router.back()} />
          </>
        )
      }
    >
      {couple.status === 'setup' ? (
        <Section title={t('couple.checklist')}>
          <Text style={font.body}>{couple.kind ? '✓' : '○'} {t('couple.checkProfile')}</Text>
          <Text style={font.body}>{photoReady ? '✓' : '○'} {t('couple.checkPhoto')}</Text>
          <Text style={font.body}>{couple.me_verified && couple.partner.verified ? '✓' : '○'} {t('couple.checkVerified')}</Text>
          {!couple.partner.verified ? <Note>{t('couple.partnerPending', { name: partner })}</Note> : null}
        </Section>
      ) : null}

      {couple.pending_likes.length ? (
        <Section title={t('couple.likes')}>
          {couple.pending_likes.map((l) => (
            <View key={l.id} style={styles.card}>
              <Text style={font.body}>
                {l.mine ? t('couple.likeMine', { name: l.target_first_name, partner }) : t('couple.likeToApprove', { partner, name: l.target_first_name })}
              </Text>
              {!l.mine ? (
                <View style={styles.actions}>
                  <View style={styles.flex}><Button label={t('couple.approveLike')} onPress={() => act(() => api.decideCoupleLike(l.id, true))} disabled={busy} /></View>
                  <View style={styles.flex}><Button label={t('couple.rejectLike')} variant="secondary" onPress={() => act(() => api.decideCoupleLike(l.id, false))} disabled={busy} /></View>
                </View>
              ) : null}
            </View>
          ))}
        </Section>
      ) : null}

      <CoupleProfileForm couple={couple} alcoholFree={profile?.alcohol_free_icons ?? false} onSaved={load} />

      <Section title={t('couple.photos')}>
        <Note>{t('couple.photosHint')}</Note>
        {couple.photos.map((p) => (
          <CouplePhoto key={p.id} path={p.storage_path}>
            {p.needs_my_approval ? (
              <>
                <Button label={t('couple.approve')} onPress={() => act(() => api.approveCouplePhoto(p.id, true))} disabled={busy} />
                <Button label={t('couple.reject')} variant="ghost" onPress={() => act(() => api.approveCouplePhoto(p.id, false))} disabled={busy} />
              </>
            ) : !p.partner_approved ? (
              <Text style={font.small}>{t('couple.waitingPartner', { name: partner })}</Text>
            ) : p.moderation_status !== 'approved' ? (
              <Text style={font.small}>{t('couple.inModeration')}</Text>
            ) : null}
          </CouplePhoto>
        ))}
        <Button
          label={t('couple.addPhoto')}
          variant="secondary"
          disabled={busy}
          onPress={() => run(async () => {
            const result = await ImagePicker.launchImageLibraryAsync({ mediaTypes: ['images'], allowsEditing: true, aspect: [4, 5], quality: 0.8 });
            if (result.canceled || !result.assets[0]) return;
            const path = await uploadImage('photos', couple.id, result.assets[0].uri, result.assets[0].mimeType);
            const photoId = await api.addCouplePhoto(path);
            await api.moderatePhoto(photoId).catch(() => undefined);
            load();
          })}
        />
      </Section>

      {couple.kind === 'open' ? (
        <Section title={t('couple.myProfile')}>
          <Note>{t('couple.hiddenHint')}</Note>
          <Button
            label={couple.my_individual_hidden ? t('couple.showMine') : t('couple.hideMine')}
            variant="secondary"
            onPress={() => act(() => api.setCoupleVisibility(!couple.my_individual_hidden))}
            disabled={busy}
          />
        </Section>
      ) : null}

      <ErrorText message={error ? errorMessage(t, error) : null} />
    </Screen>
  );
}

function CoupleProfileForm({ couple, alcoholFree, onSaved }: { couple: NonNullable<MyCouple['couple']>; alcoholFree: boolean; onSaved: () => void }) {
  const { t } = useTranslation();
  const [kind, setKind] = useState<CoupleKind>(couple.kind ?? 'open');
  const [main, setMain] = useState<Drink>(couple.drinks.find((d) => d !== 'beer') ?? 'coffee');
  const [withBeer, setWithBeer] = useState(couple.drinks.includes('beer'));
  const [structure, setStructure] = useState<Structure>(couple.sensitive.structure ?? 'open_to_explore');
  const [target, setTarget] = useState<('person' | 'couple')[]>(couple.seeking_target.length ? couple.seeking_target : ['person']);
  const [seeking, setSeeking] = useState<Gender[]>(couple.sensitive.seeking_genders ?? []);
  const [bio, setBio] = useState(couple.bio ?? '');
  const [saved, setSaved] = useState(false);
  const { busy, error, run } = useSubmit();

  const drinks: Drink[] = kind === 'closed' ? ['beer'] : main === 'beer' ? ['beer'] : withBeer ? ['beer', main] : [main];
  const romantic = drinks.some((d) => d !== 'beer');

  const save = () =>
    run(async () => {
      await api.setCoupleProfile({ kind, drinks, structure: romantic ? structure : null, target, seeking, bio });
      setSaved(true);
      onSaved();
    });

  return (
    <Section title={t('couple.setupTitle')}>
      <Text style={font.label}>{t('couple.kind')}</Text>
      <Choice label={t('couple.open')} description={t('couple.openHint')} selected={kind === 'open'} onPress={() => setKind('open')} />
      <Choice label={t('couple.closed')} description={t('couple.closedHint')} selected={kind === 'closed'} onPress={() => setKind('closed')} />
      {kind === 'open' ? (
        <>
          <Chips>
            {DRINKS.map((d) => (
              <Chip key={d} label={t(`drinks.${d}`)} selected={main === d} onPress={() => setMain(d)} leading={<DrinkIcon drink={d} alcoholFree={alcoholFree} size={18} />} />
            ))}
          </Chips>
          {main !== 'beer' ? <Checkbox label={t('drinks.addBeer')} checked={withBeer} onToggle={() => setWithBeer(!withBeer)} /> : null}
          {romantic ? (
            <Chips>
              {STRUCTURES.filter((s) => s !== 'monogamous').map((s) => (
                <Chip key={s} label={t(`structure.${s}`)} selected={structure === s} onPress={() => setStructure(s)} />
              ))}
            </Chips>
          ) : null}
        </>
      ) : null}
      <Text style={font.label}>{t('couple.target')}</Text>
      <Chips>
        <Chip label={t('couple.targetPerson')} selected={target.includes('person')} onPress={() => setTarget(toggle(target, 'person').length ? toggle(target, 'person') : target)} />
        <Chip label={t('couple.targetCouple')} selected={target.includes('couple')} onPress={() => setTarget(toggle(target, 'couple').length ? toggle(target, 'couple') : target)} />
      </Chips>
      {romantic ? (
        <>
          <Text style={font.label}>{t('couple.seeking')}</Text>
          <Chips>
            {GENDERS.map((g) => <Chip key={g} label={t(`seekingGender.${g}`)} selected={seeking.includes(g)} onPress={() => setSeeking(toggle(seeking, g))} />)}
          </Chips>
        </>
      ) : null}
      <Field label={t('couple.bio')} value={bio} onChangeText={setBio} multiline maxLength={300} />
      <Button label={t('couple.save')} onPress={save} loading={busy} disabled={romantic && seeking.length === 0} />
      {saved ? <Note>✓</Note> : null}
      <ErrorText message={error ? errorMessage(t, error) : null} />
    </Section>
  );
}

function CouplePhoto({ path, children }: { path: string; children?: ReactNode }) {
  const [url, setUrl] = useState<string | null>(null);
  useEffect(() => {
    void signedPhotoUrl(path).then(setUrl);
  }, [path]);
  return (
    <View style={styles.photoRow}>
      {url ? <Image source={{ uri: url }} style={styles.photo} contentFit="cover" /> : <View style={[styles.photo, styles.placeholder]} />}
      <View style={styles.flex}>{children}</View>
    </View>
  );
}

const styles = StyleSheet.create({
  flex: { flex: 1, gap: spacing.xs },
  card: { gap: spacing.sm, padding: spacing.md, borderRadius: radius.md, backgroundColor: colors.white },
  actions: { flexDirection: 'row', gap: spacing.sm },
  photoRow: { flexDirection: 'row', gap: spacing.md, alignItems: 'center' },
  photo: { width: 72, height: 90, borderRadius: radius.sm },
  placeholder: { backgroundColor: colors.navySoft },
});
