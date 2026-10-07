// Dashboard access: a dedicated secret (METRICS_DASHBOARD_TOKEN), never a user session.
// The payload holds aggregates only (cohorts under 5 users are hidden in SQL).

import { safeEqual } from '../_shared/secrets.ts';

/** True when the request carries the configured token; a missing or short secret refuses everyone. */
export function authorized(req: Request, secret = Deno.env.get('METRICS_DASHBOARD_TOKEN') ?? ''): boolean {
  if (secret.length < 32) return false;
  const header = req.headers.get('Authorization') ?? '';
  return header.startsWith('Bearer ') && safeEqual(header.slice(7), secret);
}

export function parseDays(url: URL): number | null {
  const raw = url.searchParams.get('days') ?? '90';
  const n = Number(raw);
  return Number.isInteger(n) && n >= 7 && n <= 400 ? n : null;
}

export const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Authorization',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
};
