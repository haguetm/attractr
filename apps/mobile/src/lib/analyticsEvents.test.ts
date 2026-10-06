import { describe, expect, it } from 'vitest';
import { EVENTS, sanitize } from './analyticsEvents';

describe('analytics allowlist', () => {
  it('drops unknown events', () => {
    expect(sanitize('profile_viewed', { id: 'x' })).toBeNull();
  });

  it('keeps only the listed properties', () => {
    expect(sanitize('like_sent', { target: 'photo', matched: true, drink: 'cocktail', name: 'Lea' }))
      .toEqual({ target: 'photo', matched: true });
  });

  it('refuses values outside the closed sets', () => {
    expect(sanitize('like_sent', { target: 'Lea, 28 ans', matched: 'yes' })).toEqual({});
    expect(sanitize('onboarding_step_completed', { step: 'Mon adresse : 3 rue X' })).toEqual({});
    expect(sanitize('onboarding_step_completed', { step: 'sensitive_consent' })).toEqual({ step: 'sensitive_consent' });
  });

  it('never declares a sensitive or identifying property', () => {
    const forbidden = /drink|gender|orientation|situation|structure|age|birth|name|phone|email|location|lat|lon|city|message|body|text|user_id/;
    for (const [event, props] of Object.entries(EVENTS)) {
      for (const key of Object.keys(props)) expect(forbidden.test(key), `${event}.${key}`).toBe(false);
    }
  });
});
