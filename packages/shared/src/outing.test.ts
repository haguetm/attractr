import { describe, expect, it } from 'vitest';
import { outingStart, outingState, upcomingDays } from './outing';

const now = new Date(2026, 9, 6, 18, 20); // 6 Oct 2026, 18:20 local

describe('outing day and time', () => {
  it('offers today and the next 13 days', () => {
    const days = upcomingDays(now);
    expect(days).toHaveLength(14);
    expect(days[0]!.getDate()).toBe(6);
    expect(days[13]!.getDate()).toBe(19);
  });

  it('only accepts a start in the future', () => {
    const today = upcomingDays(now)[0]!;
    expect(outingStart(today, 18, 0, now)).toBeNull();
    expect(outingStart(today, 20, 30, now)?.getHours()).toBe(20);
  });
});

describe('outing participants (3 to 8, spec §7)', () => {
  it('waits for a third person, and is full at the max', () => {
    expect(outingState(2, 3, 8)).toBe('waiting');
    expect(outingState(3, 3, 8)).toBe('ok');
    expect(outingState(8, 3, 8)).toBe('full');
  });
});
