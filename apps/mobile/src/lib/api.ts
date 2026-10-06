// Typed wrappers around the RPCs and Edge Functions used by the app.
// Every failure is thrown as AppError carrying the backend code.

import type {
  CompositionChoice,
  ConsentType,
  DistanceBucket,
  Drink,
  Gender,
  Situation,
  Structure,
} from '@attractr/shared';
import { AppError, errorCode } from './errors';
import { supabase } from './supabase';

async function rpc<T = void>(fn: string, args?: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.rpc(fn, args);
  if (error) throw new AppError(errorCode(error));
  return data as T;
}

async function invoke<T>(fn: string, body: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.functions.invoke(fn, { body });
  if (error) {
    // FunctionsHttpError keeps the response: read our { error: code } body.
    const context = (error as { context?: Response }).context;
    const payload = context ? await context.json().catch(() => null) : null;
    throw new AppError(typeof payload?.error === 'string' ? payload.error : errorCode(error));
  }
  return data as T;
}

export interface MyProfile {
  id: string;
  status: 'onboarding' | 'active' | 'paused' | 'suspended' | 'closed';
  is_seed: boolean;
  first_name: string | null;
  birth_date: string | null;
  gender: Gender | null;
  gender_detail: string | null;
  verification_status: 'unverified' | 'pending' | 'verified' | 'rejected';
  country_code: string | null;
  department_code: string | null;
  region_code: string | null;
  has_location: boolean;
  search: SearchPreferences;
  drinks: Drink[];
  alcohol_free_icons: boolean;
  prompts: { position: number; question_code: string; answer: string }[];
  photos: { id: string; storage_path: string; position: number; moderation_status: string }[];
  consents: Partial<Record<ConsentType, number>>;
  sensitive: {
    seeking_genders?: Gender[];
    situation?: Situation;
    structure?: Structure;
    orientation?: string;
    orientation_visible?: boolean;
  };
}

export type SearchMode = 'radius' | 'department' | 'region';

export interface SearchPreferences {
  mode: SearchMode;
  radius_km: number;
  age_min: number;
  age_max: number;
  drinks: Drink[] | null;
}

/** What the feed shows of another profile: public fields only, distance as a range. */
export interface ProfileCard {
  id: string;
  first_name: string;
  age: number;
  gender: Gender;
  gender_detail: string | null;
  bio: string | null;
  verified: boolean;
  recently_active: boolean;
  distance: DistanceBucket;
  drinks: Drink[];
  matched_drinks: Drink[];
  orientation: string | null;
  prompts: { question_code: string; answer: string }[];
  photos: { id: string; storage_path: string }[];
}

export interface Feed {
  cards: ProfileCard[];
  mode: SearchMode;
  radius_km: number | null;
  widened: boolean;
}

export interface SeedProfileSummary {
  id: string;
  firstName: string;
  birthDate: string;
  gender: Gender;
  departmentCode: string | null;
  verified: boolean;
  drinks: Drink[];
}

export interface CountrySwitches {
  orientationEnabled: boolean;
  structureEnabled: boolean;
  compositionEnabled: boolean;
}

export const api = {
  getMyProfile: () => rpc<MyProfile>('get_my_profile'),

  /** Latest published version of each legal text. */
  async latestConsentVersions(): Promise<Record<ConsentType, number>> {
    const { data, error } = await supabase.from('consent_texts').select('type, version');
    if (error) throw new AppError(errorCode(error));
    const latest = {} as Record<ConsentType, number>;
    for (const row of data as { type: ConsentType; version: number }[]) {
      latest[row.type] = Math.max(latest[row.type] ?? 0, row.version);
    }
    return latest;
  },
  grantConsent: (type: ConsentType, version: number) => rpc('grant_consent', { p_type: type, p_version: version }),
  withdrawConsent: (type: ConsentType) => rpc('withdraw_consent', { p_type: type }),

  async configInt(key: string): Promise<number> {
    const { data, error } = await supabase.from('app_config').select('value').eq('key', key).single();
    if (error) throw new AppError(errorCode(error));
    return Number(data.value);
  },

  async countrySwitches(countryCode: string | null): Promise<CountrySwitches> {
    const codes = countryCode ? [countryCode, '*'] : ['*'];
    const { data, error } = await supabase
      .from('country_config')
      .select('country_code, orientation_enabled, structure_enabled, composition_enabled')
      .in('country_code', codes);
    if (error) throw new AppError(errorCode(error));
    const row = data.find((r) => r.country_code === countryCode) ?? data.find((r) => r.country_code === '*');
    return {
      orientationEnabled: row?.orientation_enabled ?? true,
      structureEnabled: row?.structure_enabled ?? true,
      compositionEnabled: row?.composition_enabled ?? true,
    };
  },

  setBirthDate: (birthDate: string) => rpc('set_my_birth_date', { p_birth_date: birthDate }),
  setReferralCode: (code: string, befriend: boolean) =>
    rpc('set_my_referral_code', { p_code: code, p_befriend_referrer: befriend }),
  setIdentity: (firstName: string, gender: Gender, genderDetail: string | null) =>
    rpc('set_my_identity', { p_first_name: firstName, p_gender: gender, p_gender_detail: genderDetail }),
  setSeeking: (seeking: Gender[]) => rpc('set_my_seeking', { p_seeking_genders: seeking }),
  setIntent: (i: {
    situation: Situation;
    drinks: Drink[];
    structure: Structure | null;
    composition: CompositionChoice | null;
    openToCouples: boolean;
  }) =>
    rpc('set_my_intent', {
      p_situation: i.situation,
      p_drinks: i.drinks,
      p_structure: i.structure,
      p_composition: i.composition && {
        kinds: i.composition.kinds,
        three_plus_genders: i.composition.threePlusGenders,
      },
      p_open_to_couples: i.openToCouples,
    }),
  async setAlcoholFreeIcons(value: boolean, userId: string) {
    const { error } = await supabase.from('profiles').update({ alcohol_free_icons: value }).eq('id', userId);
    if (error) throw new AppError(errorCode(error));
  },
  setPrompts: (prompts: { question_code: string; answer: string }[]) => rpc('set_my_prompts', { p_prompts: prompts }),
  addPhoto: (path: string) => rpc<string>('add_my_photo', { p_storage_path: path }),
  removePhoto: (id: string) => rpc<string>('remove_my_photo', { p_photo_id: id }),
  reorderPhotos: (ids: string[]) => rpc('reorder_my_photos', { p_photo_ids: ids }),
  submitSelfie: (path: string) => rpc('submit_my_selfie', { p_storage_path: path }),
  setOrientation: (label: string | null, visible: boolean) =>
    rpc('set_my_orientation', { p_label: label, p_visible: visible }),
  completeOnboarding: () => rpc('complete_onboarding'),

  getFeed: (limit?: number) => rpc<Feed>('get_feed', limit ? { p_limit: limit } : {}),
  passProfile: (targetId: string) => rpc('pass_profile', { p_target_id: targetId }),
  setSearchPreferences: (p: SearchPreferences) =>
    rpc('set_my_search_preferences', {
      p_mode: p.mode,
      p_radius_km: p.mode === 'radius' ? p.radius_km : null,
      p_age_min: p.age_min,
      p_age_max: p.age_max,
      p_drinks: p.drinks,
    }),

  /** Development only ("tester en tant que"); the server refuses it anywhere else. */
  devListSeedProfiles: () => invoke<{ profiles: SeedProfileSummary[] }>('dev-impersonate', { action: 'list' }),
  devImpersonate: (userId: string) => invoke<{ tokenHash: string }>('dev-impersonate', { action: 'login', userId }),

  updateLocation: (body: { mode: 'device'; lat: number; lon: number } | { mode: 'home'; query: string }) =>
    invoke<{ label: string | null; countryCode: string | null }>('update-location', body),
  deleteAccount: () => invoke<{ deleted: boolean }>('delete-account', {}),
};
