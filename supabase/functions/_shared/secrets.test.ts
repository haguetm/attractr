import { assertEquals } from 'jsr:@std/assert@1';
import { isCronCall, safeEqual } from './secrets.ts';

const secret = 'c'.repeat(40);
const req = (headers: Record<string, string>) => new Request('http://x/send-push', { method: 'POST', headers });

Deno.test('scheduled calls need the cron secret in X-Cron-Secret', () => {
  assertEquals(isCronCall(req({ 'X-Cron-Secret': secret }), secret), true);
  assertEquals(isCronCall(req({ 'X-Cron-Secret': secret.slice(1) }), secret), false);
  assertEquals(isCronCall(req({ Authorization: `Bearer ${secret}` }), secret), false);
  assertEquals(isCronCall(req({}), secret), false);
});

Deno.test('a missing or short cron secret refuses everyone', () => {
  assertEquals(isCronCall(req({ 'X-Cron-Secret': '' }), ''), false);
  assertEquals(isCronCall(req({ 'X-Cron-Secret': 'short' }), 'short'), false);
});

Deno.test('safeEqual compares whole strings', () => {
  assertEquals(safeEqual('abc', 'abc'), true);
  assertEquals(safeEqual('abc', 'abd'), false);
  assertEquals(safeEqual('abc', 'abcd'), false);
});
