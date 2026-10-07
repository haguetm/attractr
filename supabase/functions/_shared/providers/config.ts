// Environment detection and provider selection.
// Mock or real implementations are chosen from app_config (`providers.<name>`,
// falling back to `providers.mode`). Production can never run mocks.
//
// Environments:
//   development  local stack; mocks return the outcome set in app_config.
//   beta         hosted test project; mocks are allowed, but the selfie and photo
//                mocks always ask for human review (no automatic approval).
//   production   real providers only.

export type ProviderMode = 'mock' | 'real';
export type AppEnv = 'development' | 'beta' | 'production';

export interface ConfigReader {
  get(key: string): Promise<unknown>;
}

const APP_ENVS: readonly AppEnv[] = ['development', 'beta', 'production'];

/** True when the functions run against the local Supabase stack (Docker). */
export function isLocalSupabase(url = Deno.env.get('SUPABASE_URL') ?? ''): boolean {
  return /^http:\/\/(kong|localhost|127\.0\.0\.1|host\.docker\.internal)(:\d+)?(\/|$)/.test(url);
}

/**
 * APP_ENV when set explicitly; otherwise development only on the local stack.
 * A hosted project with a missing or unknown APP_ENV is treated as production (fail safe).
 */
export function appEnv(
  value = Deno.env.get('APP_ENV'),
  url = Deno.env.get('SUPABASE_URL') ?? '',
): AppEnv {
  if ((APP_ENVS as readonly string[]).includes(value ?? '')) return value as AppEnv;
  return isLocalSupabase(url) ? 'development' : 'production';
}

export async function providerMode(config: ConfigReader, provider: string, env = appEnv()): Promise<ProviderMode> {
  const specific = await config.get(`providers.${provider}`);
  const mode = (specific ?? (await config.get('providers.mode')) ?? 'mock') as string;
  if (mode !== 'mock' && mode !== 'real') throw new Error(`invalid provider mode for ${provider}`);
  if (env === 'production' && mode === 'mock') throw new Error(`mock ${provider} provider refused in production`);
  return mode;
}

/**
 * Outcome of a mock provider: the app_config value in development; in beta, the
 * `beta` outcome (human review) whatever app_config says.
 */
export async function mockOutcome<T extends string>(
  config: ConfigReader,
  key: string,
  fallback: T,
  beta: T,
  env = appEnv(),
): Promise<T> {
  if (env === 'beta') return beta;
  return ((await config.get(key)) ?? fallback) as T;
}
