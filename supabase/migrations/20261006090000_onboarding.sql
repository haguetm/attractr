-- Phase 2: onboarding (spec §3). Photos, selfie, written answers, referral code
-- capture, server-side location with country, and onboarding completion.

insert into public.app_config (key, value, description, is_public) values
  ('photos.min_count', '2', 'Photos required to finish onboarding (provisoire).', true),
  ('photos.max_count', '6', 'Max photos per profile (provisoire).', true);

-- Step 1 / step 2 split -----------------------------------------------------
-- The birth date is collected on screen 1 and the identity on screen 2.

drop function public.set_my_identity(text, date, public.gender, text);

create function public.set_my_birth_date(p_birth_date date)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  current_birth date;
begin
  select birth_date into current_birth from public.profiles where id = uid;
  if current_birth is not null and current_birth <> p_birth_date then
    raise exception 'birth_date_locked';
  end if;
  update public.profiles set birth_date = p_birth_date where id = uid;
end;
$$;

create function public.set_my_identity(
  p_first_name text,
  p_gender public.gender,
  p_gender_detail text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
begin
  update public.profiles
     set first_name = btrim(p_first_name),
         gender = p_gender,
         gender_detail = nullif(btrim(p_gender_detail), '')
   where id = uid;
end;
$$;

-- Referral code typed at signup. Resolved and rewarded in phase 7; the referrer
-- never sees anything but "inscrit et vérifié" (spec §9).
create table private.signup_referrals (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  code text not null check (code ~ '^[A-Za-z0-9-]{4,32}$'),
  befriend_referrer boolean not null default false,
  created_at timestamptz not null default now()
);

create function public.set_my_referral_code(p_code text, p_befriend_referrer boolean default false)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  clean text := upper(btrim(p_code));
begin
  if clean is null or clean = '' then
    delete from private.signup_referrals where user_id = uid;
    return;
  end if;
  if clean !~ '^[A-Z0-9-]{4,32}$' then
    raise exception 'invalid_referral_code';
  end if;
  if (select status from public.profiles where id = uid) <> 'onboarding' then
    raise exception 'referral_code_only_at_signup';
  end if;
  insert into private.signup_referrals (user_id, code, befriend_referrer)
  values (uid, clean, coalesce(p_befriend_referrer, false))
  on conflict (user_id) do update set code = excluded.code, befriend_referrer = excluded.befriend_referrer;
end;
$$;

-- Written answers: exactly 3, replaced atomically (spec §2) -------------------

create function public.set_my_prompts(p_prompts jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
begin
  if jsonb_typeof(p_prompts) is distinct from 'array' or jsonb_array_length(p_prompts) <> 3 then
    raise exception 'prompts_exactly_three';
  end if;
  if (select count(distinct e ->> 'question_code') from jsonb_array_elements(p_prompts) e) <> 3 then
    raise exception 'prompts_duplicate_question';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_prompts) e
    where not exists (select 1 from public.prompt_questions q where q.code = e ->> 'question_code' and q.active)
  ) then
    raise exception 'unknown_prompt_question';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_prompts) e
    where coalesce(char_length(btrim(e ->> 'answer')), 0) not between 1 and 150
  ) then
    raise exception 'prompt_answer_length';
  end if;

  delete from public.profile_prompts where user_id = uid;
  insert into public.profile_prompts (user_id, position, question_code, answer)
  select uid, e.ord::smallint, e.value ->> 'question_code', btrim(e.value ->> 'answer')
  from jsonb_array_elements(p_prompts) with ordinality as e (value, ord);
end;
$$;

-- Photos ------------------------------------------------------------------------
-- Files live in private Storage buckets under `<user_id>/`. Other users will get
-- short-lived signed URLs through feed/match RPCs (phase 3), never direct access.

create type public.moderation_status as enum ('pending', 'approved', 'rejected');

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('photos', 'photos', false, 10485760, array['image/jpeg', 'image/png', 'image/webp', 'image/heic']),
  ('selfies', 'selfies', false, 10485760, array['image/jpeg', 'image/png', 'image/webp', 'image/heic'])
on conflict (id) do nothing;

create policy photos_insert_own on storage.objects for insert to authenticated
  with check (bucket_id = 'photos' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy photos_select_own on storage.objects for select to authenticated
  using (bucket_id = 'photos' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy photos_delete_own on storage.objects for delete to authenticated
  using (bucket_id = 'photos' and (storage.foldername(name))[1] = (select auth.uid())::text);
-- Selfies: the user uploads, nobody reads them through the API (verification runs server-side).
create policy selfies_insert_own on storage.objects for insert to authenticated
  with check (bucket_id = 'selfies' and (storage.foldername(name))[1] = (select auth.uid())::text);

create table public.photos (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  storage_path text not null unique,
  position smallint not null check (position between 1 and 20),
  moderation_status public.moderation_status not null default 'pending',
  created_at timestamptz not null default now(),
  unique (user_id, position) deferrable initially immediate
);

alter table public.photos enable row level security;
revoke insert, update, delete, truncate on public.photos from authenticated;
create policy photos_select_own_rows on public.photos
  for select to authenticated using (user_id = (select auth.uid()));

create function private.require_own_object(p_bucket text, p_path text, p_user_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if split_part(p_path, '/', 1) <> p_user_id::text or not exists (
    select 1 from storage.objects where bucket_id = p_bucket and name = p_path
  ) then
    raise exception 'storage_object_not_found';
  end if;
end;
$$;

-- Registers an uploaded file as the next photo. Moderation runs in phase 5.
create function public.add_my_photo(p_storage_path text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  n integer;
  new_id uuid;
begin
  perform private.require_own_object('photos', p_storage_path, uid);
  perform 1 from public.profiles where id = uid for update;  -- serialize concurrent adds
  select count(*) into n from public.photos where user_id = uid;
  if n >= private.config_int('photos.max_count') then
    raise exception 'photos_max_reached';
  end if;
  insert into public.photos (user_id, storage_path, position)
  values (uid, p_storage_path, n + 1)
  returning id into new_id;
  return new_id;
end;
$$;

-- Removes the row and returns the path; the app then deletes the Storage file.
create function public.remove_my_photo(p_photo_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  removed public.photos;
begin
  delete from public.photos where id = p_photo_id and user_id = uid returning * into removed;
  if removed.id is null then
    raise exception 'photo_not_found';
  end if;
  update public.photos set position = position - 1
   where user_id = uid and position > removed.position;
  return removed.storage_path;
end;
$$;

-- p_photo_ids lists all the caller's photos in the new order.
create function public.reorder_my_photos(p_photo_ids uuid[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
begin
  if (select array_agg(id order by id) from public.photos where user_id = uid)
     is distinct from (select array_agg(x order by x) from unnest(p_photo_ids) x) then
    raise exception 'photo_order_mismatch';
  end if;
  set constraints public.photos_user_id_position_key deferred;
  update public.photos p set position = o.ord
    from unnest(p_photo_ids) with ordinality as o (id, ord)
   where p.id = o.id and p.user_id = uid;
end;
$$;

-- Selfie --------------------------------------------------------------------------
-- Verification (liveness, age estimate, duplicate face) runs in phase 5 through the
-- SelfieVerificationProvider. Here the submission is recorded and the profile is
-- marked 'pending'.

create table private.selfie_submissions (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  storage_path text not null,
  status public.verification_status not null default 'pending',
  submitted_at timestamptz not null default now(),
  processed_at timestamptz
);

create function public.submit_my_selfie(p_storage_path text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
begin
  perform private.require_own_object('selfies', p_storage_path, uid);
  insert into private.selfie_submissions (user_id, storage_path) values (uid, p_storage_path);
  update public.profiles set verification_status = 'pending'
   where id = uid and verification_status <> 'verified';
end;
$$;

-- Location -------------------------------------------------------------------------
-- Only the update-location Edge Function writes positions: it geocodes the country
-- server-side, so the client cannot pick its own country (Q21).

drop function public.set_my_location(double precision, double precision, public.location_source);

create function public.service_set_location(
  p_user_id uuid,
  p_lat double precision,
  p_lon double precision,
  p_source public.location_source,
  p_country_code text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.profiles
     set location = private.snap_point(p_lat, p_lon),
         location_source = p_source,
         country_code = upper(p_country_code)
   where id = p_user_id;
  if not found then
    raise exception 'profile_not_found';
  end if;
end;
$$;

-- Completion --------------------------------------------------------------------------

create function public.complete_onboarding()
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
  if (select count(*) from public.photos where user_id = uid) < private.config_int('photos.min_count') then
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

-- get_my_profile now also returns photos and the signup referral code.
create or replace function public.get_my_profile()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
begin
  return (
    select jsonb_build_object(
      'id', p.id,
      'status', p.status,
      'first_name', p.first_name,
      'birth_date', p.birth_date,
      'gender', p.gender,
      'gender_detail', p.gender_detail,
      'bio', p.bio,
      'open_to_couples', p.open_to_couples,
      'alcohol_free_icons', p.alcohol_free_icons,
      'verification_status', p.verification_status,
      'country_code', p.country_code,
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
      'sensitive', private.read_sensitive(p.id)
    )
    from public.profiles p where p.id = uid
  );
end;
$$;

do $$
declare
  f text;
begin
  foreach f in array array[
    'public.set_my_birth_date(date)',
    'public.set_my_identity(text, public.gender, text)',
    'public.set_my_referral_code(text, boolean)',
    'public.set_my_prompts(jsonb)',
    'public.add_my_photo(text)',
    'public.remove_my_photo(uuid)',
    'public.reorder_my_photos(uuid[])',
    'public.submit_my_selfie(text)',
    'public.complete_onboarding()'
  ]
  loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end;
$$;

revoke execute on function public.service_set_location(uuid, double precision, double precision, public.location_source, text)
  from public, anon, authenticated;
grant execute on function public.service_set_location(uuid, double precision, double precision, public.location_source, text)
  to service_role;

-- Drink changes during onboarding are all part of the first choice (Q12): no
-- cooldown, no drinks_changed_at, history reason 'initial'. Otherwise unchanged.
create or replace function public.set_my_intent(
  p_situation public.situation,
  p_drinks public.drink[],
  p_structure public.relationship_structure default null,
  p_composition jsonb default null,
  p_open_to_couples boolean default false
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  prof public.profiles;
  sw public.country_config;
  err text;
  old_drinks public.drink[];
  new_drinks public.drink[] := array(select distinct d from unnest(p_drinks) d order by d);
  onboarding boolean;
begin
  perform private.require_sensitive_consent(uid);
  select * into prof from public.profiles where id = uid for update;
  onboarding := prof.status = 'onboarding';
  sw := private.country_switches(prof.country_code);

  err := private.validate_intent(p_situation, p_drinks, p_structure, p_composition,
                                 p_open_to_couples, sw.structure_enabled, sw.composition_enabled);
  if err is not null then
    raise exception '%', err;
  end if;

  select array_agg(drink order by drink) into old_drinks
    from public.profile_drinks where user_id = uid;

  if old_drinks is distinct from new_drinks then
    if onboarding or old_drinks is null then
      insert into private.drink_change_history (user_id, old_drinks, new_drinks, reason)
        values (uid, old_drinks, new_drinks, 'initial');
    else
      if prof.drinks_changed_at is not null
         and prof.drinks_changed_at > now() - make_interval(days => private.config_int('drinks.change_cooldown_days')) then
        raise exception 'drink_change_cooldown';
      end if;
      insert into private.drink_change_history (user_id, old_drinks, new_drinks, reason)
        values (uid, old_drinks, new_drinks, 'user');
      update public.profiles set drinks_changed_at = now() where id = uid;
    end if;
    delete from public.profile_drinks where user_id = uid;
    insert into public.profile_drinks (user_id, drink) select uid, unnest(new_drinks);
  end if;

  update public.profiles set open_to_couples = p_open_to_couples where id = uid;

  perform private.write_sensitive(uid, jsonb_build_object(
    'situation', p_situation,
    'structure', p_structure,
    'composition', case when p_composition = 'null'::jsonb then null else p_composition end
  ));
end;
$$;
