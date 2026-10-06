// Dashboard access: a dedicated secret (METRICS_DASHBOARD_TOKEN), never a user session.
// The payload holds aggregates only (cohorts under 5 users are hidden in SQL).

const encoder = new TextEncoder();

/** Constant-time comparison of two strings. */
export function safeEqual(a: string, b: string): boolean {
  const x = encoder.encode(a);
  const y = encoder.encode(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return diff === 0;
}

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
