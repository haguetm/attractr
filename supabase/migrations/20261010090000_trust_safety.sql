-- Phase 5 (spec §12): selfie verification and age check, photo moderation, reports,
-- blocks (including phone contacts), pause mode, simple scam rules, the human review
-- queue and moderator functions. External providers are called by Edge Functions only;
-- this file holds the rules applied to their results.

insert into public.app_config (key, value, description, is_public) values
  ('verification.adult_age', '18', 'Estimated age below this suspends the profile until human review.', false),
  ('verification.age_gap_review_years', '5', 'Declared vs estimated age gap that sends the selfie to human review (provisoire).', false),
  ('verification.min_confidence', '0.7', 'Age estimates below this confidence go to human review (provisoire).', false),
  ('moderation.photo_reject_score', '0.9', 'Nudity/violence score at or above which a photo is rejected automatically (provisoire).', false),
  ('moderation.photo_review_score', '0.5', 'Score at or above which a photo goes to human review (provisoire).', false),
  ('reports.daily_limit', '10', 'Reports a user can file per 24 h (anti-abuse).', false),
  ('chat.scam_check_first_messages', '3', 'Links are refused in a sender''s first N messages of a conversation (provisoire).', true),
  ('providers.mock_selfie_outcome', '"pass"', 'Development only: pass | retake | review | minor | duplicate.', false),
  ('providers.mock_photo_outcome', '"approve"', 'Development only: approve | review | reject.', false);

-- Pepper for phone hashes kept after a closed minor account (Q22). Generated in the DB.
do $$
begin
  if not exists (select 1 from vault.secrets where name = 'phone_hash_pepper') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(32), 'base64'), 'phone_hash_pepper',
      'HMAC pepper for private.blocked_identities phone hashes. Never export.');
  end if;
end;
$$;

create function private.phone_hash(p_phone text)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select encode(extensions.hmac(regexp_replace(p_phone, '\D', '', 'g'),
                (select decrypted_secret from vault.decrypted_secrets where name = 'phone_hash_pepper'), 'sha256'), 'hex');
$$;

-- Moderation queue ----------------------------------------------------------------------
-- Priority 1 = urgent (possible minor), handled first (spec §12).

create table private.moderation_queue (
  id bigint generated always as identity primary key,
  kind text not null check (kind in ('selfie_review', 'photo_review', 'report', 'message_review')),
  subject_user_id uuid references public.profiles (id) on delete cascade,
  ref_id text,
  reason text not null,
  priority smallint not null default 2 check (priority between 1 and 3),
  status text not null default 'open' check (status in ('open', 'resolved')),
  decision text,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by text
);

create index moderation_queue_open_idx on private.moderation_queue (priority, created_at) where status = 'open';

create function private.enqueue(p_kind text, p_subject uuid, p_ref text, p_reason text, p_priority smallint default 2)
returns bigint
language sql
security definer
set search_path = ''
as $$
  insert into private.moderation_queue (kind, subject_user_id, ref_id, reason, priority)
  values (p_kind, p_subject, p_ref, p_reason, p_priority)
  returning id;
$$;

-- Identity: one face, one phone, and no comeback after a closed minor account --------------

create table private.face_templates (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  -- Provider's opaque face reference, not an image nor a biometric template.
  face_id text not null unique,
  created_at timestamptz not null default now()
);

create table private.blocked_identities (
  id bigint generated always as identity primary key,
  phone_hash text,
  face_id text,
  reason text not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null
);

create index blocked_identities_phone_idx on private.blocked_identities (phone_hash);
create index blocked_identities_face_idx on private.blocked_identities (face_id);

-- SHA-256 of each account's phone digits, for "block my phone contacts" (Q23): the
-- device sends digests of its contacts, never the numbers, and nothing is stored.
create table private.phone_digests (
  user_id uuid primary key references auth.users (id) on delete cascade,
  digest text not null
);

create index phone_digests_digest_idx on private.phone_digests (digest);

-- BEFORE so a blocked phone cannot sign up; digests need the row, so a second AFTER trigger.
create function private.check_blocked_phone()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.phone is not null and exists (
    select 1 from private.blocked_identities b
    where b.phone_hash = private.phone_hash(new.phone) and b.expires_at > now()
  ) then
    raise exception 'identity_blocked';
  end if;
  return new;
end;
$$;

create function private.sync_phone_digest()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.phone is null then
    delete from private.phone_digests where user_id = new.id;
  else
    insert into private.phone_digests (user_id, digest)
    values (new.id, encode(extensions.digest(regexp_replace(new.phone, '\D', '', 'g'), 'sha256'), 'hex'))
    on conflict (user_id) do update set digest = excluded.digest;
  end if;
  return new;
end;
$$;

create trigger before_auth_user_created_check_phone
  before insert on auth.users
  for each row execute function private.check_blocked_phone();

create trigger on_auth_user_phone_digest
  after insert or update of phone on auth.users
  for each row execute function private.sync_phone_digest();

-- Existing accounts (seed, earlier users).
insert into private.phone_digests (user_id, digest)
select id, encode(extensions.digest(regexp_replace(phone, '\D', '', 'g'), 'sha256'), 'hex')
from auth.users where phone is not null
on conflict (user_id) do nothing;

-- Accounts to erase by the process-deletions Edge Function (Storage + auth user).
create table private.pending_deletions (
  user_id uuid primary key,
  reason text not null check (reason in ('minor', 'moderation', 'user')),
  requested_at timestamptz not null default now(),
  processed_at timestamptz
);

-- Storage files to remove (e.g. a selfie once its review is over).
create table private.storage_cleanup (
  id bigint generated always as identity primary key,
  bucket text not null,
  path text not null,
  requested_at timestamptz not null default now(),
  processed_at timestamptz
);

create table private.user_warnings (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  reason text not null,
  created_at timestamptz not null default now()
);

alter type public.notification_kind add value if not exists 'moderation_notice';

-- Selfie verification (spec §12) ---------------------------------------------------------

alter table private.selfie_submissions
  add column result jsonb,
  add column outcome text check (outcome in ('verified', 'retake', 'review'));

create function public.service_latest_selfie(p_user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('id', s.id, 'storage_path', s.storage_path, 'declared_age', private.age_of(p.birth_date))
  from private.selfie_submissions s
  join public.profiles p on p.id = s.user_id
  where s.user_id = p_user_id and s.processed_at is null
  order by s.submitted_at desc
  limit 1;
$$;

-- Applies the provider result. Outcomes:
--   retake   : no live face; the user takes a new selfie.
--   review   : possible minor (profile suspended meanwhile, urgent), duplicate face,
--              low confidence or a large declared/estimated gap -> human review.
--   verified : badge granted, face reference stored (one face = one account, spec §9).
create function private.apply_selfie_result(
  p_submission_id bigint,
  p_live boolean,
  p_estimated_age integer,
  p_confidence numeric,
  p_face_id text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  s private.selfie_submissions;
  p public.profiles;
  declared integer;
  v_outcome text;
  v_reason text;
begin
  select * into s from private.selfie_submissions where id = p_submission_id for update;
  if s.id is null or s.processed_at is not null then
    raise exception 'selfie_not_found';
  end if;
  select * into p from public.profiles where id = s.user_id for update;
  declared := private.age_of(p.birth_date);

  if not p_live then
    v_outcome := 'retake';
  elsif p_estimated_age < private.config_int('verification.adult_age') then
    v_outcome := 'review';
    v_reason := 'possible_minor';
  elsif exists (select 1 from private.face_templates f where f.face_id = p_face_id and f.user_id <> s.user_id)
     or exists (select 1 from private.blocked_identities b where b.face_id = p_face_id and b.expires_at > now()) then
    v_outcome := 'review';
    v_reason := 'duplicate_face';
  elsif p_confidence < (private.config('verification.min_confidence'))::numeric
     or abs(declared - p_estimated_age) > private.config_int('verification.age_gap_review_years') then
    v_outcome := 'review';
    v_reason := 'age_mismatch';
  else
    v_outcome := 'verified';
  end if;

  update private.selfie_submissions
     set processed_at = now(), outcome = v_outcome,
         status = case v_outcome when 'verified' then 'verified' when 'retake' then 'rejected' else 'pending' end::public.verification_status,
         result = jsonb_build_object('live', p_live, 'estimated_age', p_estimated_age, 'confidence', p_confidence,
                                     'face_id', p_face_id, 'reason', v_reason)
   where id = s.id;

  if v_outcome = 'verified' then
    update public.profiles set verification_status = 'verified', verified_at = now() where id = p.id;
    insert into private.face_templates (user_id, face_id) values (p.id, p_face_id)
    on conflict (user_id) do update set face_id = excluded.face_id;
    insert into private.storage_cleanup (bucket, path) values ('selfies', s.storage_path);
  elsif v_outcome = 'retake' then
    update public.profiles set verification_status = 'rejected' where id = p.id;
    insert into private.storage_cleanup (bucket, path) values ('selfies', s.storage_path);
  else
    update public.profiles set verification_status = 'pending' where id = p.id;
    if v_reason = 'possible_minor' and p.status in ('active', 'paused', 'onboarding') then
      -- Hidden from everyone until a human decides (spec §12).
      update public.profiles set status = 'suspended' where id = p.id;
    end if;
    perform private.enqueue('selfie_review', p.id, s.id::text, v_reason,
                            case when v_reason = 'possible_minor' then 1 else 2 end::smallint);
  end if;
  return v_outcome;
end;
$$;

create function public.service_record_selfie_result(
  p_submission_id bigint, p_live boolean, p_estimated_age integer, p_confidence numeric, p_face_id text
)
returns text
language sql
security definer
set search_path = ''
as $$
  select private.apply_selfie_result(p_submission_id, p_live, p_estimated_age, p_confidence, p_face_id);
$$;

-- Photo moderation -----------------------------------------------------------------------------

create function private.apply_photo_result(p_photo_id uuid, p_nudity numeric, p_violence numeric)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  score numeric := greatest(coalesce(p_nudity, 0), coalesce(p_violence, 0));
  ph public.photos;
  outcome text;
begin
  select * into ph from public.photos where id = p_photo_id for update;
  if ph.id is null then
    raise exception 'photo_not_found';
  end if;
  if score >= (private.config('moderation.photo_reject_score'))::numeric then
    outcome := 'rejected';
  elsif score >= (private.config('moderation.photo_review_score'))::numeric then
    outcome := 'review';
  else
    outcome := 'approved';
  end if;
  if outcome = 'review' then
    perform private.enqueue('photo_review', ph.user_id, ph.id::text,
                            case when p_nudity >= coalesce(p_violence, 0) then 'nudity' else 'violence' end);
  else
    update public.photos set moderation_status = outcome::public.moderation_status where id = ph.id;
  end if;
  return outcome;
end;
$$;

create function public.service_record_photo_result(p_photo_id uuid, p_nudity numeric, p_violence numeric)
returns text
language sql
security definer
set search_path = ''
as $$
  select private.apply_photo_result(p_photo_id, p_nudity, p_violence);
$$;

-- Pending photos not yet sent to review (batch run by moderate-photo).
create function public.service_pending_photos(p_limit integer default 50)
returns table (id uuid, user_id uuid, storage_path text)
language sql
stable
security definer
set search_path = ''
as $$
  select ph.id, ph.user_id, ph.storage_path
  from public.photos ph
  where ph.moderation_status = 'pending'
    and not exists (select 1 from private.moderation_queue q
                    where q.kind = 'photo_review' and q.ref_id = ph.id::text and q.status = 'open')
  order by ph.created_at
  limit p_limit;
$$;

-- Other people only ever see approved photos from now on.
create or replace function private.profile_card(p_candidate_id uuid, p_distance_m double precision, p_matched public.drink[])
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p.id,
    'first_name', p.first_name,
    'age', private.age_of(p.birth_date),
    'gender', p.gender,
    'gender_detail', p.gender_detail,
    'bio', p.bio,
    'verified', p.verification_status = 'verified',
    'recently_active', coalesce(p.last_reply_at > now() - make_interval(hours => private.config_int('activity.badge_window_hours')), false),
    'distance', private.distance_bucket(coalesce(p_distance_m, 0)),
    'drinks', coalesce((select jsonb_agg(d.drink order by d.drink) from public.profile_drinks d where d.user_id = p.id), '[]'::jsonb),
    'matched_drinks', to_jsonb(p_matched),
    'orientation', case
        when (s ->> 'orientation_visible')::boolean and (private.country_switches(p.country_code)).orientation_enabled
        then s ->> 'orientation' end,
    'prompts', coalesce((select jsonb_agg(jsonb_build_object('question_code', q.question_code, 'answer', q.answer) order by q.position)
                         from public.profile_prompts q where q.user_id = p.id), '[]'::jsonb),
    'photos', coalesce((select jsonb_agg(jsonb_build_object('id', ph.id, 'storage_path', ph.storage_path) order by ph.position)
                        from public.photos ph where ph.user_id = p.id and ph.moderation_status = 'approved'), '[]'::jsonb)
  )
  from public.profiles p
  cross join lateral (select private.read_sensitive(p.id) as s) sens
  where p.id = p_candidate_id;
$$;

-- Rejected photos do not count towards the onboarding minimum.
create or replace function public.complete_onboarding()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  p public.profiles;
  s jsonb;
begin
  select * into p from public.profiles where id = uid for update;
  if p.status <> 'onboarding' then
    return;
  end if;
  if not (private.has_consent(uid, 'terms') and private.has_consent(uid, 'privacy')) then
    raise exception 'onboarding_incomplete:terms';
  end if;
  if not private.has_consent(uid, 'sensitive_data') then
    raise exception 'onboarding_incomplete:sensitive_consent';
  end if;
  if p.birth_date is null or p.first_name is null or p.gender is null then
    raise exception 'onboarding_incomplete:identity';
  end if;
  s := private.read_sensitive(uid);
  if s -> 'seeking_genders' is null then
    raise exception 'onboarding_incomplete:seeking';
  end if;
  if s ->> 'situation' is null or not exists (select 1 from public.profile_drinks where user_id = uid) then
    raise exception 'onboarding_incomplete:intent';
  end if;
  if (select count(*) from public.profile_prompts where user_id = uid) <> 3 then
    raise exception 'onboarding_incomplete:prompts';
  end if;
  if (select count(*) from public.photos where user_id = uid and moderation_status <> 'rejected')
     < private.config_int('photos.min_count') then
    raise exception 'onboarding_incomplete:photos';
  end if;
  if p.verification_status not in ('pending', 'verified') then
    raise exception 'onboarding_incomplete:selfie';
  end if;
  if p.location is null then
    raise exception 'onboarding_incomplete:location';
  end if;
  update public.profiles set status = 'active' where id = uid;
end;
$$;

-- Blocks -------------------------------------------------------------------------------------------

alter table public.blocks
  add column source text not null default 'user' check (source in ('user', 'contacts', 'report'));

-- Blocking hides both people from each other and closes their match (spec §12).
create function private.block(p_blocker uuid, p_blocked uuid, p_source text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_blocker = p_blocked then
    raise exception 'cannot_block_self';
  end if;
  insert into public.blocks (blocker_id, blocked_id, source) values (p_blocker, p_blocked, p_source)
  on conflict (blocker_id, blocked_id) do nothing;
  update public.matches set status = 'unmatched', ended_at = now(), ended_by = p_blocker
   where status = 'active' and user_a = least(p_blocker, p_blocked) and user_b = greatest(p_blocker, p_blocked);
end;
$$;

create function public.block_profile(p_target_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from public.profiles where id = p_target_id) then
    raise exception 'profile_unavailable';
  end if;
  perform private.block(private.require_user(), p_target_id, 'user');
end;
$$;

create function public.unblock_profile(p_target_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.blocks where blocker_id = (select auth.uid()) and blocked_id = p_target_id and source <> 'contacts';
$$;

-- People the caller blocked by hand. Contact blocks are only counted: listing them
-- would reveal which contacts use the app.
create function public.get_my_blocks()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'profiles', coalesce((
      select jsonb_agg(jsonb_build_object('id', p.id, 'first_name', p.first_name, 'blocked_at', b.created_at) order by b.created_at desc)
      from public.blocks b join public.profiles p on p.id = b.blocked_id
      where b.blocker_id = (select auth.uid()) and b.source <> 'contacts'), '[]'::jsonb),
    'contacts_blocked', exists (select 1 from public.blocks b where b.blocker_id = (select auth.uid()) and b.source = 'contacts')
  );
$$;

-- "Bloquer mes contacts" (Q23): SHA-256 digests of the contacts' numbers (digits of the
-- E.164 form). Matching accounts are blocked; digests are not stored.
create function public.block_contacts(p_digests text[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  target uuid;
begin
  if cardinality(p_digests) > 5000 then
    raise exception 'too_many_contacts';
  end if;
  for target in
    select d.user_id from private.phone_digests d
    where d.digest = any (p_digests) and d.user_id <> uid
      and exists (select 1 from public.profiles p where p.id = d.user_id)
  loop
    perform private.block(uid, target, 'contacts');
  end loop;
end;
$$;

create function public.unblock_contacts()
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.blocks where blocker_id = (select auth.uid()) and source = 'contacts';
$$;

-- Reports ------------------------------------------------------------------------------------------

alter table public.reports
  add column details text check (char_length(details) <= 1000),
  add column conversation_id uuid references public.conversations (id) on delete set null,
  add column status text not null default 'open' check (status in ('open', 'validated', 'dismissed')),
  add column reviewed_at timestamptz,
  add constraint reports_reason_check check (reason in (
    'misleading_intent', 'suspected_minor', 'scam', 'harassment', 'inappropriate_photo',
    'fake_profile', 'couple_pressure', 'other', 'test'));

-- Reports are visible to the reporter only, through get_my_reports if ever needed.
create function public.report_profile(
  p_target_id uuid,
  p_reason text,
  p_details text default null,
  p_conversation_id uuid default null,
  p_also_block boolean default true
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  report_id bigint;
begin
  if p_target_id = uid then
    raise exception 'cannot_report_self';
  end if;
  if not exists (select 1 from public.profiles where id = p_target_id) then
    raise exception 'profile_unavailable';
  end if;
  if p_reason = 'test' or p_reason is null then
    raise exception 'invalid_report_reason';
  end if;
  if (select count(*) from public.reports where reporter_id = uid and created_at > now() - interval '24 hours')
     >= private.config_int('reports.daily_limit') then
    raise exception 'report_limit_reached';
  end if;
  if p_conversation_id is not null and not exists (
    select 1 from public.conversation_members where conversation_id = p_conversation_id and user_id = uid
  ) then
    raise exception 'conversation_not_found';
  end if;

  insert into public.reports (reporter_id, reported_id, reason, details, conversation_id)
  values (uid, p_target_id, p_reason, nullif(btrim(p_details), ''), p_conversation_id)
  returning id into report_id;

  -- "Suspicion de mineur" is handled first (spec §12).
  perform private.enqueue('report', p_target_id, report_id::text, p_reason,
                          case when p_reason = 'suspected_minor' then 1 else 2 end::smallint);
  if p_also_block then
    perform private.block(uid, p_target_id, 'report');
  end if;
  return report_id;
end;
$$;

-- Pause mode (spec §12): hidden from the feed, matches and chats keep working.
create function public.set_my_paused(p_paused boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  current_status public.profile_status;
begin
  select status into current_status from public.profiles where id = uid;
  if current_status not in ('active', 'paused') then
    raise exception 'profile_not_active';
  end if;
  update public.profiles set status = case when p_paused then 'paused' else 'active' end::public.profile_status where id = uid;
end;
$$;

-- Chat: scam rules (spec §12, V1 = simple rules) ------------------------------------------------
-- Links are refused in a sender's first messages; money requests go to human review.

create function private.looks_like_link(p_body text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_body ~* '(https?://|www\.|\m[a-z0-9-]+\.(com|fr|net|org|io|me|ly|gg|app|link|xyz|info|biz|ru|tk)(/|\M))';
$$;

create function private.looks_like_money_request(p_body text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_body ~* '(western ?union|moneygram|virement|\miban\M|bitcoin|\mbtc\M|crypto|usdt|paypal|transcash|neosurf|carte[s]? cadeau|coupon[s]? pcs|mandat cash|pr[eê]te[rz]?[- ]moi|envoie[rz]?[- ]moi .{0,20}(argent|euros?|€)|besoin d.argent)';
$$;

create or replace function public.send_message(p_conversation_id uuid, p_body text)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  c public.conversations;
  m public.matches;
  body text := btrim(p_body);
  new_id bigint;
  recipient uuid;
begin
  select * into c from public.conversations where id = p_conversation_id;
  if c.id is null or not exists (
    select 1 from public.conversation_members where conversation_id = c.id and user_id = uid
  ) then
    raise exception 'conversation_not_found';
  end if;
  if (select status from public.profiles where id = uid) not in ('active', 'paused') then
    raise exception 'profile_not_active';
  end if;
  if body is null or char_length(body) = 0 or char_length(body) > private.config_int('chat.message_max_length') then
    raise exception 'message_length';
  end if;

  if c.kind = 'match' then
    select * into m from public.matches where id = c.match_id for update;
    -- The status itself is updated by private.expire_matches (scheduled job).
    if m.status = 'active' and m.first_message_at is null and now() > m.first_message_deadline then
      raise exception 'match_expired';
    end if;
    if not private.match_is_open(m) then
      raise exception 'match_closed';
    end if;
  end if;

  if private.looks_like_link(body) and (
    select count(*) from public.messages where conversation_id = c.id and sender_id = uid
  ) < private.config_int('chat.scam_check_first_messages') then
    raise exception 'links_not_allowed_yet';
  end if;

  if c.kind = 'match' and m.first_message_at is null then
    update public.matches set first_message_at = now() where id = m.id;
  end if;

  insert into public.messages (conversation_id, sender_id, body) values (c.id, uid, body) returning id into new_id;
  update public.conversations set last_message_at = now() where id = c.id;
  update public.conversation_members set last_read_at = now() where conversation_id = c.id and user_id = uid;
  update public.profiles set last_reply_at = now(), last_active_at = now() where id = uid;

  if private.looks_like_money_request(body) then
    perform private.enqueue('message_review', uid, new_id::text, 'money_request');
  end if;

  for recipient in
    select user_id from public.conversation_members where conversation_id = c.id and user_id <> uid
  loop
    perform private.notify(recipient, 'new_message', jsonb_build_object('conversation_id', c.id));
  end loop;
  return new_id;
end;
$$;

-- Moderation (staff) -------------------------------------------------------------------------------
-- Called from the Supabase SQL editor (or a future back-office) as postgres. Every call
-- names the moderator and is written to private.access_log. See docs/MODERATION.md.

create function private.mod_queue(p_actor text, p_limit integer default 50)
returns table (id bigint, kind text, priority smallint, reason text, subject_user_id uuid, ref_id text, created_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.log_access(p_actor, null, 'moderation_queue', 'list open items');
  return query
  select q.id, q.kind, q.priority, q.reason, q.subject_user_id, q.ref_id, q.created_at
  from private.moderation_queue q where q.status = 'open'
  order by q.priority, q.created_at
  limit p_limit;
end;
$$;

create function private.mod_take(p_actor text, p_queue_id bigint, p_kind text)
returns private.moderation_queue
language plpgsql
security definer
set search_path = ''
as $$
declare
  q private.moderation_queue;
begin
  select * into q from private.moderation_queue where id = p_queue_id for update;
  if q.id is null or q.status <> 'open' or q.kind <> p_kind then
    raise exception 'queue_item_not_found';
  end if;
  perform private.log_access(p_actor, q.subject_user_id, 'moderation:' || q.kind, 'resolve item ' || q.id);
  return q;
end;
$$;

create function private.mod_close(p_queue_id bigint, p_actor text, p_decision text)
returns void
language sql
security definer
set search_path = ''
as $$
  update private.moderation_queue
     set status = 'resolved', decision = p_decision, resolved_at = now(), resolved_by = p_actor
   where id = p_queue_id;
$$;

-- A person identified as a minor: account closed, data erased (process-deletions), and the
-- phone hash + face reference kept for compliance.minor_trace_retention_days (Q22).
create function private.close_minor_account(p_user_id uuid, p_actor text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  retention interval := make_interval(days => private.config_int('compliance.minor_trace_retention_days'));
begin
  insert into private.blocked_identities (phone_hash, face_id, reason, expires_at)
  select private.phone_hash(u.phone),
         (select f.face_id from private.face_templates f where f.user_id = p_user_id),
         'minor', now() + retention
  from auth.users u where u.id = p_user_id;
  update public.profiles set status = 'closed' where id = p_user_id;
  update public.matches set status = 'unmatched', ended_at = now()
   where status = 'active' and p_user_id in (user_a, user_b);
  insert into private.pending_deletions (user_id, reason) values (p_user_id, 'minor')
  on conflict (user_id) do nothing;
  perform private.log_access(p_actor, p_user_id, 'account', 'closed: minor');
end;
$$;

create function private.mod_resolve_selfie(p_actor text, p_queue_id bigint, p_decision text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  q private.moderation_queue := private.mod_take(p_actor, p_queue_id, 'selfie_review');
  s private.selfie_submissions;
begin
  if p_decision not in ('verified', 'retake', 'minor') then
    raise exception 'invalid_decision';
  end if;
  select * into s from private.selfie_submissions where id = q.ref_id::bigint;
  if p_decision = 'minor' then
    perform private.close_minor_account(q.subject_user_id, p_actor);
  elsif p_decision = 'verified' then
    update public.profiles
       set verification_status = 'verified', verified_at = now(),
           status = case when status = 'suspended' then 'active' else status end
     where id = q.subject_user_id;
    if s.result ->> 'face_id' is not null then
      insert into private.face_templates (user_id, face_id) values (q.subject_user_id, s.result ->> 'face_id')
      on conflict (user_id) do update set face_id = excluded.face_id;
    end if;
  else
    update public.profiles
       set verification_status = 'rejected',
           status = case when status = 'suspended' then 'active' else status end
     where id = q.subject_user_id;
  end if;
  if s.id is not null then
    insert into private.storage_cleanup (bucket, path) values ('selfies', s.storage_path);
  end if;
  perform private.mod_close(q.id, p_actor, p_decision);
end;
$$;

create function private.mod_resolve_photo(p_actor text, p_queue_id bigint, p_decision text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  q private.moderation_queue := private.mod_take(p_actor, p_queue_id, 'photo_review');
begin
  if p_decision not in ('approved', 'rejected') then
    raise exception 'invalid_decision';
  end if;
  update public.photos set moderation_status = p_decision::public.moderation_status where id = q.ref_id::uuid;
  perform private.mod_close(q.id, p_actor, p_decision);
end;
$$;

-- Validated "intention trompeuse" reports: warning at the 3rd, suspension at the 4th (Q15).
create function private.apply_sanctions(p_user_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  validated integer;
begin
  select count(distinct reporter_id) into validated from public.reports
  where reported_id = p_user_id and reason = 'misleading_intent' and status = 'validated';
  if validated >= private.config_int('moderation.misleading_suspension_threshold') then
    update public.profiles set status = 'suspended' where id = p_user_id and status in ('active', 'paused');
    perform private.notify(p_user_id, 'moderation_notice', '{}');
    return 'suspended';
  elsif validated = private.config_int('moderation.misleading_warning_threshold') then
    insert into private.user_warnings (user_id, reason) values (p_user_id, 'misleading_intent');
    perform private.notify(p_user_id, 'moderation_notice', '{}');
    return 'warned';
  end if;
  return 'none';
end;
$$;

create function private.mod_resolve_report(p_actor text, p_queue_id bigint, p_decision text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  q private.moderation_queue := private.mod_take(p_actor, p_queue_id, 'report');
  r public.reports;
  sanction text := 'none';
begin
  if p_decision not in ('validated', 'dismissed') then
    raise exception 'invalid_decision';
  end if;
  update public.reports set status = p_decision, reviewed_at = now() where id = q.ref_id::bigint returning * into r;
  if p_decision = 'validated' then
    if r.reason = 'misleading_intent' then
      sanction := private.apply_sanctions(r.reported_id);
    elsif r.reason = 'suspected_minor' then
      perform private.close_minor_account(r.reported_id, p_actor);
      sanction := 'closed';
    elsif r.reason in ('scam', 'harassment', 'couple_pressure', 'fake_profile') then
      update public.profiles set status = 'suspended' where id = r.reported_id and status in ('active', 'paused');
      perform private.notify(r.reported_id, 'moderation_notice', '{}');
      sanction := 'suspended';
    end if;
  end if;
  perform private.mod_close(q.id, p_actor, p_decision || ':' || sanction);
  return sanction;
end;
$$;

create function private.mod_resolve_message(p_actor text, p_queue_id bigint, p_decision text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  q private.moderation_queue := private.mod_take(p_actor, p_queue_id, 'message_review');
begin
  if p_decision not in ('ok', 'scam') then
    raise exception 'invalid_decision';
  end if;
  if p_decision = 'scam' then
    update public.profiles set status = 'suspended' where id = q.subject_user_id and status in ('active', 'paused');
    perform private.notify(q.subject_user_id, 'moderation_notice', '{}');
  end if;
  perform private.mod_close(q.id, p_actor, p_decision);
end;
$$;

-- Server-side queues for the process-deletions Edge Function.
create function public.service_pending_deletions(p_limit integer default 50)
returns table (user_id uuid, reason text)
language sql
stable
security definer
set search_path = ''
as $$
  select d.user_id, d.reason from private.pending_deletions d where d.processed_at is null order by d.requested_at limit p_limit;
$$;

create function public.service_mark_deletion(p_user_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  update private.pending_deletions set processed_at = now() where user_id = p_user_id;
$$;

create function public.service_pending_storage_cleanup(p_limit integer default 200)
returns table (id bigint, bucket text, path text)
language sql
stable
security definer
set search_path = ''
as $$
  select c.id, c.bucket, c.path from private.storage_cleanup c where c.processed_at is null order by c.id limit p_limit;
$$;

create function public.service_mark_storage_cleanup(p_ids bigint[])
returns void
language sql
security definer
set search_path = ''
as $$
  update private.storage_cleanup set processed_at = now() where id = any (p_ids);
$$;

-- get_my_profile: adds warnings and whether the selfie is under human review.
create or replace function public.get_my_profile()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  prefs public.search_preferences := private.search_prefs(uid);
begin
  return (
    select jsonb_build_object(
      'id', p.id,
      'status', p.status,
      'is_seed', p.is_seed,
      'first_name', p.first_name,
      'birth_date', p.birth_date,
      'gender', p.gender,
      'gender_detail', p.gender_detail,
      'bio', p.bio,
      'open_to_couples', p.open_to_couples,
      'alcohol_free_icons', p.alcohol_free_icons,
      'verification_status', p.verification_status,
      'verification_in_review', exists (select 1 from private.moderation_queue q
                                        where q.kind = 'selfie_review' and q.subject_user_id = p.id and q.status = 'open'),
      'warnings', (select count(*) from private.user_warnings w where w.user_id = p.id),
      'country_code', p.country_code,
      'department_code', p.department_code,
      'region_code', p.region_code,
      'has_location', p.location is not null,
      'location_source', p.location_source,
      'drinks_changed_at', p.drinks_changed_at,
      'drinks', coalesce((select jsonb_agg(d.drink order by d.drink)
                          from public.profile_drinks d where d.user_id = p.id), '[]'::jsonb),
      'prompts', coalesce((select jsonb_agg(jsonb_build_object(
                             'position', q.position, 'question_code', q.question_code, 'answer', q.answer)
                           order by q.position)
                          from public.profile_prompts q where q.user_id = p.id), '[]'::jsonb),
      'photos', coalesce((select jsonb_agg(jsonb_build_object(
                            'id', ph.id, 'storage_path', ph.storage_path, 'position', ph.position,
                            'moderation_status', ph.moderation_status)
                          order by ph.position)
                         from public.photos ph where ph.user_id = p.id), '[]'::jsonb),
      'consents', coalesce((select jsonb_object_agg(c.type, c.version)
                            from public.consents c where c.user_id = p.id and c.withdrawn_at is null), '{}'::jsonb),
      'search', jsonb_build_object('mode', prefs.mode, 'radius_km', prefs.radius_km, 'age_min', prefs.age_min,
                                   'age_max', prefs.age_max, 'drinks', to_jsonb(prefs.drinks)),
      'sensitive', private.read_sensitive(p.id)
    )
    from public.profiles p where p.id = uid
  );
end;
$$;

-- Grants ---------------------------------------------------------------------------------------

do $$
declare
  f text;
begin
  foreach f in array array[
    'public.block_profile(uuid)',
    'public.unblock_profile(uuid)',
    'public.get_my_blocks()',
    'public.block_contacts(text[])',
    'public.unblock_contacts()',
    'public.report_profile(uuid, text, text, uuid, boolean)',
    'public.set_my_paused(boolean)'
  ]
  loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;

  foreach f in array array[
    'public.service_latest_selfie(uuid)',
    'public.service_record_selfie_result(bigint, boolean, integer, numeric, text)',
    'public.service_record_photo_result(uuid, numeric, numeric)',
    'public.service_pending_photos(integer)',
    'public.service_pending_deletions(integer)',
    'public.service_mark_deletion(uuid)',
    'public.service_pending_storage_cleanup(integer)',
    'public.service_mark_storage_cleanup(bigint[])'
  ]
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end;
$$;

-- Erasures and Storage cleanup every 5 minutes (Supabase stack only).
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron')
     and exists (select 1 from pg_available_extensions where name = 'pg_net') then
    perform cron.schedule(
      'attractr-process-deletions',
      '*/5 * * * *',
      $job$
        select net.http_post(
          url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/process-deletions',
          headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key')),
          body := '{}'::jsonb)
        where exists (select 1 from vault.decrypted_secrets where name = 'project_url')
          and exists (select 1 from vault.decrypted_secrets where name = 'service_role_key')
      $job$
    );
  end if;
end;
$$;
