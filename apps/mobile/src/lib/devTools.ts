// Development tools are only shown in development builds with APP_ENV=development.
// The server enforces its own guard (supabase/functions/dev-impersonate/guard.ts).
export const DEV_TOOLS_ENABLED = __DEV__ && process.env.EXPO_PUBLIC_APP_ENV === 'development';
