// Profile analysis provider (spec §11). Photos are referred to by their 1-based index in
// the request; the Edge Function maps indexes back to photo ids before recording.
// Nothing identifying is sent: no name, age, gender, location or sensitive field.

export interface AnalysisPhoto {
  index: number;
  image: Uint8Array;
  contentType: 'image/jpeg' | 'image/png' | 'image/webp' | 'image/gif';
}

export interface ProfileAnalysisInput {
  photos: AnalysisPhoto[];
  bio: string | null;
  prompts: { question: string; answer: string }[];
  drinks: string[];
}

export interface PhotoAdvice {
  index: number;
  strength: string;
  improvement: string;
}

export interface ProfileAnalysis {
  photos: PhotoAdvice[];
  photo_order: number[];
  bio: { cliches: string[]; rewrite: string; drink_fit: string };
  top_tip: string;
}

export interface ProfileAnalysisProvider {
  /** Recorded with the result, e.g. "claude-opus-5-5" or "mock". */
  readonly model: string;
  /** Returns the raw parsed answer; the output guard validates it afterwards. */
  analyze(input: ProfileAnalysisInput): Promise<unknown>;
}
