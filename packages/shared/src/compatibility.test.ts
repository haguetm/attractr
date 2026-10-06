import { describe, expect, it } from 'vitest';
import { type MatchProfile, compositionGenders, distanceBucket, isCompatible, matchDrinks } from './compatibility';
import { DRINKS, GENDERS } from './domain';

const ALL = [...GENDERS];
const p = (patch: Partial<MatchProfile>): MatchProfile => ({
  gender: 'woman',
  drinks: ['wine'],
  seekingGenders: ['man'],
  friendGenders: ALL,
  structure: 'monogamous',
  composition: null,
  ...patch,
});
const woman = (patch: Partial<MatchProfile> = {}) => p({ gender: 'woman', seekingGenders: ['man'], ...patch });
const man = (patch: Partial<MatchProfile> = {}) => p({ gender: 'man', seekingGenders: ['woman'], ...patch });

describe('drink matrix (spec §1)', () => {
  const expected: Record<string, boolean> = {
    'wine-wine': true, 'wine-coffee': true, 'wine-cocktail': false, 'wine-beer': false,
    'coffee-coffee': true, 'coffee-cocktail': true, 'coffee-beer': false,
    'cocktail-cocktail': true, 'cocktail-beer': false, 'beer-beer': true,
  };
  for (const a of DRINKS) {
    for (const b of DRINKS) {
      const key = expected[`${a}-${b}`] ?? expected[`${b}-${a}`];
      it(`${a} x ${b} -> ${key}`, () => {
        const s = (d: typeof a) => (d === 'beer' ? null : 'open_to_explore' as const);
        expect(isCompatible(woman({ drinks: [a], structure: s(a) }), man({ drinks: [b], structure: s(b) }))).toBe(key);
      });
    }
  }
});

describe('sought genders', () => {
  it('must match both ways on romantic crossings', () => {
    expect(isCompatible(woman(), man())).toBe(true);
    expect(isCompatible(woman(), man({ seekingGenders: ['man'] }))).toBe(false);
    expect(isCompatible(woman({ seekingGenders: ['woman'] }), woman({ seekingGenders: ['woman'] }))).toBe(true);
  });

  it('do not apply to beer, friend genders do (Q2)', () => {
    const a = woman({ drinks: ['beer'], structure: null });
    const b = woman({ drinks: ['beer'], structure: null });
    expect(isCompatible(a, b)).toBe(true);
    expect(isCompatible(a, { ...b, friendGenders: ['man'] })).toBe(false);
  });
});

describe('structure (spec §2)', () => {
  it('follows the structure matrix', () => {
    expect(isCompatible(woman({ structure: 'monogamous' }), man({ structure: 'polyamorous' }))).toBe(false);
    expect(isCompatible(woman({ structure: 'open_relationship' }), man({ structure: 'polyamorous' }))).toBe(false);
    expect(isCompatible(woman({ structure: 'open_to_explore' }), man({ structure: 'polyamorous' }))).toBe(true);
    expect(isCompatible(woman({ structure: 'polyamorous' }), man({ structure: 'polyamorous' }))).toBe(true);
  });

  it('is ignored when disabled in a country (null)', () => {
    expect(isCompatible(woman({ structure: null }), man({ structure: 'polyamorous' }))).toBe(true);
  });
});

describe('crossings are independent (Q1)', () => {
  it('beer still matches when the romantic crossing fails', () => {
    const a = woman({ drinks: ['beer', 'wine'], structure: 'monogamous' });
    const b = man({ drinks: ['beer', 'wine'], structure: 'polyamorous' });
    expect(matchDrinks(a, b)).toEqual(['beer']);
  });

  it('reports every matching drink', () => {
    const a = woman({ drinks: ['beer', 'coffee'], structure: 'open_to_explore' });
    const b = man({ drinks: ['beer', 'cocktail'], structure: 'open_to_explore' });
    expect(matchDrinks(a, b).sort()).toEqual(['beer', 'cocktail']);
  });
});

describe('polyamory composition (Q4)', () => {
  const poly = (patch: Partial<MatchProfile>) => p({ structure: 'polyamorous', ...patch });

  it('maps each option to genders', () => {
    expect(compositionGenders({ kinds: ['two_women'], threePlusGenders: null })).toEqual(['woman']);
    expect(compositionGenders({ kinds: ['woman_and_man'], threePlusGenders: null })?.sort()).toEqual(['man', 'woman']);
    expect(compositionGenders({ kinds: ['three_plus'], threePlusGenders: null })?.sort()).toEqual([...ALL].sort());
    expect(compositionGenders({ kinds: ['three_plus'], threePlusGenders: ['non_binary'] })).toEqual(['non_binary']);
    expect(compositionGenders(null)).toBeNull();
  });

  it('the other person must match one of the requested genders', () => {
    const a = poly({ gender: 'woman', seekingGenders: ['man', 'woman'], composition: { kinds: ['two_women'], threePlusGenders: null } });
    expect(isCompatible(a, poly({ gender: 'man', seekingGenders: ['woman'] }))).toBe(false);
    expect(isCompatible(a, poly({ gender: 'woman', seekingGenders: ['woman'] }))).toBe(true);
  });

  it('applies both ways', () => {
    const a = poly({ gender: 'man', seekingGenders: ['woman'] });
    const b = poly({ gender: 'woman', seekingGenders: ['man'], composition: { kinds: ['one_woman'], threePlusGenders: null } });
    expect(isCompatible(a, b)).toBe(false);
  });
});

describe('distance buckets', () => {
  it.each([[0.4, 'lt5'], [4.99, 'lt5'], [5, 'lt10'], [24, 'lt25'], [49, 'lt50'], [99, 'lt100'], [500, 'gte100']] as const)(
    '%s km -> %s', (km, bucket) => expect(distanceBucket(km)).toBe(bucket),
  );
});
