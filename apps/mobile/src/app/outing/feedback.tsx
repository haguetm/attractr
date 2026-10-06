// Private feedback after an outing (spec §7): read by the Attractr team only.

import { router, useLocalSearchParams } from 'expo-router';
import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import { Button, Chip, Chips, ErrorText, Field, Screen, Section } from '../../components/ui';
import { api } from '../../lib/api';
import { errorMessage } from '../../lib/errors';
import { useSubmit } from '../../lib/useSubmit';

export default function OutingFeedbackScreen() {
  const { t } = useTranslation();
  const { outingId } = useLocalSearchParams<{ outingId: string }>();
  const [rating, setRating] = useState<number | null>(null);
  const [comment, setComment] = useState('');
  const { busy, error, run } = useSubmit();

  const send = () =>
    run(async () => {
      if (!rating) return;
      await api.giveOutingFeedback(outingId, rating, comment);
      router.back();
    });

  return (
    <Screen
      title={t('feedback.title')}
      subtitle={t('feedback.subtitle')}
      footer={
        <>
          <Button label={t('feedback.send')} onPress={send} loading={busy} disabled={!rating} />
          <Button label={t('common.cancel')} variant="ghost" onPress={() => router.back()} />
        </>
      }
    >
      <Section title={t('feedback.rating')}>
        <Chips>
          {[1, 2, 3, 4, 5].map((n) => <Chip key={n} label={'★'.repeat(n)} selected={rating === n} onPress={() => setRating(n)} />)}
        </Chips>
      </Section>
      <Field label={t('feedback.comment')} value={comment} onChangeText={setComment} multiline maxLength={500} />
      <ErrorText message={error ? errorMessage(t, error) : null} />
    </Screen>
  );
}
