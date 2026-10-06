import { GENDERS, isCompatible, validateIntent } from '@attractr/shared';
import { describe, expect, it } from 'vitest';
import { CITIES, buildProfiles } from './profiles';

const profiles = buildProfiles();
const key = (drinks: string[]) => [...drinks].sort().join('+');

describe('seed coverage (spec §13)', () => {
  it('has 100 valid profiles, 10 per city', () => {
    expect(profiles).toHaveLength(100);
    for (const city of CITIES) expect(profiles.filter((p) => p.city === city.name)).toHaveLength(10);
    for (const p of profiles) expect(validateIntent(p)).toBeNull();
  });

  it('is deterministic', () => {
    expect(buildProfiles()).toEqual(profiles);
  });

  it('covers every drink combination', () => {
    const combos = new Set(profiles.map((p) => key(p.drinks)));
    for (const c of ['wine', 'coffee', 'cocktail', 'beer', 'beer+wine', 'beer+coffee', 'beer+cocktail']) {
      expect(combos).toContain(c);
    }
  });

  it('covers every structure, situation and gender', () => {
    const structures = new Set(profiles.map((p) => p.structure));
    for (const s of ['monogamous', 'open_to_explore', 'open_relationship', 'polyamorous']) expect(structures).toContain(s);
    const situations = new Set(profiles.map((p) => p.situation));
    for (const s of ['single', 'consensual_relationship', 'closed_couple']) expect(situations).toContain(s);
    const genders = new Set(profiles.map((p) => p.gender));
    for (const g of ['woman', 'man', 'non_binary']) expect(genders).toContain(g);
  });

  it('covers varied polyamory compositions', () => {
    const withComposition = profiles.filter((p) => p.composition);
    expect(withComposition.length).toBeGreaterThanOrEqual(4);
    expect(withComposition.some((p) => p.composition!.kinds.includes('three_plus') && p.composition!.threePlusGenders === null)).toBe(true);
    expect(withComposition.some((p) => p.composition!.threePlusGenders?.length)).toBe(true);
    expect(withComposition.some((p) => p.composition!.kinds.length > 1)).toBe(true);
    expect(profiles.some((p) => p.structure === 'polyamorous' && !p.composition)).toBe(true);
  });

  it('covers open-to-couples, verified and unverified profiles', () => {
    expect(profiles.some((p) => p.openToCouples)).toBe(true);
    expect(profiles.some((p) => p.verified)).toBe(true);
    expect(profiles.some((p) => !p.verified)).toBe(true);
    expect(profiles.some((p) => p.situation === 'closed_couple' && !p.verified)).toBe(true);
  });

  it('uses only fictional phone numbers and unique ids', () => {
    expect(new Set(profiles.map((p) => p.id)).size).toBe(100);
    for (const p of profiles) expect(p.phone).toMatch(/^33639981\d{3}$/);
  });

  it('respects field limits', () => {
    for (const p of profiles) {
      expect(p.prompts).toHaveLength(3);
      for (const pr of p.prompts) expect(pr.answer.length).toBeLessThanOrEqual(150);
      expect((p.bio ?? '').length).toBeLessThanOrEqual(300);
      expect(p.firstName.length).toBeLessThanOrEqual(40);
    }
  });
});

describe('seed feeds are not empty (phase 3)', () => {
  const asMatch = (p: (typeof profiles)[number]) => ({
    gender: p.gender,
    drinks: p.drinks,
    seekingGenders: p.seekingGenders,
    friendGenders: [...GENDERS],
    structure: p.structure,
    composition: p.composition,
  });

  it('almost every profile has at least one compatible profile', () => {
    const lonely = profiles.filter((a) => !profiles.some((b) => a !== b && isCompatible(asMatch(a), asMatch(b))));
    expect(lonely.length).toBeLessThanOrEqual(5);
  });

  it('has compatible pairs inside the same city, for the default radius', () => {
    const pairs = profiles.filter((a) =>
      profiles.some((b) => a !== b && a.city === b.city && isCompatible(asMatch(a), asMatch(b))));
    expect(pairs.length).toBeGreaterThanOrEqual(40);
  });

  it('stores areas and a reserved test email for impersonation', () => {
    for (const p of profiles) {
      expect(p.email).toMatch(/^seed-\d{3}@attractr\.test$/);
      expect(p.departmentCode).toMatch(/^\d{2}$/);
    }
  });
});
