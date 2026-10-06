// French date formats used by outings.

const dateTime = new Intl.DateTimeFormat('fr-FR', {
  weekday: 'long',
  day: 'numeric',
  month: 'long',
  hour: '2-digit',
  minute: '2-digit',
});
const dayLabel = new Intl.DateTimeFormat('fr-FR', { weekday: 'short', day: 'numeric', month: 'short' });

export const formatDateTime = (iso: string | Date) => dateTime.format(new Date(iso));
export const formatDay = (d: Date) => dayLabel.format(d);
export const formatTime = (hour: number, minute: number) => `${hour} h ${String(minute).padStart(2, '0')}`;

/** Deep link opened by the friend invitation (expo-router: /friend/[code]). */
export const friendInviteLink = (code: string) => `attractr://friend/${code}`;
