// AI profile analysis (spec §11). A separate consent comes first; the analysis runs in
// the analyze-profile Edge Function, once a week. Free users see one tip (spec §10),
// Premium users the per-photo advice, the suggested order and the bio rewrite, which
// they accept or edit before anything changes on their profile.

import { router, useFocusEffect } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { Image, StyleSheet, Text, View } from 'react-native';
import { Button, ErrorText, Field, Note, Screen, Section } from '../components/ui';
import { useSession } from '../features/session/SessionProvider';
import { track } from '../lib/analytics';
import { type AiAnalysisState, api } from '../lib/api';
import { errorMessage } from '../lib/errors';
import { formatDateTime } from '../lib/format';
import { signedPhotoUrl } from '../lib/upload';
import { useSubmit } from '../lib/useSubmit';
import { colors, font, radius, spacing } from '../theme';

export default function AiAnalysisScreen() {
  const { t } = useTranslation();
  const { profile, refreshProfile } = useSession();
  const [state, setState] = useState<AiAnalysisState | null>(null);
  const [bio, setBio] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [urls, setUrls] = useState<Record<string, string>>({});
  const { busy, error, run } = useSubmit();

  const load = useCallback(async () => {
    const s = await api.getAiAnalysis();
    setState(s);
    setBio((prev) => prev ?? s.analysis?.bio?.rewrite ?? null);
  }, []);

  useFocusEffect(useCallback(() => { void load().catch(() => undefined); }, [load]));

  const photos = profile?.photos ?? [];
  useEffect(() => {
    void Promise.all(photos.map(async (p) => [p.id, await signedPhotoUrl(p.storage_path)] as const)).then((pairs) =>
      setUrls(Object.fromEntries(pairs.filter(([, u]) => u)) as Record<string, string>));
  }, [photos.map((p) => p.id).join()]);

  const consent = () => run(async () => {
    const versions = await api.latestConsentVersions();
    await api.grantConsent('ai_photo_analysis', versions.ai_photo_analysis);
    await refreshProfile();
    await load();
  });
  const analyze = () => run(async () => {
    await api.runAiAnalysis();
    track('ai_analysis_run');
    setBio(null);
    await load();
  });
  const withdraw = () => run(async () => {
    await api.withdrawConsent('ai_photo_analysis');
    setBio(null);
    await refreshProfile();
    await load();
  });
  const applyOrder = (order: string[]) => run(async () => {
    const rest = photos.map((p) => p.id).filter((id) => !order.includes(id));
    await api.reorderPhotos([...order, ...rest]);
    await refreshProfile();
    setNotice(t('ai.orderApplied'));
  });
  const saveBio = () => run(async () => {
    if (!profile || bio === null) return;
    await api.setBio(bio, profile.id);
    await refreshProfile();
    setNotice(t('ai.bioSaved'));
  });

  const footer = <Button label={t('common.back')} variant="ghost" onPress={() => router.back()} />;

  if (!state) return <Screen title={t('ai.title')} footer={footer}><ErrorText message={error ? errorMessage(t, error) : null} /></Screen>;

  if (!state.consent) {
    return (
      <Screen title={t('ai.title')} footer={<><Button label={t('ai.consentAccept')} onPress={consent} loading={busy} />{footer}</>}>
        <Text style={font.body}>{t('ai.consentIntro')}</Text>
        <Text style={font.body}>{t('ai.consentItems')}</Text>
        <Note>{t('ai.consentRules')}</Note>
        <ErrorText message={error ? errorMessage(t, error) : null} />
      </Screen>
    );
  }

  const a = state.analysis;
  const canRun = !state.running && !state.next_available_at;
  const byId = Object.fromEntries((a?.photos ?? []).map((p) => [p.photo_id, p]));

  return (
    <Screen
      title={t('ai.title')}
      subtitle={a ? t('ai.doneAt', { date: formatDateTime(a.completed_at) }) : t('ai.subtitle')}
      footer={
        <>
          {canRun ? <Button label={a ? t('ai.runAgain') : t('ai.run')} onPress={analyze} loading={busy} /> : null}
          {footer}
        </>
      }
    >
      {state.running ? <Note>{t('ai.running')}</Note> : null}
      {state.next_available_at ? <Note>{t('ai.nextAt', { date: formatDateTime(state.next_available_at) })}</Note> : null}
      {notice ? <Note>{notice}</Note> : null}

      {a ? (
        <Section title={t('ai.topTip')}>
          <Text style={font.body}>{a.top_tip}</Text>
        </Section>
      ) : null}

      {a?.locked ? (
        <Section title={t('ai.lockedTitle')}>
          <Text style={font.body}>{t('ai.lockedBody', { count: a.locked.photos })}</Text>
          <Button label={t('ai.goPremium')} variant="secondary" onPress={() => router.push('/premium')} />
        </Section>
      ) : null}

      {a?.photo_order?.length ? (
        <Section title={t('ai.photos')}>
          {a.photo_order.map((id, i) => (
            <View key={id} style={styles.photo}>
              {urls[id] ? <Image source={{ uri: urls[id] }} style={styles.thumb} /> : <View style={styles.thumb} />}
              <View style={styles.advice}>
                <Text style={font.label}>{t('ai.position', { n: i + 1 })}</Text>
                {byId[id] ? <Text style={font.body}>👍 {byId[id].strength}</Text> : null}
                {byId[id] ? <Text style={font.body}>💡 {byId[id].improvement}</Text> : null}
              </View>
            </View>
          ))}
          <Button label={t('ai.applyOrder')} variant="secondary" onPress={() => applyOrder(a.photo_order!)} loading={busy} />
        </Section>
      ) : null}

      {a?.bio ? (
        <Section title={t('ai.bio')}>
          {a.bio.cliches.length ? <Text style={font.body}>{t('ai.cliches', { list: a.bio.cliches.map((c) => `« ${c} »`).join(', ') })}</Text> : null}
          <Text style={font.body}>{a.bio.drink_fit}</Text>
          <Field label={t('ai.rewrite')} hint={t('ai.rewriteHint')} value={bio ?? ''} onChangeText={setBio} multiline />
          <Button label={t('ai.saveBio')} variant="secondary" onPress={saveBio} loading={busy} disabled={!bio?.trim()} />
        </Section>
      ) : null}

      <ErrorText message={error ? errorMessage(t, error) : null} />
      <Button label={t('ai.withdraw')} variant="ghost" onPress={withdraw} />
    </Screen>
  );
}

const styles = StyleSheet.create({
  photo: { flexDirection: 'row', gap: spacing.md, marginBottom: spacing.md },
  thumb: { width: 72, height: 96, borderRadius: radius.md, backgroundColor: colors.border },
  advice: { flex: 1, gap: spacing.xs },
});
