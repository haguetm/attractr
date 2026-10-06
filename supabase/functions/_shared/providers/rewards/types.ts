// Rewards provider (spec §9): grants referral free months on the store side. Isolated
// so the strategy can follow the App Store / Google Play rules (to validate legally):
// RevenueCat promotional entitlements today, store-side deferral or offer codes later.

export interface RewardsProvider {
  /** Grants `months` of Premium to the user. Throws on failure (retried next run). */
  grantFreeMonths(userId: string, months: number): Promise<void>;
}
