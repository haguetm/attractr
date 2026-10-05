import { describe, expect, it } from 'vitest';
import {
  EMPTY_INTENT,
  type IntentDraft,
  type OnboardingSwitches,
  ageOn,
  applicableSteps,
  canAddBeer,
  isAdult,
  mainDrinkChoices,
  nextStep,
  parseBirthDate,
  previousStep,
  resumeStep,
  structureChoices,
  withDrinks,
  withSituation,
  withStructure,
} from './onboarding';

const ALL_ON: OnboardingSwitches = { structureEnabled: true, compositionEnabled: true, orientationEnabled: true };
const draft = (patch: Partial<IntentDraft>): IntentDraft => ({ ...EMPTY_INTENT, situation: 'single', ...patch });

describe('applicable steps', () => {
  it('follows the spec order for a polyamorous romantic profile', () => {
    expect(applicableSteps(draft({ drinks: ['wine'], structure: 'polyamorous' }), ALL_ON)).toEqual([
      'age', 'location', 'identity', 'sensitive_consent', 'account_type', 'situation', 'drinks',
      'structure', 'composition', 'open_to_couples', 'prompts', 'photos', 'selfie', 'orientation',
    ]);
  });

  it('skips structure, composition and open-to-couples with beer only', () => {
    const steps = applicableSteps(draft({ drinks: ['beer'] }), ALL_ON);
    expect(steps).not.toContain('structure');
    expect(steps).not.toContain('composition');
    expect(steps).not.toContain('open_to_couples');
  });

  it('asks composition only for polyamory', () => {
    expect(applicableSteps(draft({ drinks: ['coffee'], structure: 'open_to_explore' }), ALL_ON)).not.toContain('composition');
  });

  it('hides fields disabled in the country', () => {
    const off = { structureEnabled: false, compositionEnabled: false, orientationEnabled: false };
    const steps = applicableSteps(draft({ drinks: ['wine'], structure: 'polyamorous' }), off);
    expect(steps).not.toContain('structure');
    expect(steps).not.toContain('composition');
    expect(steps).not.toContain('orientation');
    expect(steps).toContain('open_to_couples');
  });

  it('navigates around skipped steps', () => {
    const beer = draft({ drinks: ['beer'] });
    expect(nextStep('drinks', beer, ALL_ON)).toBe('prompts');
    expect(previousStep('prompts', beer, ALL_ON)).toBe('drinks');
    expect(nextStep('orientation', beer, ALL_ON)).toBeNull();
    expect(previousStep('age', beer, ALL_ON)).toBeNull();
  });
});

describe('choices', () => {
  it('closed couple only gets beer', () => {
    expect(mainDrinkChoices('closed_couple')).toEqual(['beer']);
    expect(canAddBeer('closed_couple', 'beer')).toBe(false);
    expect(mainDrinkChoices('single')).toHaveLength(4);
  });

  it('beer can be added to a romantic drink only', () => {
    expect(canAddBeer('single', 'wine')).toBe(true);
    expect(canAddBeer('single', 'beer')).toBe(false);
    expect(canAddBeer('single', null)).toBe(false);
  });

  it('consensual relationship excludes monogamy (Q3)', () => {
    expect(structureChoices('consensual_relationship')).not.toContain('monogamous');
    expect(structureChoices('single')).toContain('monogamous');
  });
});

describe('draft transitions', () => {
  it('closed couple resets to beer only', () => {
    const d = withSituation(draft({ drinks: ['wine'], structure: 'polyamorous', openToCouples: true }), 'closed_couple');
    expect(d).toEqual({ ...EMPTY_INTENT, situation: 'closed_couple', drinks: ['beer'] });
  });

  it('consensual relationship drops a monogamous structure', () => {
    const d = withSituation(draft({ drinks: ['wine'], structure: 'monogamous' }), 'consensual_relationship');
    expect(d.structure).toBeNull();
  });

  it('beer only drops structure, composition and open-to-couples', () => {
    const d = withDrinks(draft({ drinks: ['wine'], structure: 'polyamorous', openToCouples: true,
      composition: { kinds: ['one_man'], threePlusGenders: null } }), ['beer']);
    expect([d.structure, d.composition, d.openToCouples]).toEqual([null, null, false]);
  });

  it('leaving polyamory drops the composition', () => {
    const d = withStructure(draft({ structure: 'polyamorous', composition: { kinds: ['one_man'], threePlusGenders: null } }), 'monogamous');
    expect(d.composition).toBeNull();
  });
});

describe('age', () => {
  const today = new Date(Date.UTC(2026, 9, 5)); // 2026-10-05

  it('parses only real dates', () => {
    expect(parseBirthDate(5, 10, 2000)).toBe('2000-10-05');
    expect(parseBirthDate(31, 2, 2000)).toBeNull();
    expect(parseBirthDate(1, 1, 1850)).toBeNull();
  });

  it('computes age around the birthday', () => {
    expect(ageOn('2008-10-05', today)).toBe(18);
    expect(ageOn('2008-10-06', today)).toBe(17);
    expect(isAdult('2008-10-05', today)).toBe(true);
    expect(isAdult('2008-10-06', today)).toBe(false);
  });
});

describe('resumeStep', () => {
  const base = {
    status: 'onboarding' as const, hasTermsConsent: true, birthDate: '1995-01-01', hasLocation: true,
    firstName: 'Léa', hasSensitiveConsent: true, hasSeekingGenders: true, hasIntent: true,
    promptsCount: 3, photosCount: 2, minPhotos: 2, verificationStatus: 'pending' as const,
  };

  it('walks the steps in order', () => {
    expect(resumeStep({ ...base, hasTermsConsent: false })).toBe('age');
    expect(resumeStep({ ...base, hasLocation: false })).toBe('location');
    expect(resumeStep({ ...base, firstName: null })).toBe('identity');
    expect(resumeStep({ ...base, hasSensitiveConsent: false })).toBe('sensitive_consent');
    expect(resumeStep({ ...base, hasSeekingGenders: false })).toBe('identity');
    expect(resumeStep({ ...base, hasIntent: false })).toBe('account_type');
    expect(resumeStep({ ...base, promptsCount: 2 })).toBe('prompts');
    expect(resumeStep({ ...base, photosCount: 1 })).toBe('photos');
    expect(resumeStep({ ...base, verificationStatus: 'unverified' })).toBe('selfie');
    expect(resumeStep(base)).toBe('orientation');
  });

  it('is done once the profile left onboarding', () => {
    expect(resumeStep({ ...base, status: 'active', hasLocation: false })).toBe('done');
  });
});
