// Selfie verification provider: liveness, age estimate and a face reference used to
// enforce "one face = one account" (spec §9, §12). Real implementation later, behind
// `providers.selfie`; development uses MockSelfieProvider.

export interface SelfieInput {
  image: Uint8Array;
  contentType: string;
  /** Opaque id of the account, so the provider can scope its face index. */
  subjectId: string;
  declaredAge: number;
}

export interface SelfieResult {
  live: boolean;
  estimatedAge: number | null;
  /** 0..1 confidence of the age estimate. */
  confidence: number | null;
  /** Provider's opaque face reference (never an image or a raw template). */
  faceId: string | null;
}

export interface SelfieVerificationProvider {
  verify(input: SelfieInput): Promise<SelfieResult>;
}
