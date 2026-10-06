// Product analytics allowlist (spec §12: no sensitive data in PostHog).
// Only these events are sent, each with only its listed properties, and every value is
// a short code from a closed set: no free text, no names, no drink, no orientation,
// no situation, no location. Anything else is dropped before leaving the phone.

const CODE = /^[a-z0-9_]{1,40}$/;

type PropRule = readonly string[] | 'code' | 'boolean' | 'count';

export const EVENTS = {
  app_opened: {},
  onboarding_step_completed: { step: 'code' },
  onboarding_completed: {},
  feed_viewed: { as_couple: 'boolean' },
  like_sent: { target: ['photo', 'prompt'], matched: 'boolean' },
  pass_sent: {},
  message_sent: { kind: ['match', 'group'] },
  premium_viewed: { source: 'code' },
  purchase_started: { product: ['monthly', 'yearly', 'boost'] },
  invitation_shared: { kind: ['referral', 'friend', 'couple'] },
  outing_created: {},
  ai_analysis_run: {},
  report_sent: {},
} as const satisfies Record<string, Record<string, PropRule>>;

export type AnalyticsEvent = keyof typeof EVENTS;
export type AnalyticsProps = Record<string, string | number | boolean>;

/** Keeps the allowed properties of an allowed event; null when the event is unknown. */
export function sanitize(event: string, props: Record<string, unknown> = {}): AnalyticsProps | null {
  const rules = (EVENTS as Record<string, Record<string, PropRule>>)[event];
  if (!rules) return null;
  const out: AnalyticsProps = {};
  for (const [key, rule] of Object.entries(rules)) {
    const v = props[key];
    if (v === undefined || v === null) continue;
    if (rule === 'boolean' && typeof v === 'boolean') out[key] = v;
    else if (rule === 'count' && typeof v === 'number' && Number.isInteger(v) && v >= 0 && v < 1e6) out[key] = v;
    else if (rule === 'code' && typeof v === 'string' && CODE.test(v)) out[key] = v;
    else if (Array.isArray(rule) && typeof v === 'string' && rule.includes(v)) out[key] = v;
  }
  return out;
}
