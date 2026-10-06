import type { SelfieInput, SelfieResult, SelfieVerificationProvider } from './types.ts';

export type MockSelfieOutcome = 'pass' | 'retake' | 'review' | 'minor' | 'duplicate';

/**
 * Development provider. The outcome is chosen with app_config
 * `providers.mock_selfie_outcome`, so every branch of the flow can be tried.
 */
export class MockSelfieProvider implements SelfieVerificationProvider {
  constructor(private readonly outcome: MockSelfieOutcome = 'pass') {}

  verify({ subjectId, declaredAge }: SelfieInput): Promise<SelfieResult> {
    const faceId = `mock-face-${subjectId}`;
    switch (this.outcome) {
      case 'retake':
        return Promise.resolve({ live: false, estimatedAge: null, confidence: null, faceId: null });
      case 'review':
        return Promise.resolve({ live: true, estimatedAge: declaredAge, confidence: 0.4, faceId });
      case 'minor':
        return Promise.resolve({ live: true, estimatedAge: 15, confidence: 0.9, faceId });
      case 'duplicate':
        return Promise.resolve({ live: true, estimatedAge: declaredAge, confidence: 0.95, faceId: 'mock-face-shared' });
      default:
        return Promise.resolve({ live: true, estimatedAge: declaredAge, confidence: 0.95, faceId });
    }
  }
}
