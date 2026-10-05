// Deterministic generator of the 100 fictional seed profiles (spec §13).
// No real photos: the app renders initials when a profile has no photo.

import {
  type CompositionChoice,
  type Drink,
  type Gender,
  type Situation,
  type Structure,
  isRomantic,
  validateIntent,
} from '@attractr/shared';

export interface SeedProfile {
  id: string;
  phone: string;
  firstName: string;
  birthDate: string;
  gender: Gender;
  seekingGenders: Gender[];
  situation: Situation;
  drinks: Drink[];
  structure: Structure | null;
  composition: CompositionChoice | null;
  openToCouples: boolean;
  orientation: string | null;
  orientationVisible: boolean;
  verified: boolean;
  city: string;
  lat: number;
  lon: number;
  bio: string | null;
  prompts: { questionCode: string; answer: string }[];
  lastActiveHoursAgo: number;
  alcoholFreeIcons: boolean;
}

export const CITIES = [
  { name: 'Paris', lat: 48.8566, lon: 2.3522 },
  { name: 'Marseille', lat: 43.2965, lon: 5.3698 },
  { name: 'Lyon', lat: 45.764, lon: 4.8357 },
  { name: 'Toulouse', lat: 43.6047, lon: 1.4442 },
  { name: 'Nice', lat: 43.7102, lon: 7.262 },
  { name: 'Nantes', lat: 47.2184, lon: -1.5536 },
  { name: 'Montpellier', lat: 43.6119, lon: 3.8772 },
  { name: 'Strasbourg', lat: 48.5734, lon: 7.7521 },
  { name: 'Bordeaux', lat: 44.8378, lon: -0.5792 },
  { name: 'Lille', lat: 50.6292, lon: 3.0573 },
] as const;

export const PROFILE_COUNT = 100;
const REFERENCE_YEAR = 2026;

const NAMES: Record<Gender, string[]> = {
  woman: ['Léa', 'Chloé', 'Manon', 'Inès', 'Jade', 'Sarah', 'Lucie', 'Emma', 'Zoé', 'Clara',
          'Louise', 'Alice', 'Nora', 'Yasmine', 'Margaux', 'Julie', 'Anaïs', 'Elsa', 'Mila', 'Rose'],
  man: ['Lucas', 'Hugo', 'Thomas', 'Nathan', 'Karim', 'Louis', 'Théo', 'Antoine', 'Mehdi', 'Jules',
        'Arthur', 'Paul', 'Raphaël', 'Malik', 'Victor', 'Simon', 'Adam', 'Baptiste', 'Yanis', 'Martin'],
  non_binary: ['Camille', 'Alex', 'Charlie', 'Sasha', 'Eden', 'Noa', 'Andréa', 'Maxime'],
};

const PROMPT_ANSWERS: Record<string, string[]> = {
  perfect_sunday: ['Marché le matin, sieste l\'après-midi.', 'Une rando et un bon repas.', 'Brunch qui dure jusqu\'à 16 h.'],
  green_flag: ['Quelqu\'un qui pose des questions.', 'Rire de ses propres blagues ratées.', 'Être à l\'heure.'],
  unpopular_opinion: ['Le ketchup va avec tout.', 'Les séries sont trop longues.', 'L\'hiver est la meilleure saison.'],
  ideal_first_date: ['Une balade et une glace.', 'Un musée puis un café.', 'Un concert dans une petite salle.'],
  currently_learning: ['La guitare, lentement.', 'L\'espagnol avec une appli.', 'La poterie.'],
  never_without: ['Mes écouteurs.', 'Un livre dans le sac.', 'Mon vélo.'],
  best_travel_memory: ['Un lever de soleil au Portugal.', 'Un train de nuit en Italie.', 'Camper en Bretagne sous la pluie.'],
  makes_me_laugh: ['Les jeux de mots nuls.', 'Les vidéos de chats.', 'Mes amis, surtout.'],
  simple_pleasure: ['Le pain chaud.', 'Les draps propres.', 'Une terrasse au soleil.'],
  looking_for_someone_who: ['Aime les discussions tard le soir.', 'Ne se prend pas trop au sérieux.', 'Aime bouger le week-end.'],
};

const BIOS = [
  'Curieux·se de tout, surtout des gens.',
  'Je cuisine mieux que je ne danse.',
  'Toujours partant·e pour une expo ou un ciné.',
  'Fan de randonnée et de jeux de société.',
  'Nouvelle ville, nouvelles rencontres.',
];

const DRINK_COMBOS: Drink[][] = [
  ['wine'], ['coffee'], ['cocktail'], ['beer'], ['beer', 'wine'], ['beer', 'coffee'], ['beer', 'cocktail'],
];

const ALL_COMPOSITION_KINDS: CompositionChoice['kinds'] = [
  'one_woman', 'one_man', 'one_any', 'woman_and_man', 'two_women', 'two_men', 'three_plus',
];

type IntentOverride = Pick<SeedProfile, 'situation' | 'drinks' | 'structure' | 'composition'> &
  Partial<Pick<SeedProfile, 'openToCouples' | 'verified'>>;

/**
 * Fixed cases placed first so every rule combination exists in the seed,
 * whatever the random fill produces (spec §13).
 */
const GUARANTEED: IntentOverride[] = [
  { situation: 'single', drinks: ['wine'], structure: 'monogamous', composition: null },
  { situation: 'single', drinks: ['coffee'], structure: 'open_to_explore', composition: null, openToCouples: true },
  { situation: 'single', drinks: ['cocktail'], structure: 'open_relationship', composition: null },
  { situation: 'single', drinks: ['beer'], structure: null, composition: null },
  { situation: 'single', drinks: ['beer', 'wine'], structure: 'polyamorous',
    composition: { kinds: ['one_woman'], threePlusGenders: null } },
  { situation: 'single', drinks: ['beer', 'coffee'], structure: 'monogamous', composition: null, verified: false },
  { situation: 'single', drinks: ['beer', 'cocktail'], structure: 'open_to_explore', composition: null, openToCouples: true },
  { situation: 'closed_couple', drinks: ['beer'], structure: null, composition: null },
  { situation: 'closed_couple', drinks: ['beer'], structure: null, composition: null, verified: false },
  { situation: 'consensual_relationship', drinks: ['coffee'], structure: 'open_relationship', composition: null, openToCouples: true },
  { situation: 'consensual_relationship', drinks: ['wine'], structure: 'polyamorous',
    composition: { kinds: ['woman_and_man', 'two_women'], threePlusGenders: null } },
  { situation: 'consensual_relationship', drinks: ['cocktail'], structure: 'open_to_explore', composition: null },
  { situation: 'single', drinks: ['cocktail'], structure: 'polyamorous',
    composition: { kinds: ['three_plus'], threePlusGenders: null } },
  { situation: 'single', drinks: ['coffee'], structure: 'polyamorous',
    composition: { kinds: ['three_plus', 'one_any'], threePlusGenders: ['woman', 'non_binary'] } },
  { situation: 'single', drinks: ['wine'], structure: 'polyamorous', composition: null },
  { situation: 'consensual_relationship', drinks: ['beer', 'coffee'], structure: 'polyamorous',
    composition: { kinds: ['two_men', 'one_man'], threePlusGenders: null }, openToCouples: true },
];

/** mulberry32: small deterministic PRNG so the seed file is reproducible. */
function prng(seed: number) {
  let a = seed >>> 0;
  const next = () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  const pick = <T>(items: readonly T[]): T => items[Math.floor(next() * items.length)]!;
  const weighted = <T>(items: readonly (readonly [T, number])[]): T => {
    let r = next() * items.reduce((s, [, w]) => s + w, 0);
    for (const [item, w] of items) if ((r -= w) < 0) return item;
    return items[items.length - 1]![0];
  };
  const sample = <T>(items: readonly T[], n: number): T[] => {
    const copy = [...items];
    for (let i = copy.length - 1; i > 0; i--) {
      const j = Math.floor(next() * (i + 1));
      [copy[i], copy[j]] = [copy[j]!, copy[i]!];
    }
    return copy.slice(0, n);
  };
  return { next, pick, weighted, sample };
}

type Rng = ReturnType<typeof prng>;

function randomIntent(rng: Rng): IntentOverride {
  const situation = rng.weighted<Situation>([['single', 70], ['consensual_relationship', 18], ['closed_couple', 12]]);
  const drinks = situation === 'closed_couple'
    ? (['beer'] as Drink[])
    : rng.weighted<Drink[]>(DRINK_COMBOS.map((c) => [c, c.length === 1 && c[0] === 'beer' ? 10 : 15] as const));
  let structure: Structure | null = null;
  if (drinks.some(isRomantic)) {
    structure = situation === 'consensual_relationship'
      ? rng.pick<Structure>(['open_relationship', 'polyamorous', 'open_to_explore'])
      : rng.weighted<Structure>([['monogamous', 40], ['open_to_explore', 25], ['open_relationship', 15], ['polyamorous', 20]]);
  }
  let composition: CompositionChoice | null = null;
  if (structure === 'polyamorous' && rng.next() < 0.7) {
    const kinds = rng.sample(ALL_COMPOSITION_KINDS, 1 + Math.floor(rng.next() * 2));
    const threePlusGenders = kinds.includes('three_plus') && rng.next() < 0.5
      ? rng.sample<Gender>(['woman', 'man', 'non_binary'], 1 + Math.floor(rng.next() * 2))
      : null;
    composition = { kinds, threePlusGenders };
  }
  return { situation, drinks, structure, composition };
}

function seekingFor(gender: Gender, rng: Rng): Gender[] {
  if (gender === 'woman') return rng.weighted<Gender[]>([[['man'], 70], [['woman'], 15], [['woman', 'man', 'non_binary'], 15]]);
  if (gender === 'man') return rng.weighted<Gender[]>([[['woman'], 70], [['man'], 15], [['woman', 'man'], 15]]);
  return rng.weighted<Gender[]>([[['woman', 'man', 'non_binary'], 50], [['woman', 'non_binary'], 25], [['man', 'non_binary'], 25]]);
}

function orientationFor(gender: Gender, seeking: Gender[], rng: Rng): string {
  if (seeking.length > 1) return rng.pick(['bisexual', 'pansexual', 'queer']);
  if (gender === 'non_binary') return rng.pick(['queer', 'pansexual', 'questioning']);
  if (seeking[0] === gender) return gender === 'woman' ? 'lesbian' : 'gay';
  return rng.pick(['heterosexual', 'heterosexual', 'heterosexual', 'asexual']);
}

const pad = (n: number, len: number) => String(n).padStart(len, '0');

export function buildProfiles(seed = 20261005): SeedProfile[] {
  const rng = prng(seed);
  const profiles: SeedProfile[] = [];
  const usedNames = new Map<string, number>();

  for (let i = 0; i < PROFILE_COUNT; i++) {
    const city = CITIES[i % CITIES.length]!;
    const gender = rng.weighted<Gender>([['woman', 45], ['man', 45], ['non_binary', 10]]);
    const seekingGenders = seekingFor(gender, rng);
    const intent = GUARANTEED[i] ?? randomIntent(rng);
    const romantic = intent.drinks.some(isRomantic);

    const baseName = rng.pick(NAMES[gender]);
    const seen = usedNames.get(baseName) ?? 0;
    usedNames.set(baseName, seen + 1);

    // Uniform position within 6 km of the city centre; snapped to ~1 km in SQL.
    const r = 6 * Math.sqrt(rng.next());
    const theta = 2 * Math.PI * rng.next();
    const lat = city.lat + (r * Math.cos(theta)) / 111;
    const lon = city.lon + (r * Math.sin(theta)) / (111 * Math.cos((city.lat * Math.PI) / 180));

    const age = 19 + Math.floor(rng.next() * 40);
    const birthDate = `${REFERENCE_YEAR - age}-${pad(1 + Math.floor(rng.next() * 12), 2)}-${pad(1 + Math.floor(rng.next() * 28), 2)}`;
    const hasOrientation = rng.next() < 0.5;

    const profile: SeedProfile = {
      id: `00000000-0000-4000-8000-${pad(i + 1, 12)}`,
      // ARCEP range reserved for fiction: 06 39 98 10 00 to 06 39 98 10 99.
      phone: `33639981${pad(i, 3)}`,
      firstName: seen === 0 ? baseName : `${baseName} ${String.fromCharCode(65 + seen)}.`,
      birthDate,
      gender,
      seekingGenders,
      ...intent,
      openToCouples: intent.openToCouples ?? (romantic && rng.next() < 0.35),
      orientation: hasOrientation ? orientationFor(gender, seekingGenders, rng) : null,
      orientationVisible: hasOrientation && rng.next() < 0.7,
      verified: intent.verified ?? rng.next() < 0.8,
      city: city.name,
      lat: Number(lat.toFixed(6)),
      lon: Number(lon.toFixed(6)),
      bio: rng.next() < 0.5 ? rng.pick(BIOS) : null,
      prompts: rng.sample(Object.keys(PROMPT_ANSWERS), 3).map((questionCode) => ({
        questionCode,
        answer: rng.pick(PROMPT_ANSWERS[questionCode]!),
      })),
      lastActiveHoursAgo: Math.floor(rng.next() * 240),
      alcoholFreeIcons: rng.next() < 0.15,
    };

    const error = validateIntent(profile);
    if (error) throw new Error(`Seed profile ${i} is invalid: ${error}`);
    profiles.push(profile);
  }
  return profiles;
}

