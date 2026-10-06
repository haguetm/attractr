import { assertEquals } from 'jsr:@std/assert@1';
import { MockModerationProvider } from '../_shared/providers/moderation/mock.ts';
import { selfieProvider } from '../_shared/providers/selfie/index.ts';
import { MockSelfieProvider } from '../_shared/providers/selfie/mock.ts';

const input = { image: new Uint8Array(), contentType: 'image/jpeg', subjectId: 'u1', declaredAge: 30 };

Deno.test('mock selfie outcomes drive every branch of the SQL rules', async () => {
  assertEquals(await new MockSelfieProvider('pass').verify(input), { live: true, estimatedAge: 30, confidence: 0.95, faceId: 'mock-face-u1' });
  assertEquals((await new MockSelfieProvider('retake').verify(input)).live, false);
  assertEquals((await new MockSelfieProvider('minor').verify(input)).estimatedAge, 15);
  assertEquals((await new MockSelfieProvider('review').verify(input)).confidence, 0.4);
  const a = await new MockSelfieProvider('duplicate').verify(input);
  const b = await new MockSelfieProvider('duplicate').verify({ ...input, subjectId: 'u2' });
  assertEquals(a.faceId, b.faceId);
});

Deno.test('mock moderation scores match the configured outcome', async () => {
  const img = { image: new Uint8Array(), contentType: 'image/jpeg' };
  assertEquals((await new MockModerationProvider('approve').moderate(img)).nudity < 0.5, true);
  assertEquals((await new MockModerationProvider('review').moderate(img)).nudity, 0.6);
  assertEquals((await new MockModerationProvider('reject').moderate(img)).nudity >= 0.9, true);
});

Deno.test('the provider factory reads the mock outcome from app_config', async () => {
  Deno.env.set('APP_ENV', 'development');
  const config = {
    get: (key: string) =>
      Promise.resolve(({ 'providers.mode': 'mock', 'providers.mock_selfie_outcome': 'minor' } as Record<string, unknown>)[key] ?? null),
  };
  const provider = await selfieProvider(config);
  assertEquals((await provider.verify(input)).estimatedAge, 15);
  Deno.env.delete('APP_ENV');
});

Deno.test('without APP_ENV on a hosted project, mocks are refused', async () => {
  const config = { get: () => Promise.resolve('mock') };
  await selfieProvider(config).then(
    () => { throw new Error('should refuse'); },
    (e: Error) => assertEquals(e.message.includes('refused in production'), true),
  );
});
