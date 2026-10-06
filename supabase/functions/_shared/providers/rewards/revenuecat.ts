import type { RewardsProvider } from './types.ts';

// RevenueCat REST v1 promotional entitlement. It starts now and does not wait for the
// end of the paid period: see docs/DECISIONS.md (phase 7) before enabling it.
const DURATIONS: Record<number, string> = { 1: 'monthly', 2: 'two_month', 3: 'three_month', 6: 'six_month' };

export class RevenueCatRewardsProvider implements RewardsProvider {
  constructor(
    private readonly secretKey: string,
    private readonly entitlement: string,
    private readonly fetchFn: typeof fetch = fetch,
  ) {}

  async grantFreeMonths(userId: string, months: number): Promise<void> {
    const duration = DURATIONS[months];
    if (!duration) throw new Error(`unsupported duration: ${months} months`);
    const url = `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(userId)}/entitlements/${encodeURIComponent(this.entitlement)}/promotional`;
    const response = await this.fetchFn(url, {
      method: 'POST',
      headers: { Authorization: `Bearer ${this.secretKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ duration }),
    });
    if (!response.ok) throw new Error(`revenuecat http ${response.status}`);
  }
}
