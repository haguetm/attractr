// Chooses mock or real provider implementations from app_config
// (`providers.<name>`, falling back to `providers.mode`). Production can never run mocks.

export type ProviderMode = 'mock' | 'real';

export interface ConfigReader {
  get(key: string): Promise<unknown>;
}

export const appEnv = (): 'development' | 'production' =>
  Deno.env.get('APP_ENV') === 'production' ? 'production' : 'development';

export async function providerMode(config: ConfigReader, provider: string, env = appEnv()): Promise<ProviderMode> {
  const specific = await config.get(`providers.${provider}`);
  const mode = (specific ?? (await config.get('providers.mode')) ?? 'mock') as string;
  if (mode !== 'mock' && mode !== 'real') throw new Error(`invalid provider mode for ${provider}`);
  if (env === 'production' && mode === 'mock') throw new Error(`mock ${provider} provider refused in production`);
  return mode;
}
