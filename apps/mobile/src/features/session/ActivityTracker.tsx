// App opens: one activity day for server-side retention (touch_my_activity) and the
// `app_opened` analytics event. Links analytics to the account's pseudonymous id.

import { useEffect } from 'react';
import { AppState } from 'react-native';
import { flush, identify, track } from '../../lib/analytics';
import { api } from '../../lib/api';
import { useSession } from './SessionProvider';

export function ActivityTracker() {
  const { profile } = useSession();
  const tracked = profile?.status === 'active' || profile?.status === 'paused';
  const userId = profile?.id;

  useEffect(() => {
    if (userId) void api.getAnalyticsId().then((id) => { if (id) void identify(id); }).catch(() => undefined);
  }, [userId]);

  useEffect(() => {
    const opened = () => {
      track('app_opened');
      if (tracked) void api.touchActivity().catch(() => undefined);
    };
    opened();
    const sub = AppState.addEventListener('change', (state) => {
      if (state === 'active') opened();
      else void flush();
    });
    return () => sub.remove();
  }, [tracked]);

  return null;
}
