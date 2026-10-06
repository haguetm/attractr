// A profile as shown in the feed: photos (or an initials avatar), first name, age,
// drink icons only (spec §1), badges, distance range, answers and bio.

import { Image } from 'expo-image';
import { useEffect, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import type { ProfileCard } from '../lib/api';
import { supabase } from '../lib/supabase';
import { colors, font, radius, spacing } from '../theme';
import { DrinkIcon } from './DrinkIcon';

const AVATAR_COLORS = [colors.coral, colors.navy, '#E0896B', '#4C6A92', '#B85C7A', '#3E7C6F'];

function avatarColor(id: string) {
  let hash = 0;
  for (const ch of id) hash = (hash * 31 + ch.charCodeAt(0)) >>> 0;
  return AVATAR_COLORS[hash % AVATAR_COLORS.length]!;
}

/** Signed URLs for the card photos; the storage policy allows profiles the feed served. */
function usePhotoUrls(card: ProfileCard) {
  const [urls, setUrls] = useState<string[]>([]);
  useEffect(() => {
    setUrls([]);
    if (card.photos.length === 0) return;
    let cancelled = false;
    void supabase.storage
      .from('photos')
      .createSignedUrls(card.photos.map((p) => p.storage_path), 3600)
      .then(({ data }) => {
        if (!cancelled) setUrls((data ?? []).map((d) => d.signedUrl).filter((u): u is string => !!u));
      });
    return () => {
      cancelled = true;
    };
  }, [card]);
  return urls;
}

export function ProfileCardView({ card, alcoholFree }: { card: ProfileCard; alcoholFree: boolean }) {
  const { t } = useTranslation();
  const urls = usePhotoUrls(card);
  const [photoIndex, setPhotoIndex] = useState(0);
  useEffect(() => setPhotoIndex(0), [card.id]);

  const onlyBeer = card.matched_drinks.length === 1 && card.matched_drinks[0] === 'beer' && card.drinks.length > 1;
  const initials = card.first_name.slice(0, 1).toUpperCase();

  return (
    <View style={styles.card}>
      <Pressable
        accessibilityRole="imagebutton"
        accessibilityLabel={urls.length ? t('card.photo', { current: photoIndex + 1, total: urls.length }) : card.first_name}
        onPress={() => urls.length > 1 && setPhotoIndex((photoIndex + 1) % urls.length)}
        style={styles.media}
      >
        {urls[photoIndex] ? (
          <Image source={{ uri: urls[photoIndex] }} style={StyleSheet.absoluteFill} contentFit="cover" transition={150} />
        ) : (
          <View style={[StyleSheet.absoluteFill, styles.avatar, { backgroundColor: avatarColor(card.id) }]}>
            <Text style={styles.initials}>{initials}</Text>
          </View>
        )}
        {urls.length > 1 ? (
          <View style={styles.dots}>
            {urls.map((u, i) => <View key={u} style={[styles.dot, i === photoIndex && styles.dotActive]} />)}
          </View>
        ) : null}
        <View style={styles.drinks}>
          {card.drinks.map((d) => (
            <View key={d} style={[styles.drinkBubble, !card.matched_drinks.includes(d) && styles.drinkDimmed]}>
              <DrinkIcon drink={d} alcoholFree={alcoholFree} size={22} />
            </View>
          ))}
        </View>
      </Pressable>

      <View style={styles.body}>
        <Text style={styles.name}>
          {card.first_name}, <Text style={styles.age}>{t('card.age', { age: card.age })}</Text>
        </Text>
        <View style={styles.badges}>
          {card.verified ? <Text style={[styles.badge, styles.badgeVerified]}>✓ {t('card.verified')}</Text> : null}
          {card.recently_active ? <Text style={[styles.badge, styles.badgeActive]}>● {t('card.recentlyActive')}</Text> : null}
          <Text style={styles.badge}>{t(`card.distance.${card.distance}`)}</Text>
        </View>
        {onlyBeer ? <Text style={styles.beerOnly}>{t('card.matchedOnlyBeer')}</Text> : null}
        {card.gender_detail || card.orientation ? (
          <Text style={font.small}>
            {[card.gender_detail, card.orientation && t(`orientation.labels.${card.orientation}`)].filter(Boolean).join(' · ')}
          </Text>
        ) : null}
        {card.bio ? <Text style={font.body}>{card.bio}</Text> : null}
        {card.prompts.map((p) => (
          <View key={p.question_code} style={styles.prompt}>
            <Text style={font.small}>{t(`prompts.questions.${p.question_code}`)}</Text>
            <Text style={styles.answer}>{p.answer}</Text>
          </View>
        ))}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  card: { borderRadius: radius.lg, backgroundColor: colors.white, overflow: 'hidden', borderWidth: 1, borderColor: colors.border },
  media: { width: '100%', aspectRatio: 4 / 5, backgroundColor: colors.navySoft },
  avatar: { alignItems: 'center', justifyContent: 'center' },
  initials: { fontSize: 96, fontWeight: '800', color: colors.white },
  dots: { position: 'absolute', top: 8, left: 8, right: 8, flexDirection: 'row', gap: 4 },
  dot: { flex: 1, height: 3, borderRadius: 2, backgroundColor: 'rgba(255,255,255,0.45)' },
  dotActive: { backgroundColor: colors.white },
  drinks: { position: 'absolute', bottom: spacing.sm, right: spacing.sm, flexDirection: 'row', gap: spacing.xs },
  drinkBubble: { backgroundColor: colors.white, borderRadius: radius.pill, padding: 6 },
  drinkDimmed: { opacity: 0.45 },
  body: { padding: spacing.md, gap: spacing.sm },
  name: { fontSize: 24, fontWeight: '700', color: colors.text },
  age: { fontWeight: '400' },
  badges: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.xs },
  badge: { fontSize: 12, color: colors.navy, backgroundColor: colors.navySoft, paddingHorizontal: 8, paddingVertical: 3, borderRadius: radius.pill, overflow: 'hidden' },
  badgeVerified: { backgroundColor: '#DDF0E4', color: colors.success },
  badgeActive: { backgroundColor: colors.coralSoft, color: colors.coral },
  beerOnly: { fontSize: 13, color: colors.navy, fontWeight: '600' },
  prompt: { gap: 2, paddingVertical: spacing.sm, borderTopWidth: 1, borderTopColor: colors.border },
  answer: { fontSize: 17, fontWeight: '600', color: colors.text },
});
