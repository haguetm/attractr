import { type ConfigReader, providerMode } from '../config.ts';
import { type MockSelfieOutcome, MockSelfieProvider } from './mock.ts';
import type { SelfieVerificationProvider } from './types.ts';

export type { SelfieInput, SelfieResult, SelfieVerificationProvider } from './types.ts';

export async function selfieProvider(config: ConfigReader): Promise<SelfieVerificationProvider> {
  const mode = await providerMode(config, 'selfie');
  if (mode === 'mock') {
    return new MockSelfieProvider(((await config.get('providers.mock_selfie_outcome')) ?? 'pass') as MockSelfieOutcome);
  }
  throw new Error('real selfie provider not implemented yet');
}
