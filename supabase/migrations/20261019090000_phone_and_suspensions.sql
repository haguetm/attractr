-- Phone number for every account, and suspended accounts (DECISIONS, "Connexion et
-- comptes suspendus").
--   Phone: whatever the sign-in method (SMS, email, Google, Apple), each account has a
--   phone number, the key of "bloquer mes contacts". Signing in by SMS verifies it; other
--   methods add it during onboarding: verified by SMS in production
--   (auth.phone_verification_required), declared without check in the free beta. Only a
--   SHA-256 digest (contacts) and an HMAC (re-signup checks) are kept, never the number.
--   Suspended accounts: their matches are put on hold (closed for both) and reopen when
--   the suspension is lifted; moderators lift a suspension with a logged function; an
--   account deleted while suspended leaves a time-limited trace (phone HMAC, face
--   reference) so that a return goes to human review.

insert into public.app_config (key, value, description, is_public) values
  ('auth.phone_verification_required', 'true',
   'The phone added during onboarding must be verified by SMS. Free beta only: false (declared number, no SMS cost).', true),
  ('compliance.suspended_trace_retention_days', '365',
   'Retention of the phone HMAC and face reference of an account deleted while suspended (provisoire, legal validation pending).', false);

-- Phone ------------------------------------------------------------------------------------

alter table private.phone_digests add column phone_hmac text;
create index phone_digests_hmac_idx on private.phone_digests (phone_hmac);

create or replace function private.sync_phone_digest()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.phone is null then
    -- A number declared during onboarding (beta) stays until a verified one replaces it.
    return new;
  end if;
  insert into private.phone_digests (user_id, digest, phone_hmac)
  values (new.id, encode(extensions.digest(regexp_replace(new.phone, '\D', '', 'g'), 'sha256'), 'hex'), private.phone_hash(new.phone))
  on conflict (user_id) do update set digest = excluded.digest, phone_hmac = excluded.phone_hmac;
  return new;
end;
$$;

update private.phone_digests d set phone_hmac = private.phone_hash(u.phone)
from auth.users u where u.id = d.user_id and u.phone is not null;

-- Only a closed minor account blocks a number at signup; a suspended one leads to review.
create or replace function private.check_blocked_phone()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.phone is not null and exists (
    select 1 from private.blocked_identities b
    where b.phone_hash = private.phone_hash(new.phone) and b.reason = 'minor' and b.expires_at > now()
  ) then
    raise exception 'identity_blocked';
  end if;
  return new;
end;
$$;

-- Declared number (beta): E.164, digits only are hashed. Refused when the project
-- requires an SMS-verified number, and after a verified number exists.
create function public.set_my_phone(p_phone text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  digits text := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
begin
  if (private.config('auth.phone_verification_required'))::boolean then
    raise exception 'phone_verification_required';
  end if;
  if exists (select 1 from auth.users where id = uid and phone is not null) then
    raise exception 'phone_already_verified';
  end if;
  if p_phone !~ '^\+[1-9][0-9]{7,14}$' then
    raise exception 'invalid_phone';
  end if;
  if exists (select 1 from private.blocked_identities b
             where b.phone_hash = private.phone_hash(digits) and b.reason = 'minor' and b.expires_at > now()) then
    raise exception 'identity_blocked';
  end if;
  insert into private.phone_digests (user_id, digest, phone_hmac)
  values (uid, encode(extensions.digest(digits, 'sha256'), 'hex'), private.phone_hash(digits))
  on conflict (user_id) do update set digest = excluded.digest, phone_hmac = excluded.phone_hmac;
end;
$$;

revoke execute on function public.set_my_phone(text) from public, anon;
grant execute on function public.set_my_phone(text) to authenticated;

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
      'username', p.username,
      'has_phone', exists (select 1 from private.phone_digests d where d.user_id = p.id),
      'open_to_couples', p.open_to_couples,
      'alcohol_free_icons', p.alcohol_free_icons,
      'verification_status', p.verification_status,
      'verification_in_review', exists (select 1 from private.moderation_queue q
                                        where q.kind = 'selfie_review' and q.subject_user_id = p.id and q.status = 'open'),
      'warnings', (select count(*) from private.user_warnings w where w.user_id = p.id),
      'premium', jsonb_build_object(
        'active', private.is_premium(p.id),
        'until', private.premium_until(p.id),
        'paying', private.is_paying_subscriber(p.id)),
      'incognito', p.incognito,
      'education_level', p.education_level,
      'height_cm', p.height_cm,
      'interests', coalesce((select jsonb_agg(i.interest_code order by i.interest_code) from public.profile_interests i where i.user_id = p.id), '[]'::jsonb),
      'boost_credits', (select count(*) from private.boost_credits c where c.user_id = p.id and c.used_at is null),
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
      'search', jsonb_build_object(
        'mode', prefs.mode, 'radius_km', prefs.radius_km, 'age_min', prefs.age_min, 'age_max', prefs.age_max,
        'drinks', to_jsonb(prefs.drinks),
        'verified_only', coalesce(prefs.verified_only, false), 'recently_active', coalesce(prefs.recently_active, false),
        'education_levels', to_jsonb(prefs.education_levels), 'height_min', prefs.height_min, 'height_max', prefs.height_max,
        'interests', to_jsonb(prefs.interests), 'compositions', to_jsonb(prefs.compositions),
        'passport_label', prefs.passport_label),
      'sensitive', private.read_sensitive(p.id)
    )
    from public.profiles p where p.id = uid
  );
end;
$$;

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
  if not exists (select 1 from private.phone_digests d where d.user_id = uid) then
    raise exception 'onboarding_incomplete:phone';
  end if;
  update public.profiles set status = 'active' where id = uid;
end;
$$;

-- A minor's trace also covers a declared number.
create or replace function private.close_minor_account(p_user_id uuid, p_actor text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  retention interval := make_interval(days => private.config_int('compliance.minor_trace_retention_days'));
begin
  insert into private.blocked_identities (phone_hash, face_id, reason, expires_at)
  select coalesce(private.phone_hash(u.phone), (select d.phone_hmac from private.phone_digests d where d.user_id = u.id)),
         (select f.face_id from private.face_templates f where f.user_id = p_user_id),
         'minor', now() + retention
  from auth.users u where u.id = p_user_id;
  update public.profiles set status = 'closed' where id = p_user_id;
  update public.matches set status = 'unmatched', ended_at = now()
   where status in ('active', 'on_hold') and p_user_id in (user_a, user_b);
  insert into private.pending_deletions (user_id, reason) values (p_user_id, 'minor')
  on conflict (user_id) do nothing;
  perform private.log_access(p_actor, p_user_id, 'account', 'closed: minor');
end;
$$;

create or replace function private.apply_selfie_result(
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

  if not coalesce(p_live, false) then
    v_outcome := 'retake';
  elsif p_estimated_age is null or p_confidence is null or p_face_id is null or declared is null then
    -- Never verify on an incomplete answer.
    v_outcome := 'review';
    v_reason := 'incomplete_result';
  elsif p_estimated_age < private.config_int('verification.adult_age') then
    v_outcome := 'review';
    v_reason := 'possible_minor';
  elsif exists (select 1 from private.face_templates f where f.face_id = p_face_id and f.user_id <> s.user_id) then
    v_outcome := 'review';
    v_reason := 'duplicate_face';
  elsif exists (select 1 from private.blocked_identities b
                where b.expires_at > now()
                  and (b.face_id = p_face_id
                       or b.phone_hash = (select d.phone_hmac from private.phone_digests d where d.user_id = s.user_id))) then
    -- Face or phone of an account closed for minority, or deleted while suspended.
    v_outcome := 'review';
    v_reason := 'returning_account';
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
                            case when v_reason in ('possible_minor', 'returning_account') then 1 else 2 end::smallint);
  end if;
  return v_outcome;
end;
$$;

-- Suspensions ------------------------------------------------------------------------------

alter type public.match_status add value if not exists 'on_hold';

-- A suspended person disappears from the matches of others (closed for both); the matches
-- reopen when the suspension is lifted, unless the other side is suspended, closed or
-- blocked. A match still waiting for its first message gets a fresh window.
create function private.on_profile_status_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'suspended' and old.status <> 'suspended' then
    update public.matches set status = 'on_hold'
     where status = 'active' and new.id in (user_a, user_b);
  elsif old.status = 'suspended' and new.status in ('active', 'paused') then
    update public.matches m
       set status = 'active',
           first_message_deadline = case when m.first_message_at is null
             then now() + make_interval(hours => private.config_int('match.first_message_window_hours'))
             else m.first_message_deadline end
     where m.status = 'on_hold' and new.id in (m.user_a, m.user_b)
       and not exists (select 1 from public.profiles o
                       where o.id = case when m.user_a = new.id then m.user_b else m.user_a end
                         and o.status in ('suspended', 'closed'))
       and not private.is_blocked_pair(m.user_a, m.user_b);
  end if;
  return null;
end;
$$;

create trigger profiles_status_change
  after update of status on public.profiles
  for each row when (old.status is distinct from new.status)
  execute function private.on_profile_status_change();

-- Moderator: lifts a suspension (sanction served, report reviewed). A suspension for a
-- possible minor is resolved with mod_resolve_selfie instead.
create function private.mod_lift_suspension(p_actor text, p_user_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if char_length(btrim(coalesce(p_reason, ''))) < 5 then
    raise exception 'invalid_request';
  end if;
  update public.profiles set status = 'active' where id = p_user_id and status = 'suspended';
  if not found then
    raise exception 'not_suspended';
  end if;
  perform private.log_access(p_actor, p_user_id, 'account', 'suspension lifted: ' || btrim(p_reason));
  perform private.notify(p_user_id, 'moderation_notice', '{}');
end;
$$;

-- Deleting a suspended account stays possible (right to erasure, store rules) but leaves
-- a time-limited trace: a return with the same phone or face goes to human review.
create function private.trace_suspended_deletion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_phone text;
  v_face text;
begin
  if not exists (select 1 from public.profiles where id = old.id and status = 'suspended') then
    return old;
  end if;
  v_phone := coalesce(private.phone_hash(old.phone), (select d.phone_hmac from private.phone_digests d where d.user_id = old.id));
  v_face := (select f.face_id from private.face_templates f where f.user_id = old.id);
  if v_phone is not null or v_face is not null then
    insert into private.blocked_identities (phone_hash, face_id, reason, expires_at)
    values (v_phone, v_face, 'suspended',
            now() + make_interval(days => private.config_int('compliance.suspended_trace_retention_days')));
  end if;
  return old;
end;
$$;

create trigger before_auth_user_deleted_trace
  before delete on auth.users
  for each row execute function private.trace_suspended_deletion();
