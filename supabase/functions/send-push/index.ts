// Drains the notification outbox. Called every minute by pg_cron (see migration
// 20261009100000_push_schedule.sql) with the service role key; refuses anyone else.

import { pushSender } from '../_shared/providers/push/index.ts';
import { adminClient, configReader, json } from '../_shared/supabase.ts';
import { type OutboxRow, planPushes, settle } from './outbox.ts';

Deno.serve(async (req) => {
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!serviceKey || req.headers.get('Authorization') !== `Bearer ${serviceKey}`) {
    return json(401, { error: 'not_authenticated' });
  }

  const admin = adminClient();
  const { data, error } = await admin.rpc('service_pending_notifications', { p_limit: 500 });
  if (error) {
    console.error('send-push: queue read failed', error.code);
    return json(500, { error: 'queue_read_failed' });
  }
  const rows = (data ?? []) as OutboxRow[];
  if (rows.length === 0) return json(200, { sent: 0 });

  const plan = planPushes(rows);
  const results = plan.messages.length ? await (await pushSender(configReader(admin))).send(plan.messages) : [];
  const outcome = settle(plan, results);

  const { error: markError } = await admin.rpc('service_mark_notifications', {
    p_sent: outcome.sent,
    p_failed: outcome.failed,
    p_error: outcome.error,
    p_dead_tokens: outcome.deadTokens,
  });
  if (markError) {
    console.error('send-push: settle failed', markError.code);
    return json(500, { error: 'settle_failed' });
  }
  return json(200, { sent: outcome.sent.length, failed: outcome.failed.length });
});
