// Turns notification_outbox rows into push messages and settles the results.
// Texts are generic on purpose: a lock screen must not reveal names, drinks or
// anything personal (spec §12). Server-side texts are French only for V1.

import type { PushMessage, PushResult } from '../_shared/providers/push/index.ts';

export type NotificationKind = 'new_match' | 'new_message' | 'your_turn' | 'first_message_reminder';

export interface OutboxRow {
  id: number;
  user_id: string;
  kind: NotificationKind;
  data: Record<string, unknown>;
  tokens: string[];
}

export const TEXTS: Record<NotificationKind, { title: string; body: string }> = {
  new_match: { title: 'Nouveau match', body: 'Vous avez 24 h pour vous écrire.' },
  new_message: { title: 'Nouveau message', body: 'Ouvre Attractr pour le lire.' },
  your_turn: { title: 'À ton tour', body: 'Une conversation attend ta réponse.' },
  first_message_reminder: { title: 'Plus que quelques heures', body: 'Envoie ton premier message avant la fin du délai.' },
};

/** Only ids travel in the payload. */
const ALLOWED_DATA = ['match_id', 'conversation_id'];

export interface Planned {
  messages: PushMessage[];
  /** Index i of messages belongs to outbox row owners[i]. */
  owners: number[];
  /** Rows without any device: nothing to deliver, settled as sent. */
  withoutDevice: number[];
}

export function planPushes(rows: OutboxRow[]): Planned {
  const messages: PushMessage[] = [];
  const owners: number[] = [];
  const withoutDevice: number[] = [];
  for (const row of rows) {
    if (row.tokens.length === 0) {
      withoutDevice.push(row.id);
      continue;
    }
    const data: Record<string, string> = { kind: row.kind };
    for (const key of ALLOWED_DATA) {
      if (typeof row.data[key] === 'string') data[key] = row.data[key] as string;
    }
    for (const token of row.tokens) {
      messages.push({ to: token, ...TEXTS[row.kind], data });
      owners.push(row.id);
    }
  }
  return { messages, owners, withoutDevice };
}

export interface Settlement {
  sent: number[];
  failed: number[];
  deadTokens: string[];
  error: string | null;
}

/** A row is sent when at least one of its devices accepted the push. */
export function settle(plan: Planned, results: PushResult[]): Settlement {
  const okRows = new Set<number>(plan.withoutDevice);
  const attempted = new Set<number>(plan.owners);
  const deadTokens: string[] = [];
  let error: string | null = null;
  results.forEach((r, i) => {
    if (r.ok) okRows.add(plan.owners[i]!);
    if (r.deadToken) deadTokens.push(plan.messages[i]!.to);
    if (!r.ok && r.error) error = r.error;
  });
  return {
    sent: [...okRows],
    failed: [...attempted].filter((id) => !okRows.has(id)),
    deadTokens,
    error,
  };
}
