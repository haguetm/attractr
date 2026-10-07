// Static settings live in app.json. Files that must not be committed come from EAS
// file variables at build time (docs/BETA.md): google-services.json for Android push.

import type { ConfigContext, ExpoConfig } from 'expo/config';

export default ({ config }: ConfigContext): ExpoConfig => ({
  ...(config as ExpoConfig),
  android: {
    ...config.android,
    googleServicesFile: process.env.GOOGLE_SERVICES_JSON ?? config.android?.googleServicesFile,
  },
});
