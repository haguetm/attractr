// Report a profile (spec §12), from the feed, a match profile or a chat. "Suspicion de
// mineur" comes first and is handled in priority. Blocking at the same time is on by default.

import { router, useLocalSearchParams } from 'expo-router';
import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import { Button, Checkbox, Choice, ErrorText, Field, Note, Screen, Section } from '../../components/ui';
import { api, REPORT_REASONS, type ReportReason } from '../../lib/api';
import { errorMessage } from '../../lib/errors';
import { useSubmit } from '../../lib/useSubmit';

export default function ReportScreen() {
  const { t } = useTranslation();
  const { userId, name, conversationId } = useLocalSearchParams<{ userId: string; name?: string; conversationId?: string }>();
  const [reason, setReason] = useState<ReportReason | null>(null);
  const [details, setDetails] = useState('');
  const [alsoBlock, setAlsoBlock] = useState(true);
  const [sent, setSent] = useState(false);
  const { busy, error, run } = useSubmit();

  const send = () =>
    run(async () => {
      if (!reason) return;
      await api.reportProfile({ targetId: userId, reason, details, conversationId, alsoBlock });
      setSent(true);
    });

  const leave = () => (alsoBlock && sent ? router.dismissTo('/feed') : router.back());

  return (
    <Screen
      title={t('report.title', { name: name ?? '' })}
      subtitle={t('report.subtitle')}
      footer={
        sent ? (
          <Button label={t('common.back')} onPress={leave} />
        ) : (
          <>
            <Button label={t('report.send')} onPress={send} loading={busy} disabled={!reason} />
            <Button label={t('common.cancel')} variant="ghost" onPress={() => router.back()} />
          </>
        )
      }
    >
      {sent ? (
        <Note>{t('report.sent')}</Note>
      ) : (
        <>
          <Section title={t('report.reason')}>
            {REPORT_REASONS.map((r) => (
              <Choice key={r} label={t(`report.reasons.${r}`)} selected={reason === r} onPress={() => setReason(r)} />
            ))}
            {reason === 'suspected_minor' ? <Note>{t('report.minorNote')}</Note> : null}
          </Section>
          <Field label={t('report.details')} value={details} onChangeText={setDetails} multiline maxLength={1000} />
          <Checkbox label={t('report.alsoBlock')} checked={alsoBlock} onToggle={() => setAlsoBlock(!alsoBlock)} />
        </>
      )}
      <ErrorText message={error ? errorMessage(t, error) : null} />
    </Screen>
  );
}
