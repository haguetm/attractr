import type { RewardsProvider } from './types.ts';

/** Development: nothing store-side; the database grant (service_apply_free_month) is enough. */
export class MockRewardsProvider implements RewardsProvider {
  readonly granted: { userId: string; months: number }[] = [];

  grantFreeMonths(userId: string, months: number): Promise<void> {
    this.granted.push({ userId, months });
    return Promise.resolve();
  }
}
