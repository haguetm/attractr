// Premium (spec §10): one price for everyone, cancel in one tap. Purchases go through
// RevenueCat; the server activates Premium from the webhook, so the profile is
// refreshed a few times after a purchase.

import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { StyleSheet, Text, View } from 'react-native';
import type { PurchasesPackage } from 'react-native-purchases';
import { Button, ErrorText, Note, Screen, Section } from '../components/ui';
import { useSession } from '../features/session/SessionProvider';
import { api, type MyReferrals } from '../lib/api';
import { DEV_TOOLS_ENABLED } from '../lib/devTools';
import { errorMessage } from '../lib/errors';
import { formatDateTime } from '../lib/format';
import { buy, loadPlans, manageSubscription, purchasesAvailable, restore } from '../lib/purchases';
import { useSubmit } from '../lib/useSubmit';
import { colors, font, radius, spacing } from '../theme';

const FEATURES = [
  'unlimited_likes', 'who_liked', 'filters', 'groups', 'incognito', 'rewind', 'passport', 'stats', 'popularity', 'boost', 'no_ads',
] as const;

const wait = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

export default function PremiumScreen() {
  const { t } = useTranslation();
  const { profile, refreshProfile } = useSession();
  const [packages, setPackages] = useState<PurchasesPackage[]>([]);
  const [referrals, setReferrals] = useState<MyReferrals | null>(null);
  const [processing, setProcessing] = useState(false);
  const { busy, error, run } = useSubmit();
  const premium = profile?.premium;

  useFocusEffect(
    useCallback(() => {
      void loadPlans().then((p) => setPackages(p.subscriptions)).catch(() => undefined);
      void api.getMyReferrals().then(setReferrals).catch(() => undefined);
    }, []),
  );

  // The webhook usually lands within seconds: poll the profile briefly.
  const waitForPremium = async () => {
    setProcessing(true);
    for (let i = 0; i < 6; i++) {
      const p = await refreshProfile();
      if (p?.premium.active) break;
      await wait(2000);
    }
    setProcessing(false);
  };

  const subscribe = (pkg: PurchasesPackage) =>
    run(async () => {
      if (await buy(pkg)) await waitForPremium();
    });

  const discount = referrals?.rewards.find((r) => r.kind === 'discount' && r.status === 'earned');

  return (
    <Screen title={t('premium.title')} subtitle={t('premium.subtitle')} footer={<Button label={t('common.back')} variant="ghost" onPress={() => router.back()} />}>
      {premium?.active && premium.until ? (
        <Note>{t(premium.paying ? 'premium.active' : 'premium.activeReferral', { date: formatDateTime(premium.until) })}</Note>
      ) : null}

      <View style={styles.features}>
        {FEATURES.map((f) => (
          <Text key={f} style={font.body}>✓ {t(`premium.features.${f}`)}</Text>
        ))}
      </View>

      {discount ? (
        <Note>{t(discount.role === 'referee' ? 'premium.refereeDiscount' : 'premium.referrerDiscount', { pct: discount.value })}</Note>
      ) : null}

      {!premium?.paying ? (
        <Section title={t('premium.subscribe')}>
          {purchasesAvailable && packages.length ? (
            packages.map((pkg) => (
              <Button key={pkg.identifier} label={`${pkg.product.title} · ${pkg.product.priceString}`} onPress={() => subscribe(pkg)} disabled={busy || processing} />
            ))
          ) : (
            <>
              <Text style={font.body}>{t('premium.monthly')} · {t('premium.yearly')}</Text>
              <Note>{t('premium.unavailable')}</Note>
            </>
          )}
        </Section>
      ) : null}
      {processing ? <Note>{t('premium.processing')}</Note> : null}

      {purchasesAvailable ? (
        <>
          <Button label={t('premium.manage')} variant="secondary" onPress={() => run(manageSubscription)} />
          <Button label={t('premium.restore')} variant="ghost" onPress={() => run(async () => { await restore(); await waitForPremium(); })} />
        </>
      ) : null}

      {DEV_TOOLS_ENABLED ? (
        <Section title={t('settings.devTools')}>
          <Button label={t('premium.devGrant')} variant="secondary" onPress={() => run(async () => { await api.devGrant('premium'); await refreshProfile(); })} />
          <Button label={t('premium.devBoost')} variant="secondary" onPress={() => run(async () => { await api.devGrant('boost'); await refreshProfile(); })} />
        </Section>
      ) : null}

      <ErrorText message={error ? errorMessage(t, error) : null} />
    </Screen>
  );
}

const styles = StyleSheet.create({
  features: { gap: spacing.xs, padding: spacing.md, borderRadius: radius.lg, backgroundColor: colors.white },
});
