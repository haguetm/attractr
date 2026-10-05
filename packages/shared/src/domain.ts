// Domain vocabulary shared by the app, the seed generator and Edge Functions.
// Codes must stay identical to the SQL enums in supabase/migrations.

export const DRINKS = ['wine', 'coffee', 'cocktail', 'beer'] as const;
export type Drink = (typeof DRINKS)[number];

/** Drinks that carry a romantic or sexual intent (everything but beer). */
export const ROMANTIC_DRINKS: readonly Drink[] = ['wine', 'coffee', 'cocktail'];

export const GENDERS = ['woman', 'man', 'non_binary'] as const;
export type Gender = (typeof GENDERS)[number];

export const SITUATIONS = ['single', 'consensual_relationship', 'closed_couple'] as const;
export type Situation = (typeof SITUATIONS)[number];

export const STRUCTURES = [
  'monogamous',
  'open_to_explore',
  'open_relationship',
  'polyamorous',
] as const;
export type Structure = (typeof STRUCTURES)[number];

/** Polyamory "Je cherche" options (multi-select). */
export const COMPOSITIONS = [
  'one_woman',
  'one_man',
  'one_any',
  'woman_and_man',
  'two_women',
  'two_men',
  'three_plus',
] as const;
export type Composition = (typeof COMPOSITIONS)[number];

export interface CompositionChoice {
  kinds: Composition[];
  /** Only for `three_plus`: requested genders, or null for "peu importe". */
  threePlusGenders: Gender[] | null;
}

export const CONSENT_TYPES = ['terms', 'privacy', 'sensitive_data', 'ai_photo_analysis'] as const;
export type ConsentType = (typeof CONSENT_TYPES)[number];

export const isRomantic = (drink: Drink): boolean => ROMANTIC_DRINKS.includes(drink);
