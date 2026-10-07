// Sign-in method. Production: a code by SMS, one account per phone number (Q13).
// Free beta: a code by email, no SMS cost (EXPO_PUBLIC_AUTH_METHOD=email, docs/BETA.md).

export type AuthMethod = 'phone' | 'email';

export const AUTH_METHOD: AuthMethod = process.env.EXPO_PUBLIC_AUTH_METHOD === 'email' ? 'email' : 'phone';

/** First screen of the sign-in flow. */
export const SIGN_IN_ROUTE = AUTH_METHOD === 'email' ? '/email' : '/phone';
