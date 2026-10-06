import { assertEquals } from 'jsr:@std/assert@1';
import { appEnv, isLocalSupabase } from '../_shared/providers/config.ts';
import { impersonationAllowed, parseImpersonateRequest } from './guard.ts';

const LOCAL = 'http://kong:8000';
const HOSTED = 'https://abcdefghijklmnop.supabase.co';

Deno.test('impersonation needs development, the local stack and the flag', () => {
  assertEquals(impersonationAllowed({ appEnv: 'development', supabaseUrl: LOCAL, flag: true }), { ok: true });
  assertEquals(impersonationAllowed({ appEnv: 'production', supabaseUrl: LOCAL, flag: true }).ok, false);
  assertEquals(impersonationAllowed({ appEnv: undefined, supabaseUrl: LOCAL, flag: true }).ok, false);
  assertEquals(impersonationAllowed({ appEnv: 'development', supabaseUrl: HOSTED, flag: true }).ok, false);
  assertEquals(impersonationAllowed({ appEnv: 'development', supabaseUrl: LOCAL, flag: false }).ok, false);
  assertEquals(impersonationAllowed({ appEnv: 'development', supabaseUrl: LOCAL, flag: 'true' }).ok, false);
});

Deno.test('local stack detection', () => {
  for (const url of [LOCAL, 'http://127.0.0.1:54321', 'http://localhost:54321', 'http://host.docker.internal:54321']) {
    assertEquals(isLocalSupabase(url), true, url);
  }
  for (const url of [HOSTED, 'https://localhost.evil.com', 'http://kong.example.com', '']) {
    assertEquals(isLocalSupabase(url), false, url);
  }
});

Deno.test('a hosted project without APP_ENV counts as production', () => {
  assertEquals(appEnv(undefined, HOSTED), 'production');
  assertEquals(appEnv(undefined, LOCAL), 'development');
  assertEquals(appEnv('production', LOCAL), 'production');
  assertEquals(appEnv('staging', HOSTED), 'production');
});

Deno.test('request parsing', () => {
  assertEquals(parseImpersonateRequest({ action: 'list' }), { action: 'list' });
  assertEquals(parseImpersonateRequest({ action: 'login', userId: '00000000-0000-4000-8000-000000000001' }), {
    action: 'login', userId: '00000000-0000-4000-8000-000000000001',
  });
  assertEquals(parseImpersonateRequest({ action: 'login', userId: 'x' }), null);
  assertEquals(parseImpersonateRequest({ action: 'grant', kind: 'premium' }), { action: 'grant', kind: 'premium' });
  assertEquals(parseImpersonateRequest({ action: 'grant', kind: 'money' }), null);
  assertEquals(parseImpersonateRequest(null), null);
});
