import { useCallback, useState } from 'react';

/** Runs an async action with a busy flag and keeps the last error for display. */
export function useSubmit() {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<unknown>(null);
  const run = useCallback(async (action: () => Promise<void>) => {
    setBusy(true);
    setError(null);
    try {
      await action();
    } catch (e) {
      setError(e);
    } finally {
      setBusy(false);
    }
  }, []);
  return { busy, error, run, setError };
}
