// PostHog (EU) product analytics through its HTTP batch API: no native SDK, no autocapture,
// no session replay, no screen names. Disabled without EXPO_PUBLIC_POSTHOG_KEY and when the
// user turns audience measurement off in Réglages. The distinct id is a random install id,
// then the pseudonymous analytics_id of the account (never the user id or phone number).

import AsyncStorage from '@react-native-async-storage/async-storage';
import Constants from 'expo-constants';
import { randomUUID } from 'expo-crypto';
import { Platform } from 'react-native';
import { type AnalyticsEvent, sanitize } from './analyticsEvents';

const KEY = process.env.EXPO_PUBLIC_POSTHOG_KEY;
const HOST = process.env.EXPO_PUBLIC_POSTHOG_HOST || 'https://eu.i.posthog.com';
const OPT_OUT_KEY = 'analytics_opt_out';
const INSTALL_ID_KEY = 'analytics_install_id';

export const analyticsAvailable = !!KEY;

type Queued = { event: string; distinct_id: string; timestamp: string; properties: Record<string, unknown> };

let queue: Queued[] = [];
let distinctId: string | null = null;
let optedOut = true;  // until the stored choice is read
let ready: Promise<void> | null = null;
let timer: ReturnType<typeof setTimeout> | null = null;

function init() {
  ready ??= (async () => {
    optedOut = (await AsyncStorage.getItem(OPT_OUT_KEY).catch(() => null)) === '1';
    let id = await AsyncStorage.getItem(INSTALL_ID_KEY).catch(() => null);
    if (!id) {
      id = randomUUID();
      await AsyncStorage.setItem(INSTALL_ID_KEY, id).catch(() => undefined);
    }
    distinctId ??= id;
  })();
  return ready;
}

const common = () => ({
  $lib: 'attractr-http',
  $geoip_disable: true,
  app_version: Constants.expoConfig?.version ?? 'unknown',
  platform: Platform.OS,
});

export function track(event: AnalyticsEvent, props?: Record<string, unknown>) {
  if (!KEY) return;
  const clean = sanitize(event, props);
  if (!clean) return;
  void init().then(() => {
    if (optedOut || !distinctId) return;
    queue.push({ event, distinct_id: distinctId, timestamp: new Date().toISOString(), properties: { ...clean, ...common() } });
    if (queue.length >= 20) void flush();
    else timer ??= setTimeout(() => void flush(), 10_000);
  });
}

/** Switches to the account's pseudonymous id, merging the events sent before login. */
export async function identify(analyticsId: string) {
  if (!KEY) return;
  await init();
  if (optedOut || distinctId === analyticsId) return;
  const anon = distinctId;
  distinctId = analyticsId;
  queue.push({ event: '$identify', distinct_id: analyticsId, timestamp: new Date().toISOString(),
    properties: { $anon_distinct_id: anon, ...common() } });
  void flush();
}

/** After sign-out: a new install id, so the next person on this phone is not linked. */
export async function resetAnalytics() {
  await flush();
  const id = randomUUID();
  await AsyncStorage.setItem(INSTALL_ID_KEY, id).catch(() => undefined);
  distinctId = id;
}

export async function flush() {
  if (timer) clearTimeout(timer);
  timer = null;
  if (!KEY || queue.length === 0) return;
  const batch = queue;
  queue = [];
  try {
    await fetch(`${HOST}/batch/`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ api_key: KEY, batch }),
    });
  } catch {
    // Offline: drop the batch rather than keep data on the phone.
  }
}

export async function isAnalyticsEnabled() {
  await init();
  return !optedOut;
}

export async function setAnalyticsEnabled(enabled: boolean) {
  await init();
  optedOut = !enabled;
  if (!enabled) queue = [];
  await AsyncStorage.setItem(OPT_OUT_KEY, enabled ? '0' : '1').catch(() => undefined);
}
