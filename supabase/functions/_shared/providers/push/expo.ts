import type { PushMessage, PushResult, PushSender } from './types.ts';

const ENDPOINT = 'https://exp.host/--/api/v2/push/send';
const BATCH = 100; // Expo accepts up to 100 messages per request.

type Ticket = { status: 'ok' | 'error'; message?: string; details?: { error?: string } };

/** Sends through the Expo push service. EXPO_ACCESS_TOKEN is optional (enhanced security). */
export class ExpoPushSender implements PushSender {
  constructor(private readonly accessToken?: string, private readonly fetchFn: typeof fetch = fetch) {}

  async send(messages: PushMessage[]): Promise<PushResult[]> {
    const results: PushResult[] = [];
    for (let i = 0; i < messages.length; i += BATCH) {
      const batch = messages.slice(i, i + BATCH);
      try {
        const response = await this.fetchFn(ENDPOINT, {
          method: 'POST',
          headers: {
            Accept: 'application/json',
            'Content-Type': 'application/json',
            ...(this.accessToken ? { Authorization: `Bearer ${this.accessToken}` } : {}),
          },
          body: JSON.stringify(batch.map((m) => ({ ...m, sound: 'default' }))),
        });
        if (!response.ok) throw new Error(`expo push http ${response.status}`);
        const { data } = (await response.json()) as { data: Ticket[] };
        results.push(...batch.map((_, j): PushResult => toResult(data[j])));
      } catch (e) {
        results.push(...batch.map(() => ({ ok: false, error: (e as Error).message })));
      }
    }
    return results;
  }
}

function toResult(ticket: Ticket | undefined): PushResult {
  if (!ticket) return { ok: false, error: 'missing ticket' };
  if (ticket.status === 'ok') return { ok: true };
  const code = ticket.details?.error ?? 'error';
  return { ok: false, error: code, deadToken: code === 'DeviceNotRegistered' };
}
