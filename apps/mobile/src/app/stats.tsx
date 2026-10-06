// Profile statistics (Premium, spec §10): views, likes per photo and per answer, and
// one's own popularity level in the zone (P5).

import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { StyleSheet, Text, View } from 'react-native';
import { Button, ErrorText, Note, Screen, Section } from '../components/ui';
import { api, type MyStats } from '../lib/api';
import { errorMessage } from '../lib/errors';
import { colors, font, radius, spacing } from '../theme';

export default function StatsScreen() {
  const { t } = useTranslation();
  const [stats, setStats] = useState<MyStats | null>(null);
  const [error, setError] = useState<unknown>(null);

  useFocusEffect(useCallback(() => {
    void api.getMyStats().then(setStats).catch(setError);
  }, []));

  return (
    <Screen title={t('stats.title')} footer={<Button label={t('common.back')} variant="ghost" onPress={() => router.back()} />}>
      {stats ? (
        <>
          <View style={styles.tiles}>
            <Tile label={t('stats.views')} value={stats.views_7d} sub={t('stats.last7')} />
            <Tile label={t('stats.likes')} value={stats.likes_7d} sub={t('stats.last7')} />
            <Tile label={t('stats.views')} value={stats.views_30d} sub={t('stats.last30')} />
            <Tile label={t('stats.likes')} value={stats.likes_30d} sub={t('stats.last30')} />
          </View>
          <Section title={t('stats.perPhoto')}>
            {stats.photos.map((p) => (
              <Text key={p.id} style={font.body}>{t('stats.photo', { position: p.position })} : {p.likes}</Text>
            ))}
          </Section>
          <Section title={t('stats.perAnswer')}>
            {stats.prompts.map((p) => (
              <Text key={p.question_code} style={font.body}>{t(`prompts.questions.${p.question_code}`)} : {p.likes}</Text>
            ))}
          </Section>
          <Section title={t('stats.popularity')}>
            <Note>{stats.popularity ? t(`stats.popularityLevels.${stats.popularity}`) : t('stats.popularityUnknown')}</Note>
          </Section>
        </>
      ) : null}
      <ErrorText message={error ? errorMessage(t, error) : null} />
    </Screen>
  );
}

function Tile({ label, value, sub }: { label: string; value: number; sub: string }) {
  return (
    <View style={styles.tile}>
      <Text style={styles.value}>{value}</Text>
      <Text style={font.label}>{label}</Text>
      <Text style={font.small}>{sub}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  tiles: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm },
  tile: { width: '48%', padding: spacing.md, borderRadius: radius.md, backgroundColor: colors.white, gap: 2 },
  value: { fontSize: 28, fontWeight: '800', color: colors.coral },
});
