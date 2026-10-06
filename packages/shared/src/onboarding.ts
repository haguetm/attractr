// Onboarding flow (spec §3): which screens apply and which choices they offer.
// Pure functions so the order and skip rules are unit-tested.

import {
  type CompositionChoice,
  type Drink,
  type Situation,
  type Structure,
  STRUCTURES,
  isRomantic,
} from './domain';
import type { IntentFieldSwitches } from './intent';

export const ONBOARDING_STEPS = [
  'account_type',   // 4. individual or couple, asked first (DECISIONS: the first name screen depends on it)
  'age',            // 1. age, 18+, terms, referral code
  'location',       //    position or home: the country decides which sensitive fields exist (Q21)
  'identity',       // 2. first name, gender, sought genders
  'sensitive_consent', // 3. separate GDPR consent; sought genders are saved after it
  'situation',      // 5.
  'drinks',         // 6.
  'structure',      // 7. skipped with beer only
  'composition',    // 7b. only for polyamory
  'open_to_couples', // 8. only with a romantic drink
  'prompts',        // 9.
  'photos',         // 10.
  'selfie',         // 10b.
  'orientation',    // 11. optional
] as const;
export type OnboardingStep = (typeof ONBOARDING_STEPS)[number];

export interface IntentDraft {
  situation: Situation | null;
  drinks: Drink[];
  structure: Structure | null;
  composition: CompositionChoice | null;
  openToCouples: boolean;
}

export interface OnboardingSwitches extends IntentFieldSwitches {
  orientationEnabled: boolean;
}

export const EMPTY_INTENT: IntentDraft = {
  situation: null,
  drinks: [],
  structure: null,
  composition: null,
  openToCouples: false,
};

export function applicableSteps(draft: IntentDraft, switches: OnboardingSwitches): OnboardingStep[] {
  const romantic = draft.drinks.some(isRomantic);
  return ONBOARDING_STEPS.filter((step) => {
    switch (step) {
      case 'structure': return romantic && switches.structureEnabled;
      case 'composition': return romantic && switches.compositionEnabled && draft.structure === 'polyamorous';
      case 'open_to_couples': return romantic;
      case 'orientation': return switches.orientationEnabled;
      default: return true;
    }
  });
}

export function nextStep(current: OnboardingStep, draft: IntentDraft, switches: OnboardingSwitches): OnboardingStep | null {
  const steps = applicableSteps(draft, switches);
  const i = steps.indexOf(current);
  return i === -1 ? null : steps[i + 1] ?? null;
}

export function previousStep(current: OnboardingStep, draft: IntentDraft, switches: OnboardingSwitches): OnboardingStep | null {
  const steps = applicableSteps(draft, switches);
  const i = steps.indexOf(current);
  return i <= 0 ? null : steps[i - 1]!;
}

/** Main drinks offered for a situation; a closed couple can only pick beer. */
export function mainDrinkChoices(situation: Situation | null): Drink[] {
  return situation === 'closed_couple' ? ['beer'] : ['wine', 'coffee', 'cocktail', 'beer'];
}

/** Beer can be added to a romantic main drink (spec §1), except for closed couples. */
export function canAddBeer(situation: Situation | null, main: Drink | null): boolean {
  return situation !== 'closed_couple' && main !== null && main !== 'beer';
}

export function structureChoices(situation: Situation | null): Structure[] {
  return situation === 'consensual_relationship'
    ? STRUCTURES.filter((s) => s !== 'monogamous')
    : [...STRUCTURES];
}

/** Changing the situation drops the choices it makes invalid. */
export function withSituation(draft: IntentDraft, situation: Situation): IntentDraft {
  const next: IntentDraft = { ...draft, situation };
  if (situation === 'closed_couple') return { ...EMPTY_INTENT, situation, drinks: ['beer'] };
  if (next.structure && !structureChoices(situation).includes(next.structure)) {
    return { ...next, structure: null, composition: null };
  }
  return next;
}

/** Changing the drinks drops structure-related answers that no longer apply. */
export function withDrinks(draft: IntentDraft, drinks: Drink[]): IntentDraft {
  if (drinks.some(isRomantic)) return { ...draft, drinks };
  return { ...draft, drinks, structure: null, composition: null, openToCouples: false };
}

export function withStructure(draft: IntentDraft, structure: Structure): IntentDraft {
  return { ...draft, structure, composition: structure === 'polyamorous' ? draft.composition : null };
}

// Age -------------------------------------------------------------------------

/** Parses day/month/year typed by the user; null if the date does not exist. */
export function parseBirthDate(day: number, month: number, year: number): string | null {
  if (![day, month, year].every(Number.isInteger) || year < 1900) return null;
  const d = new Date(Date.UTC(year, month - 1, day));
  if (d.getUTCFullYear() !== year || d.getUTCMonth() !== month - 1 || d.getUTCDate() !== day) return null;
  return d.toISOString().slice(0, 10);
}

export function ageOn(birthDate: string, today: Date): number {
  const [y, m, d] = birthDate.split('-').map(Number) as [number, number, number];
  let age = today.getUTCFullYear() - y;
  const beforeBirthday = today.getUTCMonth() + 1 < m || (today.getUTCMonth() + 1 === m && today.getUTCDate() < d);
  if (beforeBirthday) age -= 1;
  return age;
}

export const MIN_AGE = 18;
export const isAdult = (birthDate: string, today: Date = new Date()) => ageOn(birthDate, today) >= MIN_AGE;

// Resume -----------------------------------------------------------------------

/** What the server knows about an onboarding in progress (from get_my_profile). */
export interface OnboardingProgress {
  status: 'onboarding' | 'active' | 'paused' | 'suspended' | 'closed';
  hasTermsConsent: boolean;
  birthDate: string | null;
  hasLocation: boolean;
  firstName: string | null;
  hasSensitiveConsent: boolean;
  hasSeekingGenders: boolean;
  hasIntent: boolean;
  promptsCount: number;
  photosCount: number;
  minPhotos: number;
  verificationStatus: 'unverified' | 'pending' | 'verified' | 'rejected';
}

/** First screen to show when the app reopens, or 'done' once onboarding is over. */
export function resumeStep(p: OnboardingProgress): OnboardingStep | 'done' {
  if (p.status !== 'onboarding') return 'done';
  // Nothing saved yet: start over with the account type (kept on the device, not on the server).
  if (!p.hasTermsConsent && !p.birthDate) return 'account_type';
  if (!p.hasTermsConsent || !p.birthDate) return 'age';
  if (!p.hasLocation) return 'location';
  if (!p.firstName) return 'identity';
  if (!p.hasSensitiveConsent) return 'sensitive_consent';
  // Sought genders are kept in memory until consent: if the app was closed in between, ask again.
  if (!p.hasSeekingGenders) return 'identity';
  if (!p.hasIntent) return 'situation';
  if (p.promptsCount < 3) return 'prompts';
  if (p.photosCount < p.minPhotos) return 'photos';
  if (p.verificationStatus === 'unverified' || p.verificationStatus === 'rejected') return 'selfie';
  return 'orientation';
}
