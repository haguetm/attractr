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
  verification_in_review: boolean;
  warnings: number;
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

export type LikeTarget = { kind: 'photo' | 'prompt'; ref: string };

export type LikeQuota =
  | { unlimited: true }
  | { unlimited: false; limit: number; used: number; remaining: number; next_reset_at: string | null };

export interface LikeResult {
  matched: boolean;
  match_id: string | null;
  conversation_id: string | null;
  quota: LikeQuota;
}

export interface MatchSummary {
  match_id: string;
  conversation_id: string;
  created_at: string;
  matched_drinks: Drink[];
  /** Set while no message has been sent yet (24 h window). */
  first_message_deadline: string | null;
  extensions_left: number;
  other: { id: string; first_name: string; age: number; verified: boolean; drinks: Drink[]; photo_path: string | null };
  last_message: { body: string; mine: boolean; created_at: string } | null;
  unread_count: number;
  my_turn: boolean;
}

export interface ChatMessage {
  id: number;
  conversation_id: string;
  sender_id: string;
  body: string;
  created_at: string;
}

export const REPORT_REASONS = [
  'suspected_minor',
  'misleading_intent',
  'scam',
  'harassment',
  'inappropriate_photo',
  'fake_profile',
  'other',
] as const;
export type ReportReason = (typeof REPORT_REASONS)[number];

export type SelfieOutcome = 'verified' | 'retake' | 'review';
export type PhotoOutcome = 'approved' | 'rejected' | 'review' | 'pending';

export interface MyBlocks {
  profiles: { id: string; first_name: string; blocked_at: string }[];
  contacts_blocked: boolean;
}

export interface FriendSummary {
  id: string;
  first_name: string;
  username: string | null;
}

export interface MyFriends {
  username: string | null;
  max: number;
  friends: FriendSummary[];
  incoming: FriendSummary[];
  outgoing: FriendSummary[];
}

export type OutingStatus = 'planned' | 'past' | 'cancelled';

/** What the matched pair sees of their outing. */
export interface MatchOuting {
  id: string;
  place: string;
  starts_at: string;
  status: OutingStatus;
  created_by_me: boolean;
  participants: number;
  min_participants: number;
  max_participants: number;
  invitations: { first_name: string; response: 'pending' | 'going' | 'not_going'; mine: boolean; friend_id: string | null }[];
  my_feedback_given: boolean;
}

/** What an invited friend sees (spec §7): no profile, drink or like. */
export interface OutingCard {
  outing_id: string;
  place: string;
  starts_at: string;
  status: OutingStatus;
  matched_first_names: [string, string];
  invited_by: string;
  response: 'pending' | 'going' | 'not_going';
  participants: number;
  my_feedback_given: boolean;
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

  likeProfile: (targetId: string, target: LikeTarget) =>
    rpc<LikeResult>('like_profile', { p_target_id: targetId, p_target_kind: target.kind, p_target_ref: target.ref }),
  getLikeQuota: () => rpc<LikeQuota>('get_like_quota'),
  getLikesReceivedCount: () => rpc<number>('get_likes_received_count'),

  getMyMatches: () => rpc<MatchSummary[]>('get_my_matches'),
  getMatchProfile: (matchId: string) => rpc<ProfileCard>('get_match_profile', { p_match_id: matchId }),
  extendMatch: (matchId: string) => rpc<string>('extend_match', { p_match_id: matchId }),
  unmatch: (matchId: string) => rpc('unmatch', { p_match_id: matchId }),

  async getMessages(conversationId: string, limit = 100): Promise<ChatMessage[]> {
    const { data, error } = await supabase
      .from('messages')
      .select('id, conversation_id, sender_id, body, created_at')
      .eq('conversation_id', conversationId)
      .order('created_at', { ascending: false })
      .limit(limit);
    if (error) throw new AppError(errorCode(error));
    return data as ChatMessage[];
  },
  sendMessage: (conversationId: string, body: string) =>
    rpc<number>('send_message', { p_conversation_id: conversationId, p_body: body }),
  markRead: (conversationId: string) => rpc('mark_conversation_read', { p_conversation_id: conversationId }),

  verifySelfie: () => invoke<{ outcome: SelfieOutcome }>('verify-selfie', {}),
  moderatePhoto: (photoId: string) => invoke<{ outcome: PhotoOutcome }>('moderate-photo', { photoId }),

  reportProfile: (p: { targetId: string; reason: ReportReason; details?: string; conversationId?: string; alsoBlock: boolean }) =>
    rpc<number>('report_profile', {
      p_target_id: p.targetId,
      p_reason: p.reason,
      p_details: p.details?.trim() || null,
      p_conversation_id: p.conversationId ?? null,
      p_also_block: p.alsoBlock,
    }),
  blockProfile: (targetId: string) => rpc('block_profile', { p_target_id: targetId }),
  unblockProfile: (targetId: string) => rpc('unblock_profile', { p_target_id: targetId }),
  getMyBlocks: () => rpc<MyBlocks>('get_my_blocks'),
  blockContacts: (digests: string[]) => rpc('block_contacts', { p_digests: digests }),
  unblockContacts: () => rpc('unblock_contacts'),
  setPaused: (paused: boolean) => rpc('set_my_paused', { p_paused: paused }),

  setUsername: (username: string) => rpc('set_my_username', { p_username: username }),
  getMyFriends: () => rpc<MyFriends>('get_my_friends'),
  requestFriend: (username: string) => rpc('request_friend_by_username', { p_username: username }),
  respondFriendRequest: (otherId: string, accept: boolean) =>
    rpc('respond_friend_request', { p_other_id: otherId, p_accept: accept }),
  createFriendInvite: () => rpc<string>('create_friend_invite'),
  previewFriendInvite: (code: string) => rpc<{ first_name: string } | null>('preview_friend_invite', { p_code: code }),
  acceptFriendInvite: (code: string) => rpc('accept_friend_invite', { p_code: code }),
  removeFriend: (otherId: string) => rpc('remove_friend', { p_other_id: otherId }),

  createOuting: (matchId: string, place: string, startsAt: Date) =>
    rpc<string>('create_outing', { p_match_id: matchId, p_place: place, p_starts_at: startsAt.toISOString() }),
  inviteToOuting: (outingId: string, friendIds: string[]) =>
    rpc('invite_to_outing', { p_outing_id: outingId, p_friend_ids: friendIds }),
  cancelOuting: (outingId: string) => rpc('cancel_outing', { p_outing_id: outingId }),
  getMatchOuting: (matchId: string) => rpc<MatchOuting | null>('get_match_outing', { p_match_id: matchId }),
  getMyOutingInvitations: () => rpc<OutingCard[]>('get_my_outing_invitations'),
  respondToOuting: (outingId: string, going: boolean) => rpc('respond_to_outing', { p_outing_id: outingId, p_going: going }),
  giveOutingFeedback: (outingId: string, rating: number, comment: string) =>
    rpc('give_outing_feedback', { p_outing_id: outingId, p_rating: rating, p_comment: comment.trim() || null }),

  registerPushToken: (token: string, platform: 'ios' | 'android' | 'web') =>
    rpc('register_push_token', { p_token: token, p_platform: platform }),
  unregisterPushToken: (token: string) => rpc('unregister_push_token', { p_token: token }),

  /** Development only ("tester en tant que"); the server refuses it anywhere else. */
  devListSeedProfiles: () => invoke<{ profiles: SeedProfileSummary[] }>('dev-impersonate', { action: 'list' }),
  devImpersonate: (userId: string) => invoke<{ tokenHash: string }>('dev-impersonate', { action: 'login', userId }),

  updateLocation: (body: { mode: 'device'; lat: number; lon: number } | { mode: 'home'; query: string }) =>
    invoke<{ label: string | null; countryCode: string | null }>('update-location', body),
  deleteAccount: () => invoke<{ deleted: boolean }>('delete-account', {}),
};
