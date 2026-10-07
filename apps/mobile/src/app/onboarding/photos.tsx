// Screen 10: photos, stored in a private bucket. Moderation comes in phase 5.

import { Image } from 'expo-image';
import * as ImagePicker from 'expo-image-picker';
import { useEffect, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { Button, ErrorText, Note, Screen } from '../../components/ui';
import { useOnboarding } from '../../features/onboarding/OnboardingProvider';
import { useSession } from '../../features/session/SessionProvider';
import { api } from '../../lib/api';
import { errorMessage } from '../../lib/errors';
import { supabase } from '../../lib/supabase';
import { signedPhotoUrl, uploadImage } from '../../lib/upload';
import { useSubmit } from '../../lib/useSubmit';
import { colors, radius, spacing } from '../../theme';

export default function PhotosScreen() {
  const { t } = useTranslation();
  const { profile, refreshProfile } = useSession();
  const { goNext, progress, photoLimits } = useOnboarding();
  const [urls, setUrls] = useState<Record<string, string>>({});
  const [denied, setDenied] = useState(false);
  const { busy, error, run } = useSubmit();
  const photos = profile?.photos ?? [];
  // Rejected photos do not count towards the minimum (same rule as complete_onboarding).
  const usable = photos.filter((p) => p.moderation_status !== 'rejected');

  useEffect(() => {
    const missing = photos.filter((p) => !urls[p.id]);
    if (missing.length === 0) return;
    void Promise.all(missing.map(async (p) => [p.id, await signedPhotoUrl(p.storage_path)] as const)).then((pairs) => {
      const found = pairs.filter((pair): pair is readonly [string, string] => pair[1] !== null);
      setUrls((prev) => ({ ...prev, ...Object.fromEntries(found) }));
    });
  }, [photos, urls]);

  const add = () =>
    run(async () => {
      const permission = await ImagePicker.requestMediaLibraryPermissionsAsync();
      if (!permission.granted) {
        setDenied(true);
        return;
      }
      const result = await ImagePicker.launchImageLibraryAsync({
        mediaTypes: ['images'],
        allowsEditing: true,
        aspect: [4, 5],
        quality: 0.8,
      });
      if (result.canceled || !result.assets[0]) return;
      const asset = result.assets[0];
      const path = await uploadImage('photos', profile!.id, asset.uri, asset.mimeType);
      const photoId = await api.addPhoto(path);
      // Moderation failures are retried by the scheduled batch; the photo stays pending.
      await api.moderatePhoto(photoId).catch(() => undefined);
      await refreshProfile();
    });

  const remove = (id: string) =>
    run(async () => {
      const path = await api.removePhoto(id);
      await supabase.storage.from('photos').remove([path]);
      await refreshProfile();
    });

  const makeMain = (id: string) =>
    run(async () => {
      await api.reorderPhotos([id, ...photos.filter((p) => p.id !== id).map((p) => p.id)]);
      await refreshProfile();
    });

  return (
    <Screen
      progress={progress('photos')}
      title={t('photos.title')}
      subtitle={t('photos.subtitle', { min: photoLimits.min, max: photoLimits.max })}
      footer={
        <Button
          label={t('common.continue')}
          onPress={() => run(() => goNext('photos'))}
          disabled={usable.length < photoLimits.min || busy}
        />
      }
    >
      <View style={styles.grid}>
        {photos.map((p, i) => (
          <View key={p.id} style={styles.tile}>
            {urls[p.id] ? <Image source={{ uri: urls[p.id] }} style={styles.image} contentFit="cover" /> : null}
            <View style={styles.badges}>
              {i === 0 ? <Text style={styles.mainBadge}>{t('photos.main')}</Text> : null}
              {p.moderation_status !== 'approved' ? (
                <Text style={[styles.status, p.moderation_status === 'rejected' && styles.statusRejected]}>
                  {t(p.moderation_status === 'rejected' ? 'photos.statusRejected' : 'photos.statusPending')}
                </Text>
              ) : null}
            </View>
            <View style={styles.actions}>
              {i > 0 ? (
                <Pressable accessibilityRole="button" onPress={() => makeMain(p.id)}>
                  <Text style={styles.action}>{t('photos.makeMain')}</Text>
                </Pressable>
              ) : null}
              <Pressable accessibilityRole="button" onPress={() => remove(p.id)}>
                <Text style={styles.action}>{t('photos.remove')}</Text>
              </Pressable>
            </View>
          </View>
        ))}
        {photos.length < photoLimits.max ? (
          <Pressable accessibilityRole="button" onPress={add} disabled={busy} style={[styles.tile, styles.addTile]}>
            <Text style={styles.addLabel}>{busy ? t('photos.uploading') : `+ ${t('photos.add')}`}</Text>
          </Pressable>
        ) : null}
      </View>
      {denied ? <Note>{t('photos.permission')}</Note> : null}
      {photos.some((p) => p.moderation_status === 'rejected') ? <Note>{t('photos.rejectedHint')}</Note> : null}
      <Note>{t('photos.moderationNote')}</Note>
      <ErrorText message={error ? errorMessage(t, error) : null} />
    </Screen>
  );
}

const styles = StyleSheet.create({
  grid: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm },
  tile: { width: '31%', aspectRatio: 4 / 5, borderRadius: radius.md, overflow: 'hidden', backgroundColor: colors.navySoft },
  image: StyleSheet.absoluteFill,
  // Stacked so the "Principale" and moderation badges never overlap on a narrow tile.
  badges: { position: 'absolute', top: 6, left: 6, right: 6, alignItems: 'flex-start', gap: 4 },
  mainBadge: { backgroundColor: colors.coral, color: colors.white, fontSize: 11, fontWeight: '700', paddingHorizontal: 6, paddingVertical: 2, borderRadius: radius.pill, overflow: 'hidden' },
  actions: { position: 'absolute', bottom: 0, left: 0, right: 0, padding: 4, gap: 2, backgroundColor: 'rgba(31,42,74,0.7)' },
  action: { color: colors.white, fontSize: 11, fontWeight: '600', textAlign: 'center' },
  addTile: { alignItems: 'center', justifyContent: 'center', borderWidth: 1.5, borderStyle: 'dashed', borderColor: colors.navy, backgroundColor: colors.white },
  addLabel: { color: colors.navy, fontWeight: '700' },
  status: { backgroundColor: colors.navy, color: colors.white, fontSize: 10, fontWeight: '700', paddingHorizontal: 6, paddingVertical: 2, borderRadius: radius.pill, overflow: 'hidden' },
  statusRejected: { backgroundColor: colors.error },
});
