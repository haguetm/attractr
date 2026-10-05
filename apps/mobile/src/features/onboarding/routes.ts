import type { OnboardingProgress, OnboardingStep } from '@attractr/shared';
import type { MyProfile } from '../../lib/api';

export const stepPath = (step: OnboardingStep) => `/onboarding/${step.replace(/_/g, '-')}` as const;

export function progressFromProfile(p: MyProfile, minPhotos: number): OnboardingProgress {
  return {
    status: p.status,
    hasTermsConsent: !!p.consents.terms && !!p.consents.privacy,
    birthDate: p.birth_date,
    hasLocation: p.has_location,
    firstName: p.first_name,
    hasSensitiveConsent: !!p.consents.sensitive_data,
    hasSeekingGenders: (p.sensitive.seeking_genders?.length ?? 0) > 0,
    hasIntent: !!p.sensitive.situation && p.drinks.length > 0,
    promptsCount: p.prompts.length,
    photosCount: p.photos.length,
    minPhotos,
    verificationStatus: p.verification_status,
  };
}
