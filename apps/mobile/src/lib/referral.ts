/** Referral code kept from an attractr://r/CODE link until signup screen 1. Not sensitive. */
export const PENDING_REFERRAL_KEY = 'attractr.pendingReferralCode';

/** Link shared by a referrer (expo-router: /r/[code]). */
export const referralLink = (code: string) => `attractr://r/${code}`;

/** Set when "compte de couple" was chosen at signup screen 4: the couple screen opens once onboarding ends. */
export const WANTS_COUPLE_KEY = 'attractr.wantsCouple';
