import { type ConfigReader, mockOutcome, providerMode } from '../config.ts';
import { type MockPhotoOutcome, MockModerationProvider } from './mock.ts';
import type { PhotoModerationProvider } from './types.ts';

export type { ModerationInput, ModerationScores, PhotoModerationProvider } from './types.ts';

export async function moderationProvider(config: ConfigReader): Promise<PhotoModerationProvider> {
  const mode = await providerMode(config, 'moderation');
  if (mode === 'mock') {
    return new MockModerationProvider(await mockOutcome<MockPhotoOutcome>(config, 'providers.mock_photo_outcome', 'approve', 'review'));
  }
  throw new Error('real moderation provider not implemented yet');
}
