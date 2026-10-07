import { type ConfigReader, mockOutcome, providerMode } from '../config.ts';
import { type MockSelfieOutcome, MockSelfieProvider } from './mock.ts';
import type { SelfieVerificationProvider } from './types.ts';

export type { SelfieInput, SelfieResult, SelfieVerificationProvider } from './types.ts';

export async function selfieProvider(config: ConfigReader): Promise<SelfieVerificationProvider> {
  const mode = await providerMode(config, 'selfie');
  if (mode === 'mock') {
    return new MockSelfieProvider(await mockOutcome<MockSelfieOutcome>(config, 'providers.mock_selfie_outcome', 'pass', 'review'));
  }
  throw new Error('real selfie provider not implemented yet');
}
