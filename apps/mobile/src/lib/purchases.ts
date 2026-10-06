// RevenueCat (spec §10). Prices are configured in RevenueCat and the stores; Premium
// status is decided server-side from the webhook (private.entitlements), never here.
// Without API keys (development, Expo Go) purchases are disabled and the dev grants of
// "Outils de développement" are used instead.

import { Platform } from 'react-native';
import { track } from './analytics';
import Purchases, { type PurchasesPackage } from 'react-native-purchases';

const API_KEY = Platform.select({
  ios: process.env.EXPO_PUBLIC_REVENUECAT_IOS_KEY,
  android: process.env.EXPO_PUBLIC_REVENUECAT_ANDROID_KEY,
});

export const purchasesAvailable = !!API_KEY && Platform.OS !== 'web';

let configuredFor: string | null = null;

/** Links purchases to the Attractr account (app_user_id = profile id, read by the webhook). */
export async function identifyPurchaser(userId: string): Promise<void> {
  if (!purchasesAvailable || configuredFor === userId) return;
  if (!configuredFor) Purchases.configure({ apiKey: API_KEY!, appUserID: userId });
  else await Purchases.logIn(userId);
  configuredFor = userId;
}

export async function resetPurchaser(): Promise<void> {
  if (!purchasesAvailable || !configuredFor) return;
  await Purchases.logOut().catch(() => undefined);
  configuredFor = null;
}

export interface Plans {
  subscriptions: PurchasesPackage[];
  boost: PurchasesPackage | null;
}

/** Current offering ("premium") for subscriptions, "boosts" offering for the consumable. */
export async function loadPlans(): Promise<Plans> {
  if (!purchasesAvailable) return { subscriptions: [], boost: null };
  const offerings = await Purchases.getOfferings();
  return {
    subscriptions: offerings.current?.availablePackages ?? [],
    boost: offerings.all.boosts?.availablePackages[0] ?? null,
  };
}

/** Returns false when the user cancelled the store sheet. */
export async function buy(pkg: PurchasesPackage): Promise<boolean> {
  track('purchase_started', { product: pkg.packageType === 'ANNUAL' ? 'yearly' : pkg.packageType === 'MONTHLY' ? 'monthly' : 'boost' });
  try {
    await Purchases.purchasePackage(pkg);
    return true;
  } catch (e) {
    if ((e as { userCancelled?: boolean }).userCancelled) return false;
    throw e;
  }
}

export async function restore(): Promise<void> {
  if (purchasesAvailable) await Purchases.restorePurchases();
}

/** "Résiliation en un clic": opens the store's subscription management. */
export async function manageSubscription(): Promise<void> {
  if (purchasesAvailable) await Purchases.showManageSubscriptions();
}
