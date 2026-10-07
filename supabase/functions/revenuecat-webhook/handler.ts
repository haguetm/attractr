// RevenueCat webhook: authenticated with the shared secret configured in RevenueCat
// (Authorization header), then applied by private.apply_revenuecat_event (idempotent).

import { safeEqual } from '../_shared/secrets.ts';

export function isAuthorized(header: string | null, secret: string | undefined): boolean {
  if (!secret || !header) return false;
  return safeEqual(header.startsWith('Bearer ') ? header.slice(7) : header, secret);
}

export function extractEvent(body: unknown): Record<string, unknown> | null {
  const event = (body as { event?: unknown } | null)?.event;
  if (!event || typeof event !== 'object') return null;
  const e = event as Record<string, unknown>;
  return typeof e.id === 'string' && typeof e.type === 'string' ? e : null;
}
