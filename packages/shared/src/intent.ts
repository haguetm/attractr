// Client-side mirror of private.validate_intent (supabase/migrations).
// The database is authoritative; this copy only drives the onboarding UI.
// Keep both in sync: the same cases are tested in intent.test.ts and supabase/tests.

import {
  type CompositionChoice,
  type Drink,
  type Situation,
  type Structure,
  isRomantic,
} from './domain';

export interface IntentInput {
  situation: Situation;
  drinks: Drink[];
  structure: Structure | null;
  composition: CompositionChoice | null;
  openToCouples: boolean;
}

/** Country-level switches (country_config); disabled fields must stay empty. */
export interface IntentFieldSwitches {
  structureEnabled: boolean;
  compositionEnabled: boolean;
}

export type IntentError =
  | 'drinks_count'
  | 'drinks_duplicate'
  | 'drinks_combination'
  | 'closed_couple_beer_only'
  | 'structure_required'
  | 'structure_not_allowed'
  | 'structure_disabled_in_country'
  | 'structure_incoherent_with_situation'
  | 'composition_requires_polyamory'
  | 'composition_disabled_in_country'
  | 'composition_empty'
  | 'composition_three_plus_genders'
  | 'open_to_couples_requires_romantic';

const ALL_ENABLED: IntentFieldSwitches = { structureEnabled: true, compositionEnabled: true };

/** Structures allowed when already in a relationship with the partners' consent (DECISIONS Q3). */
const CONSENSUAL_STRUCTURES: readonly Structure[] = [
  'open_relationship',
  'polyamorous',
  'open_to_explore',
];

/** Returns the first rule violated, or null when the intent is valid. */
export function validateIntent(
  input: IntentInput,
  switches: IntentFieldSwitches = ALL_ENABLED,
): IntentError | null {
  const { drinks, situation, structure, composition, openToCouples } = input;

  if (drinks.length < 1 || drinks.length > 2) return 'drinks_count';
  if (new Set(drinks).size !== drinks.length) return 'drinks_duplicate';
  if (drinks.length === 2 && !drinks.includes('beer')) return 'drinks_combination';
  if (situation === 'closed_couple' && !(drinks.length === 1 && drinks[0] === 'beer')) {
    return 'closed_couple_beer_only';
  }

  const romantic = drinks.some(isRomantic);

  if (!romantic || !switches.structureEnabled) {
    if (structure !== null) {
      return romantic ? 'structure_disabled_in_country' : 'structure_not_allowed';
    }
  } else {
    if (structure === null) return 'structure_required';
    if (situation === 'consensual_relationship' && !CONSENSUAL_STRUCTURES.includes(structure)) {
      return 'structure_incoherent_with_situation';
    }
  }

  if (composition !== null) {
    if (!switches.compositionEnabled) return 'composition_disabled_in_country';
    if (structure !== 'polyamorous') return 'composition_requires_polyamory';
    if (composition.kinds.length === 0) return 'composition_empty';
    const threePlus = composition.kinds.includes('three_plus');
    if (!threePlus && composition.threePlusGenders !== null) return 'composition_three_plus_genders';
    if (threePlus && composition.threePlusGenders !== null && composition.threePlusGenders.length === 0) {
      return 'composition_three_plus_genders';
    }
  }

  if (openToCouples && !romantic) return 'open_to_couples_requires_romantic';

  return null;
}
