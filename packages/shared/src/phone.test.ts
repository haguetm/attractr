import { describe, expect, it } from 'vitest';
import { contactDigestInput, normalizePhone } from './phone';

describe('normalizePhone', () => {
  it.each([
    ['06 12 34 56 78', '+33612345678'],
    ['06.12.34.56.78', '+33612345678'],
    ['+33 6 12 34 56 78', '+33612345678'],
    ['+33 06 12 34 56 78', '+33612345678'],
    ['0033612345678', '+33612345678'],
    ['+32 470 12 34 56', '+32470123456'],
  ])('%s -> %s', (input, expected) => expect(normalizePhone(input)).toBe(expected));

  it.each(['', '12345', '06 12 34', 'abc', '+33 6 12 34 56 78 90 12 34'])('rejects %s', (input) => {
    expect(normalizePhone(input)).toBeNull();
  });
});

describe('contactDigestInput', () => {
  it('uses the E.164 digits, whatever the contact format', () => {
    expect(contactDigestInput('06 12 34 56 78')).toBe('33612345678');
    expect(contactDigestInput('+33 6 12 34 56 78')).toBe('33612345678');
    expect(contactDigestInput('0033612345678')).toBe('33612345678');
    expect(contactDigestInput('*123#')).toBeNull();
  });
});
