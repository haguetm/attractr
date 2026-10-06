import type { ModerationInput, ModerationScores, PhotoModerationProvider } from './types.ts';

export type MockPhotoOutcome = 'approve' | 'review' | 'reject';

const SCORES: Record<MockPhotoOutcome, ModerationScores> = {
  approve: { nudity: 0.01, violence: 0.01 },
  review: { nudity: 0.6, violence: 0.05 },
  reject: { nudity: 0.97, violence: 0.02 },
};

/** Development provider; outcome set with app_config `providers.mock_photo_outcome`. */
export class MockModerationProvider implements PhotoModerationProvider {
  constructor(private readonly outcome: MockPhotoOutcome = 'approve') {}

  moderate(_input: ModerationInput): Promise<ModerationScores> {
    return Promise.resolve(SCORES[this.outcome] ?? SCORES.approve);
  }
}
