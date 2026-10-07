// Deep link target of the Google / Apple sign-in (lib/auth.ts). The session is set by
// signInWithProvider; this route only exists so the redirect never lands on "not found".

import { Redirect } from 'expo-router';

export default function AuthCallback() {
  return <Redirect href="/" />;
}
