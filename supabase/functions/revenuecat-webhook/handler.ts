// RevenueCat webhook: authenticated with the shared secret configured in RevenueCat
// (Authorization header), then applied by private.apply_revenuecat_event (idempotent).

export function isAuthorized(header: string | null, secret: string | undefined): boolean {
  if (!secret || !header) return false;
  const expected = header.startsWith('Bearer ') ? `Bearer ${secret}` : secret;
  if (header.length !== expected.length) return false;
  // Constant-time comparison.
  let diff = 0;
  for (let i = 0; i < header.length; i++) diff |= header.charCodeAt(i) ^ expected.charCodeAt(i);
  return diff === 0;
}

export function extractEvent(body: unknown): Record<string, unknown> | null {
  const event = (body as { event?: unknown } | null)?.event;
  if (!event || typeof event !== 'object') return null;
  const e = event as Record<string, unknown>;
  return typeof e.id === 'string' && typeof e.type === 'string' ? e : null;
}
