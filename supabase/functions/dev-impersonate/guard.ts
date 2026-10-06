// "Tester en tant que" (spec §13): development only, behind a flag, impossible in
// production. Every condition must hold:
//   1. APP_ENV is explicitly "development";
//   2. the function runs on the local Supabase stack (never a hosted project);
//   3. app_config `dev.impersonation_enabled` is true;
//   4. the target is a seed account (is_seed).
// On top of that, scripts/deploy-functions.mjs never deploys dev-* functions to production.

import { isLocalSupabase } from '../_shared/providers/config.ts';

export interface GuardInput {
  appEnv: string | undefined;
  supabaseUrl: string;
  flag: unknown;
}

export type GuardResult = { ok: true } | { ok: false; reason: 'not_development' | 'not_local' | 'disabled' };

export function impersonationAllowed({ appEnv, supabaseUrl, flag }: GuardInput): GuardResult {
  if (appEnv !== 'development') return { ok: false, reason: 'not_development' };
  if (!isLocalSupabase(supabaseUrl)) return { ok: false, reason: 'not_local' };
  if (flag !== true) return { ok: false, reason: 'disabled' };
  return { ok: true };
}

export type ImpersonateRequest =
  | { action: 'list' }
  | { action: 'login'; userId: string }
  /** Grants to the calling user, to test Premium and boosts without a store. */
  | { action: 'grant'; kind: 'premium' | 'boost' };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function parseImpersonateRequest(body: unknown): ImpersonateRequest | null {
  const b = (body ?? {}) as Record<string, unknown>;
  if (b.action === 'list') return { action: 'list' };
  if (b.action === 'grant' && (b.kind === 'premium' || b.kind === 'boost')) return { action: 'grant', kind: b.kind };
  if (b.action === 'login' && typeof b.userId === 'string' && UUID.test(b.userId)) {
    return { action: 'login', userId: b.userId };
  }
  return null;
}
