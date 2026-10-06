import { assertEquals } from 'jsr:@std/assert@1';
import { ExpoPushSender } from '../_shared/providers/push/expo.ts';
import { type OutboxRow, TEXTS, planPushes, settle } from './outbox.ts';

const row = (id: number, tokens: string[], data: Record<string, unknown> = { match_id: 'm1' }): OutboxRow => ({
  id, user_id: `u${id}`, kind: 'new_match', data, tokens,
});

Deno.test('one push per device, generic texts, ids only', () => {
  const plan = planPushes([row(1, ['t1', 't2'], { match_id: 'm1', first_name: 'Léa', drink: 'wine' })]);
  assertEquals(plan.messages.length, 2);
  assertEquals(plan.owners, [1, 1]);
  assertEquals(plan.messages[0], { to: 't1', ...TEXTS.new_match, data: { kind: 'new_match', match_id: 'm1' } });
});

Deno.test('texts never contain personal data placeholders', () => {
  for (const t of Object.values(TEXTS)) {
    assertEquals(/\{|\$|%s/.test(t.title + t.body), false);
  }
});

Deno.test('rows without device are settled as sent', () => {
  const plan = planPushes([row(1, []), row(2, ['t'])]);
  assertEquals(plan.withoutDevice, [1]);
  assertEquals(settle(plan, [{ ok: true }]).sent.sort(), [1, 2]);
});

Deno.test('a row is sent if one device accepted it; dead tokens are collected', () => {
  const plan = planPushes([row(1, ['a', 'b']), row(2, ['c'])]);
  const outcome = settle(plan, [
    { ok: false, deadToken: true, error: 'DeviceNotRegistered' },
    { ok: true },
    { ok: false, error: 'MessageRateExceeded' },
  ]);
  assertEquals(outcome.sent, [1]);
  assertEquals(outcome.failed, [2]);
  assertEquals(outcome.deadTokens, ['a']);
});

Deno.test('Expo tickets map to results, network errors fail the batch', async () => {
  const ok = new ExpoPushSender(undefined, () =>
    Promise.resolve(new Response(JSON.stringify({
      data: [{ status: 'ok' }, { status: 'error', details: { error: 'DeviceNotRegistered' } }],
    }))));
  const msg = { to: 't', title: 'x', body: 'y', data: {} };
  assertEquals(await ok.send([msg, msg]), [{ ok: true }, { ok: false, error: 'DeviceNotRegistered', deadToken: true }]);

  const down = new ExpoPushSender(undefined, () => Promise.reject(new Error('offline')));
  assertEquals(await down.send([msg]), [{ ok: false, error: 'offline' }]);
});

Deno.test('every notification kind defined in SQL has a text', async () => {
  const dir = new URL('../../migrations/', import.meta.url);
  let sql = '';
  for await (const e of Deno.readDir(dir)) sql += await Deno.readTextFile(new URL(e.name, dir));
  const kinds = new Set<string>();
  const create = sql.match(/create type public\.notification_kind as enum \(([^)]*)\)/);
  for (const m of create?.[1]?.matchAll(/'([a-z_]+)'/g) ?? []) kinds.add(m[1]!);
  for (const m of sql.matchAll(/alter type public\.notification_kind add value if not exists '([a-z_]+)'/g)) kinds.add(m[1]!);
  assertEquals(kinds.has('new_match') && kinds.has('moderation_notice'), true);
  for (const k of kinds) assertEquals(k in TEXTS, true, `missing text for ${k}`);
});
