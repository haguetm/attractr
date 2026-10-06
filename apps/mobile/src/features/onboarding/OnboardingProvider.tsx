// Holds the onboarding draft between screens and drives navigation.
// Sought genders stay in memory until the sensitive-data consent is given (screen 3).
// Screens 5-8 (situation, drinks, structure, couples) are saved together by set_my_intent
// once the last of them is answered, because their rules cross each other.

import {
  EMPTY_INTENT,
  type Gender,
  type IntentDraft,
  type OnboardingStep,
  type OnboardingSwitches,
  applicableSteps,
  nextStep,
} from '@attractr/shared';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { router } from 'expo-router';
import { createContext, type ReactNode, useCallback, useContext, useEffect, useMemo, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { track } from '../../lib/analytics';
import { api } from '../../lib/api';
import { WANTS_COUPLE_KEY } from '../../lib/referral';
import { useSession } from '../session/SessionProvider';
import { stepPath } from './routes';

const INTENT_STEPS: OnboardingStep[] = ['situation', 'drinks', 'structure', 'composition', 'open_to_couples'];

interface OnboardingState {
  intent: IntentDraft;
  setIntent: (next: IntentDraft) => void;
  seeking: Gender[];
  setSeeking: (next: Gender[]) => void;
  switches: OnboardingSwitches;
  refreshSwitches: (countryCode: string | null) => Promise<void>;
  photoLimits: { min: number; max: number };
  /** "Étape x sur y" for the given screen. */
  progress: (step: OnboardingStep) => string;
  /** Saves what must be saved after `step`, then opens the next screen (or finishes). */
  goNext: (step: OnboardingStep) => Promise<void>;
}

const ALL_ENABLED: OnboardingSwitches = { orientationEnabled: true, structureEnabled: true, compositionEnabled: true };
const OnboardingContext = createContext<OnboardingState | null>(null);

export function OnboardingProvider({ children }: { children: ReactNode }) {
  const { t } = useTranslation();
  const { profile, refreshProfile } = useSession();
  const [intent, setIntent] = useState<IntentDraft>(EMPTY_INTENT);
  const [seeking, setSeeking] = useState<Gender[]>([]);
  const [switches, setSwitches] = useState<OnboardingSwitches>(ALL_ENABLED);
  const [photoLimits, setPhotoLimits] = useState({ min: 2, max: 6 });

  const refreshSwitches = useCallback(async (countryCode: string | null) => {
    setSwitches(await api.countrySwitches(countryCode));
  }, []);

  useEffect(() => {
    void Promise.all([api.configInt('photos.min_count'), api.configInt('photos.max_count')])
      .then(([min, max]) => setPhotoLimits({ min, max }))
      .catch(() => undefined);
  }, []);

  useEffect(() => {
    if (profile?.has_location) void refreshSwitches(profile.country_code).catch(() => undefined);
  }, [profile?.has_location, profile?.country_code, refreshSwitches]);

  const progress = useCallback(
    (step: OnboardingStep) => {
      const steps = applicableSteps(intent, switches);
      return t('common.stepProgress', { current: steps.indexOf(step) + 1, total: steps.length });
    },
    [intent, switches, t],
  );

  const goNext = useCallback(
    async (step: OnboardingStep) => {
      const next = nextStep(step, intent, switches);
      const leavingIntent = INTENT_STEPS.includes(step) && (next === null || !INTENT_STEPS.includes(next));
      if (leavingIntent && intent.situation) {
        await api.setIntent({ ...intent, situation: intent.situation });
      }
      track('onboarding_step_completed', { step });
      if (next === null) {
        await api.completeOnboarding();
        track('onboarding_completed');
        await refreshProfile();
        router.replace('/feed');
        // "Compte de couple" chosen at screen 4: invite the partner now.
        if ((await AsyncStorage.getItem(WANTS_COUPLE_KEY).catch(() => null)) === '1') {
          await AsyncStorage.removeItem(WANTS_COUPLE_KEY).catch(() => undefined);
          router.push('/couple');
        }
        return;
      }
      router.push(stepPath(next));
    },
    [intent, switches, refreshProfile],
  );

  const value = useMemo(
    () => ({ intent, setIntent, seeking, setSeeking, switches, refreshSwitches, photoLimits, progress, goNext }),
    [intent, seeking, switches, refreshSwitches, photoLimits, progress, goNext],
  );
  return <OnboardingContext.Provider value={value}>{children}</OnboardingContext.Provider>;
}

export function useOnboarding() {
  const ctx = useContext(OnboardingContext);
  if (!ctx) throw new Error('useOnboarding must be used inside OnboardingProvider');
  return ctx;
}

