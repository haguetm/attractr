// Propose a group outing inside a match (spec §7): place, day, time. Friends are
// invited next, by each of the two matched people.

import { OUTING_HOURS, OUTING_MINUTES, outingStart, upcomingDays } from '@attractr/shared';
import { router, useLocalSearchParams } from 'expo-router';
import { useMemo, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { Button, Chip, Chips, ErrorText, Field, Note, Screen, Section } from '../../components/ui';
import { track } from '../../lib/analytics';
import { api } from '../../lib/api';
import { errorMessage } from '../../lib/errors';
import { formatDay, formatTime } from '../../lib/format';
import { useSubmit } from '../../lib/useSubmit';

export default function NewOutingScreen() {
  const { t } = useTranslation();
  const { matchId } = useLocalSearchParams<{ matchId: string }>();
  const days = useMemo(() => upcomingDays(), []);
  const [place, setPlace] = useState('');
  const [day, setDay] = useState(0);
  const [hour, setHour] = useState(20);
  const [minute, setMinute] = useState(0);
  const { busy, error, run } = useSubmit();

  const start = outingStart(days[day]!, hour, minute);

  const create = () =>
    run(async () => {
      if (!start) return;
      await api.createOuting(matchId, place, start);
      track('outing_created');
      router.replace({ pathname: '/outing/[matchId]', params: { matchId } });
    });

  return (
    <Screen
      title={t('outing.newTitle')}
      subtitle={t('outing.newSubtitle')}
      footer={
        <>
          <Button label={t('outing.create')} onPress={create} loading={busy} disabled={!start || place.trim().length < 2} />
          <Button label={t('common.cancel')} variant="ghost" onPress={() => router.back()} />
        </>
      }
    >
      <Field label={t('outing.place')} value={place} onChangeText={setPlace} placeholder={t('outing.placePlaceholder')} maxLength={120} />
      <Section title={t('outing.day')}>
        <Chips>
          {days.map((d, i) => <Chip key={d.toISOString()} label={formatDay(d)} selected={day === i} onPress={() => setDay(i)} />)}
        </Chips>
      </Section>
      <Section title={t('outing.time')}>
        <Chips>
          {OUTING_HOURS.map((h) => <Chip key={h} label={`${h} h`} selected={hour === h} onPress={() => setHour(h)} />)}
        </Chips>
        <Chips>
          {OUTING_MINUTES.map((m) => <Chip key={m} label={formatTime(hour, m)} selected={minute === m} onPress={() => setMinute(m)} />)}
        </Chips>
      </Section>
      {!start ? <Note>{t('outing.invalidTime')}</Note> : null}
      <ErrorText message={error ? errorMessage(t, error) : null} />
    </Screen>
  );
}
