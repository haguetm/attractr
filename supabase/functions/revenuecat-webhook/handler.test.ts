import { assertEquals, assertRejects } from 'jsr:@std/assert@1';
import { RevenueCatRewardsProvider } from '../_shared/providers/rewards/revenuecat.ts';
import { extractEvent, isAuthorized } from './handler.ts';

Deno.test('webhook authorization uses the shared secret', () => {
  assertEquals(isAuthorized('s3cret', 's3cret'), true);
  assertEquals(isAuthorized('Bearer s3cret', 's3cret'), true);
  assertEquals(isAuthorized('wrong', 's3cret'), false);
  assertEquals(isAuthorized(null, 's3cret'), false);
  assertEquals(isAuthorized('s3cret', undefined), false);
});

Deno.test('events need an id and a type', () => {
  assertEquals(extractEvent({ event: { id: 'e1', type: 'RENEWAL' } }), { id: 'e1', type: 'RENEWAL' });
  assertEquals(extractEvent({ event: { type: 'RENEWAL' } }), null);
  assertEquals(extractEvent(null), null);
});

Deno.test('RevenueCat promotional grant calls the REST API', async () => {
  const calls: { url: string; body: string }[] = [];
  const provider = new RevenueCatRewardsProvider('sk_test', 'premium', (url, init) => {
    calls.push({ url: String(url), body: String(init?.body) });
    return Promise.resolve(new Response('{}', { status: 201 }));
  });
  await provider.grantFreeMonths('user-1', 1);
  assertEquals(calls[0], {
    url: 'https://api.revenuecat.com/v1/subscribers/user-1/entitlements/premium/promotional',
    body: '{"duration":"monthly"}',
  });
  await assertRejects(() => provider.grantFreeMonths('user-1', 5), Error, 'unsupported duration');
});
