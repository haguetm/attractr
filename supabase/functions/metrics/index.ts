// Metrics dashboard payload (retention by weekly cohort, daily KPIs) for tools/dashboard.

import { adminClient } from '../_shared/supabase.ts';
import { authorized, CORS, parseDays } from './auth.ts';

const reply = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  if (req.method !== 'GET') return reply(405, { error: 'method_not_allowed' });
  if (!authorized(req)) return reply(401, { error: 'not_authenticated' });
  const days = parseDays(new URL(req.url));
  if (!days) return reply(400, { error: 'invalid_range' });

  const { data, error } = await adminClient().rpc('service_metrics_dashboard', { p_days: days });
  if (error) {
    console.error('metrics: dashboard query failed');
    return reply(500, { error: 'metrics_failed' });
  }
  return reply(200, data);
});
