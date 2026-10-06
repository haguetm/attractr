import type { ProfileAnalysisInput, ProfileAnalysisProvider } from './types.ts';

export type MockAiOutcome = 'ok' | 'forbidden' | 'error';

/**
 * Development provider; outcome set with app_config `providers.mock_ai_outcome`.
 * 'forbidden' returns an answer the output guard must reject; 'error' throws.
 */
export class MockAiProvider implements ProfileAnalysisProvider {
  readonly model = 'mock';

  constructor(private readonly outcome: MockAiOutcome = 'ok') {}

  analyze(input: ProfileAnalysisInput): Promise<unknown> {
    if (this.outcome === 'error') return Promise.reject(new Error('mock ai failure'));
    const n = input.photos.length;
    const order = Array.from({ length: n }, (_, i) => n - i);
    return Promise.resolve({
      photos: input.photos.map((p) => ({
        index: p.index,
        strength: p.index === 1 ? 'La lumière naturelle met bien ton visage en valeur.' : 'On voit une activité, ça donne envie d’en parler.',
        improvement: p.index === 1 ? 'Recadre un peu plus serré pour que ton visage occupe plus de place.' : 'Évite le contre-jour : place-toi face à la lumière.',
      })),
      photo_order: order,
      bio: {
        cliches: input.bio?.trim() ? [input.bio.trim().slice(0, 60)] : [],
        rewrite: input.bio?.trim() ? `${input.bio.trim()} (version plus concrète proposée par le mode démo)` : 'Toujours partant pour une expo le dimanche, et un bon débat ensuite.',
        drink_fit: this.outcome === 'forbidden' ? 'Tu es très belle, ça colle avec le vin.' : 'Ta bio colle bien avec la boisson que tu affiches.',
      },
      top_tip: 'Mets en premier la photo où l’on voit le mieux ton visage.',
    });
  }
}
