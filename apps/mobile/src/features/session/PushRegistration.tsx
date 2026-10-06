// Registers the device for pushes once the profile is active, and routes taps.

import { useEffect } from 'react';
import { listenToNotificationTaps, registerForPush } from '../../lib/notifications';
import { useSession } from './SessionProvider';

export function PushRegistration() {
  const { profile } = useSession();
  const active = profile?.status === 'active';

  useEffect(() => {
    if (!active) return;
    void registerForPush().catch(() => undefined);
    return listenToNotificationTaps();
  }, [active]);

  return null;
}
