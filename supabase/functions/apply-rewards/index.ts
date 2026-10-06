// Applies earned referral free months (spec §9) through the RewardsProvider, then
// mirrors them in the database. Called hourly by pg_cron with the service role key.

import { rewardsProvider } from '../_shared/providers/rewards/index.ts';
import { isServiceCall } from '../_shared/storage.ts';
import { adminClient, configReader, json } from '../_shared/supabase.ts';

Deno.serve(async (req) => {
  if (!isServiceCall(req)) return json(401, { error: 'not_authenticated' });
  const admin = adminClient();
  const provider = await rewardsProvider(configReader(admin));

  const { data: pending, error } = await admin.rpc('service_pending_rewards', { p_limit: 100 });
  if (error) return json(500, { error: 'queue_read_failed' });

  let applied = 0;
  for (const reward of (pending ?? []) as { id: number; user_id: string; value: number }[]) {
    try {
      await provider.grantFreeMonths(reward.user_id, Number(reward.value));
      const { error: applyError } = await admin.rpc('service_apply_free_month', { p_reward_id: reward.id });
      if (!applyError) applied++;
    } catch {
      console.error('apply-rewards: grant failed, retried next run');
    }
  }
  return json(200, { applied });
});
