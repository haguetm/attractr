// Referral (spec §9): code and link, anonymous statuses ("inscrit et vérifié"), rewards.

import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { Share, StyleSheet, Text, View } from 'react-native';
import { Button, ErrorText, Note, Screen, Section } from '../components/ui';
import { useSession } from '../features/session/SessionProvider';
import { api, type MyReferrals } from '../lib/api';
import { errorMessage } from '../lib/errors';
import { formatDateTime } from '../lib/format';
import { referralLink } from '../lib/referral';
import { useSubmit } from '../lib/useSubmit';
import { colors, font, radius, spacing } from '../theme';

export default function ReferralScreen() {
  const { t } = useTranslation();
  const { profile } = useSession();
  const [data, setData] = useState<MyReferrals | null>(null);
  const { error, run, setError } = useSubmit();

  useFocusEffect(useCallback(() => {
    void api.getMyReferrals().then(setData).catch(setError);
  }, [setError]));

  const share = () =>
    run(async () => {
      if (data) await Share.share({ message: t('referral.shareMessage', { code: data.code, link: referralLink(data.code) }) });
    });

  return (
    <Screen title={t('referral.title')} subtitle={t('referral.subtitle')} footer={<Button label={t('common.back')} variant="ghost" onPress={() => router.back()} />}>
      {data ? (
        <>
          <View style={styles.codeBox}>
            <Text style={font.small}>{t('referral.code')}</Text>
            <Text style={styles.code} selectable>{data.code}</Text>
          </View>
          <Button label={t('referral.share')} onPress={share} />
          <Note>{t(profile?.premium.paying ? 'referral.rulesPaying' : 'referral.rulesFree')}</Note>
          <Note>{t('referral.validation')}</Note>
          {profile?.premium.paying ? (
            <Text style={font.small}>{t('referral.monthsThisYear', { count: data.free_months_this_year, max: data.annual_cap_months })}</Text>
          ) : null}

          <Section title={t('referral.list')}>
            {data.referrals.length === 0 ? <Note>{t('referral.empty')}</Note> : null}
            {data.referrals.map((r, i) => (
              <Text key={i} style={font.body}>{t(`referral.status.${r.status}`)} · {formatDateTime(r.created_at)}</Text>
            ))}
          </Section>

          {data.rewards.length ? (
            <Section title={t('referral.rewards')}>
              {data.rewards.map((r, i) => (
                <Text key={i} style={font.body}>
                  {t(`referral.reward.${r.kind}`, { value: r.value })} · {t(`referral.reward.${r.status}`)}
                </Text>
              ))}
            </Section>
          ) : null}
        </>
      ) : null}
      <ErrorText message={error ? errorMessage(t, error) : null} />
    </Screen>
  );
}

const styles = StyleSheet.create({
  codeBox: { alignItems: 'center', padding: spacing.lg, borderRadius: radius.lg, backgroundColor: colors.white, gap: spacing.xs },
  code: { fontSize: 30, fontWeight: '800', letterSpacing: 4, color: colors.navy },
});
