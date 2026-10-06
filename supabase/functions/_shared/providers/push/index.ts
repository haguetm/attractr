import { type ConfigReader, providerMode } from '../config.ts';
import { ExpoPushSender } from './expo.ts';
import { MockPushSender } from './mock.ts';
import type { PushSender } from './types.ts';

export type { PushMessage, PushResult, PushSender } from './types.ts';

export async function pushSender(config: ConfigReader): Promise<PushSender> {
  const mode = await providerMode(config, 'push');
  return mode === 'mock' ? new MockPushSender() : new ExpoPushSender(Deno.env.get('EXPO_ACCESS_TOKEN'));
}
