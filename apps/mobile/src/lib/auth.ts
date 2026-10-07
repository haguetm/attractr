// Sign-in methods offered on the first screen, from EXPO_PUBLIC_AUTH_METHODS
// (comma-separated: phone, email, google, apple). Production offers them all once the
// paid pieces exist (SMS provider, Apple developer account); the free beta uses
// "email,google" (docs/BETA.md). Whatever the method, onboarding asks for a phone.

import * as Linking from 'expo-linking';
import * as WebBrowser from 'expo-web-browser';
import { AppError } from './errors';
import { supabase } from './supabase';

export const AUTH_METHODS = ['phone', 'email', 'google', 'apple'] as const;
export type AuthMethod = (typeof AUTH_METHODS)[number];

export function parseAuthMethods(raw: string | undefined): AuthMethod[] {
  const wanted = (raw ?? '').split(',').map((m) => m.trim());
  const methods = AUTH_METHODS.filter((m) => wanted.includes(m));
  return methods.length ? methods : ['phone'];
}

export const ENABLED_AUTH_METHODS = parseAuthMethods(process.env.EXPO_PUBLIC_AUTH_METHODS);

export const SIGN_IN_ROUTE = '/sign-in';

// Closes the browser popup on web once the provider redirected back.
WebBrowser.maybeCompleteAuthSession();

/**
 * Google or Apple through Supabase OAuth (PKCE) in the system browser: no native SDK, so
 * it works in Expo Go, in builds and on the web. Returns false when the user cancels.
 */
export async function signInWithProvider(provider: 'google' | 'apple'): Promise<boolean> {
  const redirectTo = Linking.createURL('auth-callback');
  const { data, error } = await supabase.auth.signInWithOAuth({ provider, options: { redirectTo, skipBrowserRedirect: true } });
  if (error || !data.url) throw new AppError('oauth_failed');
  const result = await WebBrowser.openAuthSessionAsync(data.url, redirectTo);
  if (result.type !== 'success') return false;
  const code = Linking.parse(result.url).queryParams?.code;
  if (typeof code !== 'string') throw new AppError('oauth_failed');
  const { error: exchangeError } = await supabase.auth.exchangeCodeForSession(code);
  if (exchangeError) throw new AppError('oauth_failed');
  return true;
}
