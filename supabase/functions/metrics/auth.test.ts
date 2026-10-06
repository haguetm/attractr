import { assertEquals } from 'jsr:@std/assert@1';
import { authorized, parseDays, safeEqual } from './auth.ts';

const secret = 'a'.repeat(40);
const req = (auth?: string) => new Request('http://x/metrics', { headers: auth ? { Authorization: auth } : {} });

Deno.test('only the configured token opens the dashboard', () => {
  assertEquals(authorized(req(`Bearer ${secret}`), secret), true);
  assertEquals(authorized(req(`Bearer ${secret}b`), secret), false);
  assertEquals(authorized(req(), secret), false);
  assertEquals(authorized(req(secret), secret), false);
});

Deno.test('a missing or weak secret refuses everyone', () => {
  assertEquals(authorized(req('Bearer '), ''), false);
  assertEquals(authorized(req('Bearer short'), 'short'), false);
});

Deno.test('constant-time comparison', () => {
  assertEquals(safeEqual('abc', 'abc'), true);
  assertEquals(safeEqual('abc', 'abd'), false);
  assertEquals(safeEqual('abc', 'abcd'), false);
});

Deno.test('the range is bounded', () => {
  assertEquals(parseDays(new URL('http://x/?days=30')), 30);
  assertEquals(parseDays(new URL('http://x/')), 90);
  assertEquals(parseDays(new URL('http://x/?days=3')), null);
  assertEquals(parseDays(new URL('http://x/?days=abc')), null);
});
