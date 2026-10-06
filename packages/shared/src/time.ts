// Countdowns and reset times shown in the app (first-message window, like quota).

export interface TimeLeft {
  expired: boolean;
  hours: number;
  minutes: number;
}

export function timeLeft(deadline: string | Date, now: Date = new Date()): TimeLeft {
  const ms = new Date(deadline).getTime() - now.getTime();
  if (ms <= 0) return { expired: true, hours: 0, minutes: 0 };
  const totalMinutes = Math.ceil(ms / 60000);
  return { expired: false, hours: Math.floor(totalMinutes / 60), minutes: totalMinutes % 60 };
}

/** "Urgent" when less than this many hours remain (UI emphasis only). */
export const URGENT_HOURS = 3;
export const isUrgent = (t: TimeLeft) => !t.expired && t.hours < URGENT_HOURS;
