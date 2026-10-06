// Push provider contract (Expo Notifications in production, a mock in development).

export interface PushMessage {
  to: string;
  title: string;
  body: string;
  /** Ids only, never personal or sensitive data (spec §12). */
  data: Record<string, string>;
}

export interface PushResult {
  ok: boolean;
  /** The token is no longer valid and must be deleted. */
  deadToken?: boolean;
  error?: string;
}

export interface PushSender {
  /** Returns one result per message, in the same order. */
  send(messages: PushMessage[]): Promise<PushResult[]>;
}
