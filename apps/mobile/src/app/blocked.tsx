// Profiles the user blocked (visible to the owner only). Contact blocks are only
// mentioned: listing them would reveal which contacts use the app.

import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { StyleSheet, Text, View } from 'react-native';
import { Button, ErrorText, Note, Screen } from '../components/ui';
import { api, type MyBlocks } from '../lib/api';
import { errorMessage } from '../lib/errors';
import { useSubmit } from '../lib/useSubmit';
import { colors, font, radius, spacing } from '../theme';

export default function BlockedScreen() {
  const { t } = useTranslation();
  const [blocks, setBlocks] = useState<MyBlocks | null>(null);
  const { busy, error, run } = useSubmit();

  const load = useCallback(() => {
    void api.getMyBlocks().then(setBlocks).catch(() => undefined);
  }, []);
  useFocusEffect(load);

  const unblock = (id: string) =>
    run(async () => {
      await api.unblockProfile(id);
      load();
    });

  return (
    <Screen title={t('blocked.title')} footer={<Button label={t('common.back')} variant="ghost" onPress={() => router.back()} />}>
      {blocks?.contacts_blocked ? <Note>{t('blocked.contacts')}</Note> : null}
      {blocks && blocks.profiles.length === 0 ? <Note>{t('blocked.empty')}</Note> : null}
      {blocks?.profiles.map((b) => (
        <View key={b.id} style={styles.row}>
          <Text style={[font.body, styles.name]}>{b.first_name}</Text>
          <Button label={t('blocked.unblock')} variant="secondary" onPress={() => unblock(b.id)} disabled={busy} />
        </View>
      ))}
      <ErrorText message={error ? errorMessage(t, error) : null} />
    </Screen>
  );
}

const styles = StyleSheet.create({
  row: { flexDirection: 'row', alignItems: 'center', gap: spacing.md, padding: spacing.sm, borderRadius: radius.md, backgroundColor: colors.white },
  name: { flex: 1, fontWeight: '600' },
});
