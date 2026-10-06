import type { PushMessage, PushResult, PushSender } from './types.ts';

/** Development sender: delivers nothing, keeps the messages for inspection. */
export class MockPushSender implements PushSender {
  readonly sent: PushMessage[] = [];

  send(messages: PushMessage[]): Promise<PushResult[]> {
    this.sent.push(...messages);
    console.log(`mock push: ${messages.length} message(s)`);
    return Promise.resolve(messages.map(() => ({ ok: true })));
  }
}
