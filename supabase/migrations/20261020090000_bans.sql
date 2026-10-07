-- Bans (DECISIONS, "Bannissement"). A banned account is closed and erased; its phone,
-- email (Gmail aliases folded) and Google / Apple accounts cannot sign up again for
-- compliance.ban_retention_days, and its face sends a new selfie to review. Only HMACs
-- are kept (pepper in Vault), never the identifiers. The same traces now cover every
-- identifier for closed minor accounts and accounts deleted while suspended.

insert into public.app_config (key, value, description, is_public) values
  ('compliance.ban_retention_days', '1095',
   'How long a banned account''s phone, email and Google / Apple accounts stay refused (provisoire, legal validation pending).', false);

alter table private.blocked_identities
  add column email_hash text,
  add column identity_hash text;

create index blocked_identities_email_idx on private.blocked_identities (email_hash);
create index blocked_identities_identity_idx on private.blocked_identities (identity_hash);

-- A closed account may never have finished its onboarding (ban or minor closure right
-- after signup): only open statuses require a complete identity.
alter table public.profiles drop constraint profiles_complete_unless_onboarding;
alter table public.profiles add constraint profiles_complete_unless_onboarding check (
  status in ('onboarding', 'closed')
  or (first_name is not null and birth_date is not null and gender is not null)
);

-- Hashes -----------------------------------------------------------------------------------

-- Lower case, "+tag" dropped; Gmail ignores dots and has two domains.
create function private.normalize_email(p_email text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  e text := lower(btrim(coalesce(p_email, '')));
  local_part text := split_part(e, '@', 1);
  domain text := split_part(e, '@', 2);
begin
  if local_part = '' or domain = '' then
    return null;
  end if;
  local_part := split_part(local_part, '+', 1);
  if domain in ('gmail.com', 'googlemail.com') then
    local_part := replace(local_part, '.', '');
    domain := 'gmail.com';
  end if;
  return local_part || '@' || domain;
end;
$$;

create function private.email_hash(p_email text)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select encode(extensions.hmac(private.normalize_email(p_email),
                (select decrypted_secret from vault.decrypted_secrets where name = 'phone_hash_pepper'), 'sha256'), 'hex');
$$;

-- Google / Apple account: the provider's stable subject id.
create function private.identity_hash(p_provider text, p_subject text)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select encode(extensions.hmac(p_provider || ':' || p_subject,
                (select decrypted_secret from vault.decrypted_secrets where name = 'phone_hash_pepper'), 'sha256'), 'hex');
$$;

-- Traces -----------------------------------------------------------------------------------

-- Records every identifier of an account: phone (verified or declared), email, face, and
-- one row per Google / Apple account.
create function private.record_identity_trace(p_user_id uuid, p_reason text, p_retention interval)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_phone text;
  v_email text;
  v_face text;
begin
  select coalesce(private.phone_hash(u.phone), (select d.phone_hmac from private.phone_digests d where d.user_id = u.id)),
         private.email_hash(u.email)
    into v_phone, v_email
  from auth.users u where u.id = p_user_id;
  v_face := (select f.face_id from private.face_templates f where f.user_id = p_user_id);
  if v_phone is not null or v_email is not null or v_face is not null then
    insert into private.blocked_identities (phone_hash, email_hash, face_id, reason, expires_at)
    values (v_phone, v_email, v_face, p_reason, now() + p_retention);
  end if;
  insert into private.blocked_identities (identity_hash, reason, expires_at)
  select private.identity_hash(i.provider, i.provider_id), p_reason, now() + p_retention
  from auth.identities i
  where i.user_id = p_user_id and i.provider not in ('email', 'phone');
end;
$$;

-- Hard refusal at signup: closed minor accounts and bans (not plain suspensions).
create function private.is_identity_refused(p_phone_hash text, p_email_hash text, p_identity_hash text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from private.blocked_identities b
    where b.reason in ('minor', 'banned') and b.expires_at > now()
      and (b.phone_hash = p_phone_hash or b.email_hash = p_email_hash or b.identity_hash = p_identity_hash)
  );
$$;

-- Any trace (refusal or suspension) matching the account: its selfie goes to review.
create function private.matches_identity_trace(p_user_id uuid, p_face_id text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from private.blocked_identities b
    where b.expires_at > now()
      and (b.face_id = p_face_id
           or b.phone_hash = (select d.phone_hmac from private.phone_digests d where d.user_id = p_user_id)
           or b.email_hash = (select private.email_hash(u.email) from auth.users u where u.id = p_user_id)
           or b.identity_hash in (select private.identity_hash(i.provider, i.provider_id) from auth.identities i
                                  where i.user_id = p_user_id and i.provider not in ('email', 'phone')))
  );
$$;

-- Signup checks ----------------------------------------------------------------------------

drop trigger before_auth_user_created_check_phone on auth.users;
drop function private.check_blocked_phone();

-- New account, or a phone / email added later (SMS verification, email change).
create function private.check_refused_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (tg_op = 'INSERT' or new.phone is distinct from old.phone or new.email is distinct from old.email)
     and private.is_identity_refused(
           case when new.phone is not null then private.phone_hash(new.phone) end,
           case when new.email is not null then private.email_hash(new.email) end,
           null) then
    raise exception 'identity_blocked';
  end if;
  return new;
end;
$$;

create trigger before_auth_user_check_refused
  before insert or update of phone, email on auth.users
  for each row execute function private.check_refused_user();

-- Signing up or linking with Google / Apple.
create function private.check_refused_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.provider not in ('email', 'phone')
     and private.is_identity_refused(null, null, private.identity_hash(new.provider, new.provider_id)) then
    raise exception 'identity_blocked';
  end if;
  return new;
end;
$$;

create trigger before_auth_identity_check_refused
  before insert on auth.identities
  for each row execute function private.check_refused_identity();

create or replace function public.set_my_phone(p_phone text)
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
  if private.is_identity_refused(private.phone_hash(digits), null, null) then
    raise exception 'identity_blocked';
  end if;
  insert into private.phone_digests (user_id, digest, phone_hmac)
  values (uid, encode(extensions.digest(digits, 'sha256'), 'hex'), private.phone_hash(digits))
  on conflict (user_id) do update set digest = excluded.digest, phone_hmac = excluded.phone_hmac;
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
  elsif private.matches_identity_trace(s.user_id, p_face_id) then
    -- Face, phone, email or Google / Apple account of a closed, banned or deleted-while-
    -- suspended account.
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

-- Existing traces now record every identifier ------------------------------------------------

create or replace function private.close_minor_account(p_user_id uuid, p_actor text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.record_identity_trace(p_user_id, 'minor',
    make_interval(days => private.config_int('compliance.minor_trace_retention_days')));
  update public.profiles set status = 'closed' where id = p_user_id;
  update public.matches set status = 'unmatched', ended_at = now()
   where status in ('active', 'on_hold') and p_user_id in (user_a, user_b);
  insert into private.pending_deletions (user_id, reason) values (p_user_id, 'minor')
  on conflict (user_id) do nothing;
  perform private.log_access(p_actor, p_user_id, 'account', 'closed: minor');
end;
$$;

create or replace function private.trace_suspended_deletion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (select 1 from public.profiles where id = old.id and status = 'suspended') then
    perform private.record_identity_trace(old.id, 'suspended',
      make_interval(days => private.config_int('compliance.suspended_trace_retention_days')));
  end if;
  return old;
end;
$$;

-- Ban --------------------------------------------------------------------------------------

-- Moderator: closes the account, erases it (process-deletions) and refuses its phone,
-- email and Google / Apple accounts for compliance.ban_retention_days.
create function private.mod_ban_account(p_actor text, p_user_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if char_length(btrim(coalesce(p_reason, ''))) < 5 then
    raise exception 'invalid_request';
  end if;
  if not exists (select 1 from public.profiles where id = p_user_id and not is_couple and status <> 'closed') then
    raise exception 'profile_unavailable';
  end if;
  perform private.record_identity_trace(p_user_id, 'banned',
    make_interval(days => private.config_int('compliance.ban_retention_days')));
  update public.profiles set status = 'closed' where id = p_user_id;
  update public.matches set status = 'unmatched', ended_at = now()
   where status in ('active', 'on_hold') and p_user_id in (user_a, user_b);
  insert into private.pending_deletions (user_id, reason) values (p_user_id, 'moderation')
  on conflict (user_id) do nothing;
  perform private.log_access(p_actor, p_user_id, 'account', 'banned: ' || btrim(p_reason));
end;
$$;
