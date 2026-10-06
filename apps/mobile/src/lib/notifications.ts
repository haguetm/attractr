// Push notifications (Expo Notifications). The server only sends generic texts and
// ids (send-push Edge Function); this module registers the device and routes taps.
// Remote push needs a development build and an EAS projectId: it is skipped
// silently elsewhere (Expo Go, simulators, web).

import Constants from 'expo-constants';
import * as Device from 'expo-device';
import * as Notifications from 'expo-notifications';
import { router } from 'expo-router';
import { Platform } from 'react-native';
import { api } from './api';

Notifications.setNotificationHandler({
  handleNotification: async () => ({
    shouldShowBanner: true,
    shouldShowList: true,
    shouldPlaySound: true,
    shouldSetBadge: false,
  }),
});

let currentToken: string | null = null;

export async function registerForPush(): Promise<void> {
  if (!Device.isDevice || Platform.OS === 'web') return;
  const projectId = Constants.expoConfig?.extra?.eas?.projectId as string | undefined;
  if (!projectId) return;

  if (Platform.OS === 'android') {
    await Notifications.setNotificationChannelAsync('default', {
      name: 'Attractr',
      importance: Notifications.AndroidImportance.DEFAULT,
    });
  }
  const existing = await Notifications.getPermissionsAsync();
  const status = existing.granted ? existing.status : (await Notifications.requestPermissionsAsync()).status;
  if (status !== 'granted') return;

  const { data: token } = await Notifications.getExpoPushTokenAsync({ projectId });
  currentToken = token;
  await api.registerPushToken(token, Platform.OS === 'ios' ? 'ios' : 'android');
}

/** Called before signing out so the device stops receiving this account's pushes. */
export async function unregisterForPush(): Promise<void> {
  if (!currentToken) return;
  await api.unregisterPushToken(currentToken).catch(() => undefined);
  currentToken = null;
}

type PushData = { kind?: string; match_id?: string; conversation_id?: string; outing_id?: string };

export function routeForNotification(data: PushData) {
  if (data.kind === 'friend_request') {
    router.push('/friends');
  } else if (data.kind === 'outing_feedback' && data.outing_id) {
    router.push({ pathname: '/outing/feedback', params: { outingId: data.outing_id } });
  } else if (data.kind === 'outing_invitation' || data.kind === 'outing_cancelled') {
    router.push('/outings');
  } else if (data.kind === 'new_match' && data.match_id) {
    router.push({ pathname: '/match/[matchId]', params: { matchId: data.match_id } });
  } else if (data.conversation_id || data.kind === 'first_message_reminder') {
    router.push('/matches');
  }
}

/** Opens the right screen when the user taps a notification. Returns the unsubscribe. */
export function listenToNotificationTaps(): () => void {
  const sub = Notifications.addNotificationResponseReceivedListener((response) => {
    routeForNotification(response.notification.request.content.data as PushData);
  });
  return () => sub.remove();
}
