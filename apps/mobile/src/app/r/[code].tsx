// Referral link (attractr://r/CODE): keeps the code for the signup screen (screen 1).

import AsyncStorage from '@react-native-async-storage/async-storage';
import { Redirect, useLocalSearchParams } from 'expo-router';
import { useEffect, useState } from 'react';
import { PENDING_REFERRAL_KEY } from '../../lib/referral';

export default function ReferralLinkScreen() {
  const { code } = useLocalSearchParams<{ code: string }>();
  const [saved, setSaved] = useState(false);

  useEffect(() => {
    const clean = (code ?? '').toUpperCase().replace(/[^A-Z0-9-]/g, '').slice(0, 32);
    void AsyncStorage.setItem(PENDING_REFERRAL_KEY, clean).catch(() => undefined).finally(() => setSaved(true));
  }, [code]);

  return saved ? <Redirect href="/" /> : null;
}
