// Screen 9: three written questions from the list, 150 characters each.

import { useEffect, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { Button, Choice, ErrorText, Field, Screen } from '../../components/ui';
import { useOnboarding } from '../../features/onboarding/OnboardingProvider';
import { useSession } from '../../features/session/SessionProvider';
import { api } from '../../lib/api';
import { errorMessage } from '../../lib/errors';
import { supabase } from '../../lib/supabase';
import { useSubmit } from '../../lib/useSubmit';
import { colors, font, radius, spacing } from '../../theme';

const MAX = 150;
type Slot = { questionCode: string | null; answer: string };

export default function PromptsScreen() {
  const { t } = useTranslation();
  const { profile, refreshProfile } = useSession();
  const { goNext, progress } = useOnboarding();
  const [questions, setQuestions] = useState<string[]>([]);
  const [slots, setSlots] = useState<Slot[]>(() =>
    [0, 1, 2].map((i) => {
      const saved = profile?.prompts[i];
      return { questionCode: saved?.question_code ?? null, answer: saved?.answer ?? '' };
    }),
  );
  const [picking, setPicking] = useState<number | null>(null);
  const { busy, error, run } = useSubmit();

  useEffect(() => {
    void supabase
      .from('prompt_questions')
      .select('code')
      .eq('active', true)
      .order('sort_order')
      .then(({ data }) => setQuestions((data ?? []).map((q) => q.code as string)));
  }, []);

  const update = (i: number, patch: Partial<Slot>) => setSlots(slots.map((s, j) => (j === i ? { ...s, ...patch } : s)));
  const used = new Set(slots.map((s) => s.questionCode));
  const complete = slots.every((s) => s.questionCode && s.answer.trim().length > 0 && s.answer.length <= MAX);

  const submit = () =>
    run(async () => {
      await api.setPrompts(slots.map((s) => ({ question_code: s.questionCode!, answer: s.answer.trim() })));
      await refreshProfile();
      await goNext('prompts');
    });

  return (
    <Screen
      progress={progress('prompts')}
      title={t('prompts.title')}
      subtitle={t('prompts.subtitle')}
      footer={<Button label={t('common.continue')} onPress={submit} loading={busy} disabled={!complete} />}
    >
      {slots.map((slot, i) => (
        <View key={i} style={styles.card}>
          {picking === i || !slot.questionCode ? (
            questions
              .filter((q) => q === slot.questionCode || !used.has(q))
              .map((q) => (
                <Choice
                  key={q}
                  label={t(`prompts.questions.${q}`)}
                  selected={slot.questionCode === q}
                  onPress={() => {
                    update(i, { questionCode: q });
                    setPicking(null);
                  }}
                />
              ))
          ) : (
            <>
              <View style={styles.questionRow}>
                <Text style={[font.label, styles.flex]}>{t(`prompts.questions.${slot.questionCode}`)}</Text>
                <Pressable accessibilityRole="button" onPress={() => setPicking(i)}>
                  <Text style={styles.link}>{t('prompts.change')}</Text>
                </Pressable>
              </View>
              <Field
                value={slot.answer}
                onChangeText={(answer) => update(i, { answer })}
                placeholder={t('prompts.answerPlaceholder')}
                maxLength={MAX}
                multiline
                hint={t('prompts.counter', { count: slot.answer.length })}
              />
            </>
          )}
        </View>
      ))}
      <ErrorText message={error ? errorMessage(t, error) : null} />
    </Screen>
  );
}

const styles = StyleSheet.create({
  flex: { flex: 1 },
  card: { gap: spacing.sm, padding: spacing.md, borderRadius: radius.lg, backgroundColor: colors.white },
  questionRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
  link: { color: colors.coral, fontWeight: '600' },
});
