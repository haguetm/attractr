import { assertEquals } from 'jsr:@std/assert@1';
import { forbiddenTerms, guardAnalysis } from '../_shared/providers/ai/guard.ts';
import { MockAiProvider } from '../_shared/providers/ai/mock.ts';

const input = {
  photos: [1, 2].map((index) => ({ index, image: new Uint8Array(), contentType: 'image/jpeg' as const })),
  bio: 'Croyante, j’aime la randonnée.',
  prompts: [],
  drinks: ['wine'],
};
const ctx = { photoCount: 2, sourceText: input.bio, bioMaxLength: 500 };

Deno.test('the mock answer passes the guard', async () => {
  const r = guardAnalysis(await new MockAiProvider('ok').analyze(input), ctx);
  assertEquals(r.ok, true);
});

Deno.test('a beauty compliment is rejected', async () => {
  const r = guardAnalysis(await new MockAiProvider('forbidden').analyze(input), ctx);
  assertEquals(r, { ok: false, reason: 'forbidden:beauty' });
});

Deno.test('every forbidden category is detected in commentary', () => {
  for (const [text, cat] of [
    ['Tu fais plus jeune que ton âge.', 'age'],
    ['Ta silhouette ressort bien.', 'body'],
    ['Ton teint est lumineux.', 'skin'],
    ['On devine tes origines.', 'origin'],
    ['Tu sembles hétéro.', 'orientation'],
    ['Pense à ta santé.', 'health'],
    ['Ta foi se voit.', 'religion'],
    ['Je te mets 8/10.', 'beauty'],
  ]) assertEquals(forbiddenTerms(text)[0]?.split(':')[0], cat, text);
});

Deno.test('ordinary photo advice is not flagged', () => {
  for (const text of ['Fais un gros plan en lumière naturelle.', 'Évite le contre-jour, photo en noir et blanc réussie.', 'Une belle lumière, montre une activité physique.', 'Ce type de photo marche bien.']) {
    assertEquals(forbiddenTerms(text), [], text);
  }
});

Deno.test('the rewrite may keep what the person wrote, not add to it', () => {
  assertEquals(forbiddenTerms('Croyante et fan de randonnée.', input.bio), []);
  assertEquals(forbiddenTerms('Musulmane et fan de randonnée.', input.bio).length, 1);
});

Deno.test('a wrong shape is rejected', () => {
  assertEquals(guardAnalysis({ photos: [] }, ctx).ok, false);
});
