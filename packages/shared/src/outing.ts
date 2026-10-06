// Choosing the day and time of an outing (spec §7) without a native date picker.

/** Local midnight of today and the next `days - 1` days. */
export function upcomingDays(now: Date = new Date(), days = 14): Date[] {
  const start = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  return Array.from({ length: days }, (_, i) => new Date(start.getFullYear(), start.getMonth(), start.getDate() + i));
}

export const OUTING_HOURS = Array.from({ length: 14 }, (_, i) => 10 + i); // 10 h to 23 h
export const OUTING_MINUTES = [0, 15, 30, 45];

/** Local date + time to a Date; null when it is not in the future. */
export function outingStart(day: Date, hour: number, minute: number, now: Date = new Date()): Date | null {
  const start = new Date(day.getFullYear(), day.getMonth(), day.getDate(), hour, minute);
  return start.getTime() > now.getTime() ? start : null;
}

/** Participants of an outing: the two matched people plus invitations not declined. */
export function outingState(participants: number, min: number, max: number): 'waiting' | 'ok' | 'full' {
  if (participants >= max) return 'full';
  return participants >= min ? 'ok' : 'waiting';
}
