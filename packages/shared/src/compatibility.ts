// Mirror of private.match_drinks (supabase/migrations). The database is
// authoritative; this copy lets the seed tests check the dataset and documents
// the rule in one readable place. Keep both in sync (same cases in tests).
//
// Two profiles are compatible when at least one crossing of their drinks is
// compatible (spec §1), each crossing being checked on its own (DECISIONS Q1):
//   - beer x beer (friendship): each one's gender is in the other's friend genders (Q2);
//   - romantic crossing: sought genders both ways, structure compatibility (spec §2),
//     and polyamory compositions both ways (Q4).

import type { CompositionChoice, Drink, Gender, Structure } from './domain';
import { GENDERS } from './domain';

export const DRINK_COMPATIBILITY: Record<Drink, readonly Drink[]> = {
  wine: ['wine', 'coffee'],
  coffee: ['wine', 'coffee', 'cocktail'],
  cocktail: ['coffee', 'cocktail'],
  beer: ['beer'],
};

export const structuresCompatible = (a: Structure, b: Structure) =>
  a === b || a === 'open_to_explore' || b === 'open_to_explore';

export interface MatchProfile {
  gender: Gender;
  drinks: Drink[];
  seekingGenders: Gender[];
  friendGenders: Gender[];
  /** Null when not asked (beer only) or disabled in the country. */
  structure: Structure | null;
  composition: CompositionChoice | null;
}

/** Genders a polyamory composition asks for, or null when it sets no constraint. */
export function compositionGenders(c: CompositionChoice | null): Gender[] | null {
  if (!c || c.kinds.length === 0) return null;
  const out = new Set<Gender>();
  for (const kind of c.kinds) {
    switch (kind) {
      case 'one_woman': case 'two_women': out.add('woman'); break;
      case 'one_man': case 'two_men': out.add('man'); break;
      case 'woman_and_man': out.add('woman'); out.add('man'); break;
      case 'one_any': GENDERS.forEach((g) => out.add(g)); break;
      case 'three_plus': (c.threePlusGenders ?? GENDERS).forEach((g) => out.add(g)); break;
    }
  }
  return [...out];
}

function crossingOk(viewer: MatchProfile, candidate: MatchProfile, dv: Drink, dc: Drink): boolean {
  if (!DRINK_COMPATIBILITY[dv].includes(dc)) return false;
  if (dv === 'beer' && dc === 'beer') {
    return candidate.friendGenders.includes(viewer.gender) && viewer.friendGenders.includes(candidate.gender);
  }
  if (!viewer.seekingGenders.includes(candidate.gender) || !candidate.seekingGenders.includes(viewer.gender)) return false;
  if (viewer.structure && candidate.structure && !structuresCompatible(viewer.structure, candidate.structure)) return false;
  const vComp = compositionGenders(viewer.composition);
  const cComp = compositionGenders(candidate.composition);
  if (vComp && !vComp.includes(candidate.gender)) return false;
  if (cComp && !cComp.includes(viewer.gender)) return false;
  return true;
}

/** Candidate drinks through which the two profiles match (empty = not compatible). */
export function matchDrinks(viewer: MatchProfile, candidate: MatchProfile): Drink[] {
  const matched = new Set<Drink>();
  for (const dv of viewer.drinks) {
    for (const dc of candidate.drinks) {
      if (crossingOk(viewer, candidate, dv, dc)) matched.add(dc);
    }
  }
  return [...matched];
}

export const isCompatible = (a: MatchProfile, b: MatchProfile) => matchDrinks(a, b).length > 0;

// Distance -----------------------------------------------------------------------

export const DISTANCE_BUCKETS = ['lt5', 'lt10', 'lt25', 'lt50', 'lt100', 'gte100'] as const;
export type DistanceBucket = (typeof DISTANCE_BUCKETS)[number];

/** Public distances are shown as ranges only (spec §4). Mirrors private.distance_bucket. */
export function distanceBucket(km: number): DistanceBucket {
  if (km < 5) return 'lt5';
  if (km < 10) return 'lt10';
  if (km < 25) return 'lt25';
  if (km < 50) return 'lt50';
  if (km < 100) return 'lt100';
  return 'gte100';
}
