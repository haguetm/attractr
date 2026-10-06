import { adminClient, json } from '../_shared/supabase.ts';
import { extractEvent, isAuthorized } from './handler.ts';

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json(405, { error: 'method_not_allowed' });
  if (!isAuthorized(req.headers.get('Authorization'), Deno.env.get('REVENUECAT_WEBHOOK_SECRET'))) {
    return json(401, { error: 'not_authenticated' });
  }
  const event = extractEvent(await req.json().catch(() => null));
  if (!event) return json(400, { error: 'invalid_request' });

  const { data, error } = await adminClient().rpc('service_apply_revenuecat_event', { p_event: event });
  if (error) {
    // 5xx makes RevenueCat retry later.
    console.error('revenuecat-webhook: apply failed', error.code);
    return json(500, { error: 'apply_failed' });
  }
  return json(200, { outcome: data });
});
