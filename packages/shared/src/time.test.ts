import { describe, expect, it } from 'vitest';
import { isUrgent, timeLeft } from './time';

const now = new Date('2026-10-06T12:00:00Z');

describe('timeLeft', () => {
  it('rounds up to the next minute', () => {
    expect(timeLeft('2026-10-07T12:00:00Z', now)).toEqual({ expired: false, hours: 24, minutes: 0 });
    expect(timeLeft('2026-10-06T14:30:20Z', now)).toEqual({ expired: false, hours: 2, minutes: 31 });
    expect(timeLeft('2026-10-06T12:00:01Z', now)).toEqual({ expired: false, hours: 0, minutes: 1 });
  });

  it('is expired at or after the deadline', () => {
    expect(timeLeft('2026-10-06T12:00:00Z', now).expired).toBe(true);
    expect(timeLeft('2026-10-05T12:00:00Z', now).expired).toBe(true);
  });

  it('flags the last hours as urgent', () => {
    expect(isUrgent(timeLeft('2026-10-06T14:00:00Z', now))).toBe(true);
    expect(isUrgent(timeLeft('2026-10-06T20:00:00Z', now))).toBe(false);
    expect(isUrgent(timeLeft('2026-10-06T11:00:00Z', now))).toBe(false);
  });
});
