import { describe, expect, it, vi } from 'vitest';

vi.mock('expo-linking', () => ({}));
vi.mock('expo-web-browser', () => ({ maybeCompleteAuthSession: () => undefined }));
vi.mock('./supabase', () => ({ supabase: {} }));

const { parseAuthMethods } = await import('./auth');

describe('parseAuthMethods', () => {
  it('keeps known methods in a fixed order', () => {
    expect(parseAuthMethods('google, email')).toEqual(['email', 'google']);
    expect(parseAuthMethods('phone,email,google,apple')).toEqual(['phone', 'email', 'google', 'apple']);
  });

  it('falls back to the phone when nothing valid is configured', () => {
    expect(parseAuthMethods(undefined)).toEqual(['phone']);
    expect(parseAuthMethods('facebook')).toEqual(['phone']);
  });
});
