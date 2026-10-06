// A profile as shown in the feed or to a match: photos (or an initials avatar),
// first name, age, drink icons only (spec §1), badges, distance range, answers and
// bio. With onLike, a heart on the shown photo and on each answer sends a targeted
// like (spec §5).

import { Image } from 'expo-image';
import { useEffect, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import type { LikeTarget, ProfileCard } from '../lib/api';
import { supabase } from '../lib/supabase';
import { colors, font, radius, spacing } from '../theme';
import { DrinkIcon } from './DrinkIcon';

const AVATAR_COLORS = [colors.coral, colors.navy, '#E0896B', '#4C6A92', '#B85C7A', '#3E7C6F'];

export function avatarColor(id: string) {
  let hash = 0;
  for (const ch of id) hash = (hash * 31 + ch.charCodeAt(0)) >>> 0;
  return AVATAR_COLORS[hash % AVATAR_COLORS.length]!;
}

type ShownPhoto = { id: string; url: string };

/** Signed URLs for the card photos; the storage policy allows served profiles and matches. */
function useShownPhotos(card: ProfileCard): ShownPhoto[] {
  const [shown, setShown] = useState<ShownPhoto[]>([]);
  useEffect(() => {
    setShown([]);
    if (card.photos.length === 0) return;
    let cancelled = false;
    void supabase.storage
      .from('photos')
      .createSignedUrls(card.photos.map((p) => p.storage_path), 3600)
      .then(({ data }) => {
        if (cancelled) return;
        const next: ShownPhoto[] = [];
        card.photos.forEach((p, i) => {
          const url = data?.[i]?.signedUrl;
          if (url) next.push({ id: p.id, url });
        });
        setShown(next);
      });
    return () => {
      cancelled = true;
    };
  }, [card]);
  return shown;
}

export function ProfileCardView(props: {
  card: ProfileCard;
  alcoholFree: boolean;
  onLike?: (target: LikeTarget) => void;
  likeDisabled?: boolean;
}) {
  const { card, alcoholFree, onLike, likeDisabled } = props;
  const { t } = useTranslation();
  const shown = useShownPhotos(card);
  const [photoIndex, setPhotoIndex] = useState(0);
  useEffect(() => setPhotoIndex(0), [card.id]);

  const current = shown[photoIndex];
  const onlyBeer = card.matched_drinks.length === 1 && card.matched_drinks[0] === 'beer' && card.drinks.length > 1;

  return (
    <View style={styles.card}>
      <Pressable
        accessibilityRole="imagebutton"
        accessibilityLabel={shown.length ? t('card.photo', { current: photoIndex + 1, total: shown.length }) : card.first_name}
        onPress={() => shown.length > 1 && setPhotoIndex((photoIndex + 1) % shown.length)}
        style={styles.media}
      >
        {current ? (
          <Image source={{ uri: current.url }} style={StyleSheet.absoluteFill} contentFit="cover" transition={150} />
        ) : (
          <View style={[StyleSheet.absoluteFill, styles.avatar, { backgroundColor: avatarColor(card.id) }]}>
            <Text style={styles.initials}>{card.first_name.slice(0, 1).toUpperCase()}</Text>
          </View>
        )}
        {shown.length > 1 ? (
          <View style={styles.dots}>
            {shown.map((s, i) => <View key={s.id} style={[styles.dot, i === photoIndex && styles.dotActive]} />)}
          </View>
        ) : null}
        {onLike && current ? (
          <LikeButton
            label={t('feed.likePhoto')}
            disabled={likeDisabled}
            onPress={() => onLike({ kind: 'photo', ref: current.id })}
            style={styles.photoLike}
          />
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
            <View style={styles.promptText}>
              <Text style={font.small}>{t(`prompts.questions.${p.question_code}`)}</Text>
              <Text style={styles.answer}>{p.answer}</Text>
            </View>
            {onLike ? (
              <LikeButton
                label={t('feed.likeAnswer')}
                disabled={likeDisabled}
                onPress={() => onLike({ kind: 'prompt', ref: p.question_code })}
              />
            ) : null}
          </View>
        ))}
      </View>
    </View>
  );
}

function LikeButton(props: { label: string; onPress: () => void; disabled?: boolean; style?: object }) {
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={props.label}
      disabled={props.disabled}
      onPress={props.onPress}
      hitSlop={8}
      style={[styles.likeButton, props.disabled && styles.likeDisabled, props.style]}
    >
      <Text style={styles.likeIcon}>♥</Text>
    </Pressable>
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
  prompt: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, paddingVertical: spacing.sm, borderTopWidth: 1, borderTopColor: colors.border },
  promptText: { flex: 1, gap: 2 },
  answer: { fontSize: 17, fontWeight: '600', color: colors.text },
  likeButton: { width: 44, height: 44, borderRadius: 22, alignItems: 'center', justifyContent: 'center', backgroundColor: colors.white, borderWidth: 1.5, borderColor: colors.coral },
  likeDisabled: { opacity: 0.4 },
  likeIcon: { color: colors.coral, fontSize: 22 },
  photoLike: { position: 'absolute', bottom: spacing.sm, left: spacing.sm },
});
