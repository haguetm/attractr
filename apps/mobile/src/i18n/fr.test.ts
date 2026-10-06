// Guards the French translation file against backend drift: every error code the
// database or Edge Functions can return, and every list value, must have a text.

import { COMPOSITIONS, DISTANCE_BUCKETS, DRINKS, GENDERS, SITUATIONS, STRUCTURES } from '@attractr/shared';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { errorCode, errorKey } from '../lib/errors';
import fr from './fr.json';

const root = join(__dirname, '../../../..');
const read = (dir: string, filter: (f: string) => boolean) =>
  readdirSync(join(root, dir), { recursive: true, encoding: 'utf8' })
    .filter(filter)
    .map((f) => readFileSync(join(root, dir, f), 'utf8'))
    .join('\n');

const migrations = read('supabase/migrations', (f) => f.endsWith('.sql'));
const functions = read('supabase/functions', (f) => f.endsWith('.ts') && !f.endsWith('.test.ts'));
const matches = (text: string, re: RegExp) => [...new Set([...text.matchAll(re)].map((m) => m[1]!))];

// Codes that only signal server misconfiguration; the app shows the generic message.
// Raised only by service functions called from Edge Functions, never shown in the app.
const INTERNAL = new Set(['sensitive_key_missing', 'method_not_allowed', 'ai_analysis_not_found', 'ai_result_invalid',
  // Metrics dashboard (tools/dashboard), not the app.
  'invalid_grain', 'invalid_range', 'metrics_failed']);

describe('fr.json', () => {
  it('translates every error raised by the database', () => {
    const codes = matches(migrations, /raise exception '([a-z_]+(?::[a-z_]+)?)'/g);
    expect(codes.length).toBeGreaterThan(30);
    const missing = codes.map(errorKey).filter((c) => !INTERNAL.has(c) && !(c in fr.errors));
    expect(missing).toEqual([]);
  });

  it('translates every error returned by Edge Functions', () => {
    const codes = [
      ...matches(functions, /error: '([a-z_]+)'/g),
      ...matches(functions, /new LocationError\('([a-z_]+)'\)/g),
    ];
    expect(codes.filter((c) => !INTERNAL.has(c) && !(c in fr.errors))).toEqual([]);
  });

  it('labels every prompt question and orientation label seeded in the database', () => {
    const block = (table: string) => migrations.split(`insert into public.${table}`)[1]!.split(';')[0]!;
    const questions = matches(block('prompt_questions'), /\('([a-z_]+)', \d+\)/g);
    const orientations = matches(block('orientation_labels'), /\('([a-z_]+)', \d+\)/g);
    expect(questions.filter((q) => !(q in fr.prompts.questions))).toEqual([]);
    expect(orientations.filter((o) => !(o in fr.orientation.labels))).toEqual([]);
  });

  it('labels every domain value', () => {
    for (const d of DRINKS) expect(fr.drinks).toHaveProperty([d]);
    for (const g of GENDERS) expect(fr.gender).toHaveProperty([g]);
    for (const s of SITUATIONS) expect(fr.situation).toHaveProperty([s]);
    for (const s of STRUCTURES) expect(fr.structure).toHaveProperty([s]);
    for (const c of COMPOSITIONS) expect(fr.composition).toHaveProperty([c]);
    for (const b of DISTANCE_BUCKETS) expect(fr.card.distance).toHaveProperty([b]);
  });
});

describe('errorCode', () => {
  it('maps database messages to translation keys', () => {
    expect(errorCode({ message: 'drink_change_cooldown' })).toBe('drink_change_cooldown');
    expect(errorCode({ message: 'onboarding_incomplete:photos' })).toBe('onboarding_incomplete_photos');
    expect(errorCode({ message: 'TypeError: Network request failed' })).toBe('network');
    expect(errorCode({ message: 'something unexpected' })).toBe('generic');
    expect(errorCode(null)).toBe('generic');
  });
});
