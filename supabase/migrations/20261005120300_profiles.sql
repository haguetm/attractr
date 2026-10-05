-- Profiles, drinks, written answers and encrypted sensitive fields.

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  status public.profile_status not null default 'onboarding',
  first_name text check (char_length(btrim(first_name)) between 1 and 40),
  birth_date date check (birth_date >= date '1900-01-01'),
  gender public.gender,
  -- Free precision shown on the profile, never used for matching (DECISIONS Q5).
  gender_detail text check (char_length(gender_detail) <= 40),
  bio text,
  open_to_couples boolean not null default false,
  alcohol_free_icons boolean not null default false,
  verification_status public.verification_status not null default 'unverified',
  verified_at timestamptz,
  -- Snapped to a ~1 km grid by private.snap_point. Exact coordinates are never stored.
  location extensions.geography(Point, 4326),
  location_source public.location_source,
  country_code text check (country_code ~ '^[A-Z]{2}$'),
  -- Last user-initiated drink change; null until the first change after onboarding (Q12).
  drinks_changed_at timestamptz,
  last_active_at timestamptz not null default now(),
  is_seed boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_complete_unless_onboarding check (
    status = 'onboarding'
    or (first_name is not null and birth_date is not null and gender is not null)
  )
);

create index profiles_location_idx on public.profiles using gist (location);

comment on column public.profiles.location is
  'Snapped to ~1 km (private.snap_point). Never store or expose exact coordinates.';

-- A user reads and edits only their own row. Other profiles are only reachable
-- through dedicated RPCs (feed, match, outing card...) returning public columns.
alter table public.profiles enable row level security;
revoke insert, update, delete, truncate on public.profiles from authenticated;
grant update (first_name, gender_detail, bio, alcohol_free_icons) on public.profiles to authenticated;

create policy profiles_select_own on public.profiles
  for select to authenticated using (id = (select auth.uid()));
create policy profiles_update_own on public.profiles
  for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- SECURITY DEFINER: runs on direct updates by `authenticated`, which cannot reach `private`.
create function private.profiles_before_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.birth_date is not null and new.birth_date > (current_date - interval '18 years')::date then
    raise exception 'underage';
  end if;
  if new.bio is not null and char_length(new.bio) > private.config_int('profile.bio_max_length') then
    raise exception 'bio_too_long';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

create trigger profiles_before_write
  before insert or update on public.profiles
  for each row execute function private.profiles_before_write();

-- Every auth user gets a profile row in 'onboarding' status.
create function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id) values (new.id) on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

-- Drinks -------------------------------------------------------------------

create table public.profile_drinks (
  user_id uuid not null references public.profiles (id) on delete cascade,
  drink public.drink not null references public.drinks (code),
  created_at timestamptz not null default now(),
  primary key (user_id, drink)
);

alter table public.profile_drinks enable row level security;
revoke insert, update, delete, truncate on public.profile_drinks from authenticated;
create policy profile_drinks_select_own on public.profile_drinks
  for select to authenticated using (user_id = (select auth.uid()));

-- Private history, reserved to moderation (spec §1).
create table private.drink_change_history (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  old_drinks public.drink[],
  new_drinks public.drink[] not null,
  reason text not null check (reason in ('initial', 'user', 'couple_closed', 'seed')),
  changed_at timestamptz not null default now()
);

create index drink_change_history_user_idx on private.drink_change_history (user_id, changed_at desc);

-- Written answers (spec §2: 3 questions, 150 characters each) ----------------

create table public.profile_prompts (
  user_id uuid not null references public.profiles (id) on delete cascade,
  position smallint not null check (position between 1 and 3),
  question_code text not null references public.prompt_questions (code),
  answer text not null check (char_length(btrim(answer)) between 1 and 150),
  updated_at timestamptz not null default now(),
  primary key (user_id, position),
  unique (user_id, question_code)
);

alter table public.profile_prompts enable row level security;
create policy profile_prompts_select_own on public.profile_prompts
  for select to authenticated using (user_id = (select auth.uid()));
create policy profile_prompts_insert_own on public.profile_prompts
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy profile_prompts_update_own on public.profile_prompts
  for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy profile_prompts_delete_own on public.profile_prompts
  for delete to authenticated using (user_id = (select auth.uid()));

-- Sensitive fields ---------------------------------------------------------
--
-- seeking_genders, friend_genders, orientation, situation, structure and
-- composition are stored as one pgcrypto-encrypted JSON document, in a table
-- no API role can reach. The key lives in Supabase Vault. Only SECURITY DEFINER
-- functions decrypt. Rationale: docs/ARCHITECTURE.md, principle 3.
--
-- Payload shape:
--   { "seeking_genders": gender[], "friend_genders": gender[],
--     "orientation": text|null, "orientation_visible": bool,
--     "situation": situation, "structure": relationship_structure|null,
--     "composition": {"kinds": text[], "three_plus_genders": gender[]|null}|null }

create table private.profile_sensitive (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  payload bytea not null,
  updated_at timestamptz not null default now()
);

-- The key is generated inside the database: it never appears in the repository.
do $$
begin
  if not exists (select 1 from vault.secrets where name = 'profile_sensitive_key') then
    perform vault.create_secret(
      encode(extensions.gen_random_bytes(32), 'base64'),
      'profile_sensitive_key',
      'pgcrypto key for private.profile_sensitive. Never export.'
    );
  end if;
end;
$$;

create function private.sensitive_key()
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  k text;
begin
  select decrypted_secret into k from vault.decrypted_secrets where name = 'profile_sensitive_key';
  if k is null then
    raise exception 'sensitive_key_missing';
  end if;
  return k;
end;
$$;

create function private.read_sensitive(p_user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select extensions.pgp_sym_decrypt(s.payload, private.sensitive_key())::jsonb
     from private.profile_sensitive s where s.user_id = p_user_id),
    '{}'::jsonb
  );
$$;

-- Merges p_patch into the stored document. A key set to JSON null is removed.
create function private.write_sensitive(p_user_id uuid, p_patch jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  merged jsonb := jsonb_strip_nulls(private.read_sensitive(p_user_id) || p_patch);
begin
  insert into private.profile_sensitive (user_id, payload, updated_at)
  values (
    p_user_id,
    extensions.pgp_sym_encrypt(merged::text, private.sensitive_key(), 'cipher-algo=aes256'),
    now()
  )
  on conflict (user_id) do update
    set payload = excluded.payload, updated_at = excluded.updated_at;
end;
$$;

-- Location -----------------------------------------------------------------

-- Snaps a position to a ~1 km grid (0.009° of latitude, longitude step widened
-- with latitude so cells stay ~1 km wide). Used before anything is stored.
create function private.snap_point(p_lat double precision, p_lon double precision)
returns extensions.geography
language plpgsql
immutable
set search_path = ''
as $$
declare
  step_lat constant double precision := 0.009;
  lat double precision;
  lon double precision;
  step_lon double precision;
begin
  if p_lat is null or p_lon is null or p_lat not between -90 and 90 or p_lon not between -180 and 180 then
    raise exception 'invalid_coordinates';
  end if;
  lat := least(greatest(round(p_lat / step_lat) * step_lat, -90), 90);
  step_lon := step_lat / greatest(cos(radians(lat)), 0.01);
  lon := least(greatest(round(p_lon / step_lon) * step_lon, -180), 180);
  return extensions.st_setsrid(extensions.st_makepoint(lon, lat), 4326)::extensions.geography;
end;
$$;
