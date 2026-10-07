import AsyncStorage from '@react-native-async-storage/async-storage';
import { createClient } from '@supabase/supabase-js';
import { AppState, Platform } from 'react-native';

const url = process.env.EXPO_PUBLIC_SUPABASE_URL;
const anonKey = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY;

if (!url || !anonKey) {
  throw new Error('Missing EXPO_PUBLIC_SUPABASE_URL / EXPO_PUBLIC_SUPABASE_ANON_KEY (see apps/mobile/.env.example)');
}

// Expo web static rendering runs this module in Node, where AsyncStorage (window) is unavailable.
const isServerRender = Platform.OS === 'web' && typeof window === 'undefined';

export const supabase = createClient(url, anonKey, {
  auth: {
    storage: isServerRender ? undefined : AsyncStorage,
    autoRefreshToken: !isServerRender,
    persistSession: !isServerRender,
    detectSessionInUrl: false,
    // PKCE: Google / Apple return a one-time code exchanged by the app (lib/auth.ts).
    flowType: 'pkce',
  },
});

// Refresh tokens only while the app is in the foreground (Supabase guidance for React Native).
if (Platform.OS !== 'web') {
  AppState.addEventListener('change', (state) => {
    if (state === 'active') void supabase.auth.startAutoRefresh();
    else void supabase.auth.stopAutoRefresh();
  });
}
