// Photo moderation provider (nudity, violence). Scores are 0..1; the thresholds live
// in app_config and are applied in SQL (private.apply_photo_result).

export interface ModerationInput {
  image: Uint8Array;
  contentType: string;
}

export interface ModerationScores {
  nudity: number;
  violence: number;
}

export interface PhotoModerationProvider {
  moderate(input: ModerationInput): Promise<ModerationScores>;
}
