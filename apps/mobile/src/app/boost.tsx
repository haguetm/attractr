// Boost (spec §10): 30 minutes at the top of the zone, with the views obtained.
// Bought at 2 € (consumable) or offered monthly with Premium.

import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { useTranslation } from 'react-i18next';
import type { PurchasesPackage } from 'react-native-purchases';
import { Button, ErrorText, Note, Screen } from '../components/ui';
import { useSession } from '../features/session/SessionProvider';
import { api, type BoostStatus } from '../lib/api';
import { errorMessage } from '../lib/errors';
import { buy, loadPlans, purchasesAvailable } from '../lib/purchases';
import { useSubmit } from '../lib/useSubmit';

const time = new Intl.DateTimeFormat('fr-FR', { hour: '2-digit', minute: '2-digit' });

export default function BoostScreen() {
  const { t } = useTranslation();
  const { profile, refreshProfile } = useSession();
  const [status, setStatus] = useState<BoostStatus | null>(null);
  const [pack, setPack] = useState<PurchasesPackage | null>(null);
  const { busy, error, run } = useSubmit();

  const load = useCallback(() => {
    void api.getMyBoost().then(setStatus).catch(() => undefined);
    void loadPlans().then((p) => setPack(p.boost)).catch(() => undefined);
  }, []);
  useFocusEffect(load);

  const activate = () =>
    run(async () => {
      await api.activateBoost();
      load();
    });

  const purchase = () =>
    run(async () => {
      if (pack && (await buy(pack))) {
        // The credit arrives with the webhook.
        await new Promise((resolve) => setTimeout(resolve, 3000));
        await refreshProfile();
        load();
      }
    });

  const last = status?.last;

  return (
    <Screen title={t('boost.title')} subtitle={t('boost.subtitle')} footer={<Button label={t('common.back')} variant="ghost" onPress={() => router.back()} />}>
      {last?.active ? (
        <Note>{t('boost.active', { time: time.format(new Date(last.ends_at)), views: last.views })}</Note>
      ) : last ? (
        <Note>{t('boost.lastResult', { views: last.views })}</Note>
      ) : null}
      <Note>{status?.credits ? t('boost.credits', { count: status.credits }) : t('boost.noCredits')}</Note>
      <Button label={t('boost.activate')} onPress={activate} loading={busy} disabled={!status?.credits || !!last?.active} />
      {purchasesAvailable && pack ? <Button label={t('boost.buy')} variant="secondary" onPress={purchase} disabled={busy} /> : null}
      {!profile?.premium.active ? <Note>{t('boost.monthly')}</Note> : null}
      <ErrorText message={error ? errorMessage(t, error) : null} />
    </Screen>
  );
}
