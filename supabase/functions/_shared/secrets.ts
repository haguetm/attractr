// Shared-secret checks for calls that do not carry a user session.

const encoder = new TextEncoder();

/** Constant-time comparison of two strings. */
export function safeEqual(a: string, b: string): boolean {
  const x = encoder.encode(a);
  const y = encoder.encode(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return diff === 0;
}

/**
 * Scheduled calls (pg_cron + pg_net, see migration 20261018090000) carry the CRON_SECRET
 * function secret in the X-Cron-Secret header. A dedicated secret, so the service role
 * key never has to be stored in Vault. A missing or short secret refuses everyone.
 */
export function isCronCall(req: Request, secret = Deno.env.get('CRON_SECRET') ?? ''): boolean {
  if (secret.length < 32) return false;
  return safeEqual(req.headers.get('X-Cron-Secret') ?? '', secret);
}
