import { createClient, type SupabaseClient } from 'jsr:@supabase/supabase-js@2';
import type { ConfigReader } from './providers/config.ts';

export const json = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });

/** Returns the caller's user id from the request JWT, or null. */
export async function requestUserId(req: Request): Promise<string | null> {
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return null;
  const client = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data, error } = await client.auth.getUser();
  return error || !data.user ? null : data.user.id;
}

/** Service-role client: server-side only, bypasses RLS. */
export const adminClient = (): SupabaseClient =>
  createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

/** Reads app_config with the service role (server-only keys included). */
export function configReader(admin: SupabaseClient): ConfigReader {
  return {
    async get(key) {
      const { data, error } = await admin.from('app_config').select('value').eq('key', key).maybeSingle();
      if (error) throw new Error('config read failed');
      return data?.value ?? null;
    },
  };
}
