import { assertEquals } from 'jsr:@std/assert@1';
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
