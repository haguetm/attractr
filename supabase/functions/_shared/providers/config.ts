// Environment detection and provider selection.
// Mock or real implementations are chosen from app_config (`providers.<name>`,
// falling back to `providers.mode`). Production can never run mocks.

export type ProviderMode = 'mock' | 'real';
export type AppEnv = 'development' | 'production';

export interface ConfigReader {
  get(key: string): Promise<unknown>;
}

/** True when the functions run against the local Supabase stack (Docker). */
export function isLocalSupabase(url = Deno.env.get('SUPABASE_URL') ?? ''): boolean {
  return /^http:\/\/(kong|localhost|127\.0\.0\.1|host\.docker\.internal)(:\d+)?(\/|$)/.test(url);
}

/**
 * APP_ENV when set explicitly; otherwise development only on the local stack.
 * A hosted project with a missing APP_ENV is treated as production (fail safe).
 */
export function appEnv(
  value = Deno.env.get('APP_ENV'),
  url = Deno.env.get('SUPABASE_URL') ?? '',
): AppEnv {
  if (value === 'development' || value === 'production') return value;
  return isLocalSupabase(url) ? 'development' : 'production';
}

export async function providerMode(config: ConfigReader, provider: string, env = appEnv()): Promise<ProviderMode> {
  const specific = await config.get(`providers.${provider}`);
  const mode = (specific ?? (await config.get('providers.mode')) ?? 'mock') as string;
  if (mode !== 'mock' && mode !== 'real') throw new Error(`invalid provider mode for ${provider}`);
  if (env === 'production' && mode === 'mock') throw new Error(`mock ${provider} provider refused in production`);
  return mode;
}
