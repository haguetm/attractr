import { type ConfigReader, providerMode } from '../config.ts';
import { MockRewardsProvider } from './mock.ts';
import { RevenueCatRewardsProvider } from './revenuecat.ts';
import type { RewardsProvider } from './types.ts';

export type { RewardsProvider } from './types.ts';

export async function rewardsProvider(config: ConfigReader): Promise<RewardsProvider> {
  const mode = await providerMode(config, 'rewards');
  if (mode === 'mock') return new MockRewardsProvider();
  const key = Deno.env.get('REVENUECAT_SECRET_KEY');
  if (!key) throw new Error('REVENUECAT_SECRET_KEY missing');
  return new RevenueCatRewardsProvider(key, ((await config.get('revenuecat.entitlement')) ?? 'premium') as string);
}
