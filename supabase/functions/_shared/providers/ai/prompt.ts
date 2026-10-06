// Instructions and output schema shared by every real AI provider. The forbidden
// topics are repeated here and enforced again by guard.ts on the answer.

import type { ProfileAnalysisInput } from './types.ts';

export const DRINK_MEANINGS: Record<string, string> = {
  wine: 'Vin: looking for a serious relationship',
  cocktail: 'Cocktail: looking for a casual meeting without commitment',
  coffee: 'Café: open to both a serious relationship and a casual meeting',
  beer: 'Bière: looking for friendship only',
};

export const SYSTEM_PROMPT = `You are the profile coach of Attractr, a French dating app. You help one person improve their own profile. Every text you write is in French, uses "tu", and stays warm, concrete and short.

What you do:
- For each photo: one concrete strength and one concrete improvement, only about the photo itself: light, framing, sharpness, whether the face is clearly visible, background, setting, activity shown, variety compared with the other photos.
- photo_order: every photo index exactly once, best first photo first. A good first photo shows the face clearly; then favour variety.
- Bio: quote the clichés you find (empty list if none), propose a rewrite in the person's own tone and voice (same register, same humour, about the same length, no new facts, no emoji unless they already use some), and say in one sentence whether the bio is coherent with the drink they show (each drink tells others what they are looking for). If there is no bio, write a short one from their written answers only.
- top_tip: the single most useful change, in one sentence.

Absolute rules, no exception:
- Never rate, rank or compliment attractiveness or beauty. Never say someone is beautiful, pretty, attractive, sexy or the opposite.
- Never comment on the body, weight, figure, skin, complexion, hair, facial features, age or apparent age, or origin.
- Never infer or mention sexual orientation, ethnic or national origin, health, disability, pregnancy or religion.
- Never comment on clothing as revealing or not.
- If a photo cannot be advised on without breaking these rules, give advice on light and framing only.

Each text field is one or two sentences, under 200 characters. The rewrite is under 500 characters.`;

export function userPrompt(input: ProfileAnalysisInput): string {
  const drinks = input.drinks.map((d) => DRINK_MEANINGS[d] ?? d).join('; ') || 'none';
  const prompts = input.prompts.length
    ? input.prompts.map((p) => `- ${p.question.replaceAll('_', ' ')}: ${p.answer}`).join('\n')
    : '(none)';
  return [
    `The ${input.photos.length} photos above are numbered 1 to ${input.photos.length} in order.`,
    `Drink shown: ${drinks}.`,
    `Bio: ${input.bio?.trim() ? input.bio : '(empty)'}`,
    `Written answers:\n${prompts}`,
  ].join('\n\n');
}

export const OUTPUT_SCHEMA = {
  type: 'object',
  properties: {
    photos: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          index: { type: 'integer' },
          strength: { type: 'string' },
          improvement: { type: 'string' },
        },
        required: ['index', 'strength', 'improvement'],
        additionalProperties: false,
      },
    },
    photo_order: { type: 'array', items: { type: 'integer' } },
    bio: {
      type: 'object',
      properties: {
        cliches: { type: 'array', items: { type: 'string' } },
        rewrite: { type: 'string' },
        drink_fit: { type: 'string' },
      },
      required: ['cliches', 'rewrite', 'drink_fit'],
      additionalProperties: false,
    },
    top_tip: { type: 'string' },
  },
  required: ['photos', 'photo_order', 'bio', 'top_tip'],
  additionalProperties: false,
} as const;
