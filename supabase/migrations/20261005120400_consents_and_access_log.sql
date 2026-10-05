-- Consents (spec §12) and internal access log.

-- One row per published version of a legal text. The text itself is versioned in
-- the repository (docs/legal, app i18n); content_sha256 ties a consent to it.
create table public.consent_texts (
  type public.consent_type not null,
  version integer not null check (version > 0),
  content_sha256 text not null,
  published_at timestamptz not null default now(),
  primary key (type, version)
);

alter table public.consent_texts enable row level security;
revoke insert, update, delete, truncate on public.consent_texts from authenticated;
create policy consent_texts_read on public.consent_texts
  for select to authenticated using (true);

-- Placeholder hashes until the legal texts are written (see docs/ARCHITECTURE.md legal checklist).
insert into public.consent_texts (type, version, content_sha256) values
  ('terms', 1, 'draft-v1'),
  ('privacy', 1, 'draft-v1'),
  ('sensitive_data', 1, 'draft-v1'),
  ('ai_photo_analysis', 1, 'draft-v1');

create table public.consents (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  type public.consent_type not null,
  version integer not null,
  granted_at timestamptz not null default now(),
  withdrawn_at timestamptz,
  foreign key (type, version) references public.consent_texts (type, version),
  check (withdrawn_at is null or withdrawn_at >= granted_at)
);

-- At most one active consent per user and type.
create unique index consents_one_active_idx on public.consents (user_id, type) where withdrawn_at is null;

alter table public.consents enable row level security;
revoke insert, update, delete, truncate on public.consents from authenticated;
create policy consents_select_own on public.consents
  for select to authenticated using (user_id = (select auth.uid()));

create function private.has_consent(p_user_id uuid, p_type public.consent_type)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.consents
    where user_id = p_user_id and type = p_type and withdrawn_at is null
  );
$$;

create function private.require_user()
returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'not_authenticated';
  end if;
  return uid;
end;
$$;

-- Grants the given version; a previous active consent of the same type is superseded.
create function public.grant_consent(p_type public.consent_type, p_version integer)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
begin
  if not exists (select 1 from public.consent_texts where type = p_type and version = p_version) then
    raise exception 'unknown_consent_version';
  end if;
  if exists (
    select 1 from public.consents
    where user_id = uid and type = p_type and version = p_version and withdrawn_at is null
  ) then
    return;
  end if;
  update public.consents set withdrawn_at = now()
    where user_id = uid and type = p_type and withdrawn_at is null;
  insert into public.consents (user_id, type, version) values (uid, p_type, p_version);
end;
$$;

-- One-click withdrawal. Withdrawing a consent stops the matching processing at once:
--   sensitive_data    -> encrypted sensitive fields are deleted (the profile can no
--                        longer be matched until consent is given again).
--   ai_photo_analysis -> cached analyses are deleted (table added in phase 10).
-- terms / privacy cannot be withdrawn here: the user deletes the account instead.
create function public.withdraw_consent(p_type public.consent_type)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
begin
  if p_type in ('terms', 'privacy') then
    raise exception 'consent_requires_account_deletion';
  end if;
  update public.consents set withdrawn_at = now()
    where user_id = uid and type = p_type and withdrawn_at is null;
  if p_type = 'sensitive_data' then
    delete from private.profile_sensitive where user_id = uid;
  end if;
end;
$$;

revoke execute on function public.grant_consent(public.consent_type, integer) from public, anon;
revoke execute on function public.withdraw_consent(public.consent_type) from public, anon;
grant execute on function public.grant_consent(public.consent_type, integer) to authenticated;
grant execute on function public.withdraw_consent(public.consent_type) to authenticated;

-- Internal access log (spec §12) --------------------------------------------
-- Every read of another person's private data by staff or back-office tooling
-- goes through a function that writes here. No FK on subject: entries outlive
-- account deletion for the retention period in docs/DATA_RETENTION.md.

create table private.access_log (
  id bigint generated always as identity primary key,
  accessed_at timestamptz not null default now(),
  actor text not null,
  subject_user_id uuid,
  resource text not null,
  reason text not null check (char_length(btrim(reason)) >= 5)
);

create index access_log_subject_idx on private.access_log (subject_user_id, accessed_at desc);

create function private.log_access(p_actor text, p_subject uuid, p_resource text, p_reason text)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into private.access_log (actor, subject_user_id, resource, reason)
  values (p_actor, p_subject, p_resource, p_reason);
$$;

-- Back-office read of a user's sensitive fields (moderation). Always logged.
create function private.admin_read_sensitive(p_actor text, p_subject uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.log_access(p_actor, p_subject, 'profile_sensitive', p_reason);
  return private.read_sensitive(p_subject);
end;
$$;
