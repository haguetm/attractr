// Once signed in: links the account to RevenueCat; once active: registers the device
// for pushes and routes notification taps.

import { useEffect } from 'react';
import { listenToNotificationTaps, registerForPush } from '../../lib/notifications';
import { identifyPurchaser } from '../../lib/purchases';
import { useSession } from './SessionProvider';

export function PushRegistration() {
  const { profile } = useSession();
  const active = profile?.status === 'active';
  const userId = profile?.id;

  useEffect(() => {
    if (userId) void identifyPurchaser(userId).catch(() => undefined);
  }, [userId]);

  useEffect(() => {
    if (!active) return;
    void registerForPush().catch(() => undefined);
    return listenToNotificationTaps();
  }, [active]);

  return null;
}
