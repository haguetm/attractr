import { describe, expect, it } from 'vitest';
import { normalizeEmail } from './email';

describe('normalizeEmail', () => {
  it('trims and lowercases a valid address', () => {
    expect(normalizeEmail('  Lea.Martin@Example.FR ')).toBe('lea.martin@example.fr');
    expect(normalizeEmail('a+tag@sub.domain.io')).toBe('a+tag@sub.domain.io');
  });

  it('refuses what cannot receive a code', () => {
    expect(normalizeEmail('')).toBeNull();
    expect(normalizeEmail('lea')).toBeNull();
    expect(normalizeEmail('lea@example')).toBeNull();
    expect(normalizeEmail('lea martin@example.fr')).toBeNull();
    expect(normalizeEmail('lea@@example.fr')).toBeNull();
    expect(normalizeEmail(`${'a'.repeat(250)}@example.fr`)).toBeNull();
  });
});
