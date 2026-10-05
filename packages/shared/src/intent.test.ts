import { describe, expect, it } from 'vitest';
import type { Drink } from './domain';
import { type IntentInput, validateIntent } from './intent';

const base: IntentInput = {
  situation: 'single',
  drinks: ['wine'],
  structure: 'monogamous',
  composition: null,
  openToCouples: false,
};
const v = (patch: Partial<IntentInput>, switches?: Parameters<typeof validateIntent>[1]) =>
  validateIntent({ ...base, ...patch }, switches);

describe('drink combinations', () => {
  const allowed: Drink[][] = [
    ['wine'], ['coffee'], ['cocktail'], ['beer'],
    ['beer', 'wine'], ['beer', 'coffee'], ['beer', 'cocktail'], ['wine', 'beer'],
  ];
  it.each(allowed)('accepts %s', (...drinks) => {
    const structure = drinks.every((d) => d === 'beer') ? null : 'monogamous';
    expect(v({ drinks, structure })).toBeNull();
  });

  it.each([
    [['wine', 'coffee']], [['wine', 'cocktail']], [['coffee', 'cocktail']],
  ] as Drink[][][])('rejects two romantic drinks %s', (drinks) => {
    expect(v({ drinks })).toBe('drinks_combination');
  });

  it('rejects zero, three or duplicated drinks', () => {
    expect(v({ drinks: [] })).toBe('drinks_count');
    expect(v({ drinks: ['beer', 'wine', 'coffee'] })).toBe('drinks_count');
    expect(v({ drinks: ['beer', 'beer'], structure: null })).toBe('drinks_duplicate');
  });
});

describe('situation', () => {
  it('closed couple is beer only', () => {
    expect(v({ situation: 'closed_couple', drinks: ['beer'], structure: null })).toBeNull();
    expect(v({ situation: 'closed_couple', drinks: ['beer', 'wine'] })).toBe('closed_couple_beer_only');
    expect(v({ situation: 'closed_couple', drinks: ['coffee'] })).toBe('closed_couple_beer_only');
  });

  it('consensual relationship excludes monogamy (Q3)', () => {
    expect(v({ situation: 'consensual_relationship', structure: 'monogamous' }))
      .toBe('structure_incoherent_with_situation');
    for (const structure of ['open_relationship', 'polyamorous', 'open_to_explore'] as const) {
      expect(v({ situation: 'consensual_relationship', structure })).toBeNull();
    }
  });
});

describe('structure', () => {
  it('is required with a romantic drink', () => {
    expect(v({ structure: null })).toBe('structure_required');
    expect(v({ drinks: ['beer', 'cocktail'], structure: null })).toBe('structure_required');
  });

  it('is forbidden with beer only', () => {
    expect(v({ drinks: ['beer'], structure: 'monogamous' })).toBe('structure_not_allowed');
  });

  it('must stay empty when disabled in the country', () => {
    const off = { structureEnabled: false, compositionEnabled: false };
    expect(v({ structure: null }, off)).toBeNull();
    expect(v({}, off)).toBe('structure_disabled_in_country');
  });
});

describe('polyamory composition', () => {
  const poly = { structure: 'polyamorous' as const };

  it('is accepted for polyamorous profiles', () => {
    expect(v({ ...poly, composition: { kinds: ['one_woman', 'two_men'], threePlusGenders: null } })).toBeNull();
    expect(v({ ...poly, composition: { kinds: ['three_plus'], threePlusGenders: null } })).toBeNull();
    expect(v({ ...poly, composition: { kinds: ['three_plus'], threePlusGenders: ['woman', 'non_binary'] } })).toBeNull();
  });

  it('is optional', () => {
    expect(v({ ...poly, composition: null })).toBeNull();
  });

  it('requires the polyamorous structure', () => {
    expect(v({ structure: 'open_to_explore', composition: { kinds: ['one_man'], threePlusGenders: null } }))
      .toBe('composition_requires_polyamory');
  });

  it('rejects empty or inconsistent choices', () => {
    expect(v({ ...poly, composition: { kinds: [], threePlusGenders: null } })).toBe('composition_empty');
    expect(v({ ...poly, composition: { kinds: ['one_man'], threePlusGenders: ['man'] } }))
      .toBe('composition_three_plus_genders');
    expect(v({ ...poly, composition: { kinds: ['three_plus'], threePlusGenders: [] } }))
      .toBe('composition_three_plus_genders');
  });

  it('must stay empty when disabled in the country', () => {
    expect(v({ ...poly, composition: { kinds: ['one_man'], threePlusGenders: null } },
      { structureEnabled: true, compositionEnabled: false })).toBe('composition_disabled_in_country');
  });
});

describe('open to couples', () => {
  it('requires a romantic drink', () => {
    expect(v({ openToCouples: true })).toBeNull();
    expect(v({ drinks: ['beer'], structure: null, openToCouples: true }))
      .toBe('open_to_couples_requires_romantic');
  });
});
