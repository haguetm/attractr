-- Phase 3: discovery (spec §4). Search preferences, compatibility, the feed RPC,
-- "pass", exclusions (seen, blocked, reported) and photo access for feed viewers.

insert into public.app_config (key, value, description, is_public) values
  ('feed.default_radius_km', '25', 'Default search radius in km (provisoire).', true),
  ('feed.max_radius_km', '300', 'Max search radius, also the auto-widening ceiling (provisoire).', true),
  ('feed.min_results', '10', 'Below this many profiles the radius widens automatically (provisoire).', false),
  ('feed.page_size', '20', 'Profiles returned per feed call.', false);

-- Administrative areas (for "département" and "région" search) -----------------
-- Set server-side by the geocoder, like the country.

alter table public.profiles
  add column department_code text check (department_code ~ '^[0-9][0-9AB][0-9]?$'),
  add column region_code text check (region_code ~ '^[0-9]{2}$');

drop function public.service_set_location(uuid, double precision, double precision, public.location_source, text);

create function public.service_set_location(
  p_user_id uuid,
  p_lat double precision,
  p_lon double precision,
  p_source public.location_source,
  p_country_code text,
  p_department_code text default null,
  p_region_code text default null
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
         country_code = upper(p_country_code),
         department_code = upper(p_department_code),
         region_code = p_region_code
   where id = p_user_id;
  if not found then
    raise exception 'profile_not_found';
  end if;
end;
$$;

revoke execute on function public.service_set_location(uuid, double precision, double precision, public.location_source, text, text, text)
  from public, anon, authenticated;
grant execute on function public.service_set_location(uuid, double precision, double precision, public.location_source, text, text, text)
  to service_role;

-- Search preferences (free filters: distance or area, age, drink) ----------------

create type public.search_mode as enum ('radius', 'department', 'region');

create table public.search_preferences (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  mode public.search_mode not null default 'radius',
  radius_km integer check (radius_km between 1 and 1000),  -- null = feed.default_radius_km
  age_min smallint not null default 18 check (age_min >= 18),
  age_max smallint not null default 99 check (age_max <= 99 and age_max >= age_min),
  drinks public.drink[],                                    -- null = every compatible drink
  updated_at timestamptz not null default now()
);

alter table public.search_preferences enable row level security;
revoke insert, update, delete, truncate on public.search_preferences from authenticated;
create policy search_preferences_select_own on public.search_preferences
  for select to authenticated using (user_id = (select auth.uid()));

-- Preferences with defaults applied (no row = defaults).
create function private.search_prefs(p_user_id uuid)
returns public.search_preferences
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  prefs public.search_preferences;
begin
  select * into prefs from public.search_preferences where user_id = p_user_id;
  if not found then
    prefs.user_id := p_user_id;
    prefs.mode := 'radius';
    prefs.age_min := 18;
    prefs.age_max := 99;
  end if;
  prefs.radius_km := coalesce(prefs.radius_km, private.config_int('feed.default_radius_km'));
  return prefs;
end;
$$;

create function public.set_my_search_preferences(
  p_mode public.search_mode,
  p_radius_km integer,
  p_age_min integer,
  p_age_max integer,
  p_drinks public.drink[] default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  p public.profiles;
begin
  select * into p from public.profiles where id = uid;
  if p_mode = 'radius' and (p_radius_km is null or p_radius_km < 1 or p_radius_km > private.config_int('feed.max_radius_km')) then
    raise exception 'invalid_radius';
  end if;
  if (p_mode = 'department' and p.department_code is null) or (p_mode = 'region' and p.region_code is null) then
    raise exception 'area_unknown';
  end if;
  if p_age_min is null or p_age_max is null or p_age_min < 18 or p_age_max > 99 or p_age_min > p_age_max then
    raise exception 'invalid_age_range';
  end if;
  if p_drinks is not null and cardinality(p_drinks) = 0 then
    raise exception 'invalid_drink_filter';
  end if;
  insert into public.search_preferences (user_id, mode, radius_km, age_min, age_max, drinks, updated_at)
  values (uid, p_mode, p_radius_km, p_age_min, p_age_max, p_drinks, now())
  on conflict (user_id) do update
    set mode = excluded.mode, radius_km = excluded.radius_km, age_min = excluded.age_min,
        age_max = excluded.age_max, drinks = excluded.drinks, updated_at = excluded.updated_at;
end;
$$;

-- Swipes (pass now, like in phase 4), blocks and reports ---------------------------

create type public.swipe_action as enum ('like', 'pass');

create table public.swipes (
  id bigint generated always as identity primary key,
  actor_id uuid not null references public.profiles (id) on delete cascade,
  target_id uuid not null references public.profiles (id) on delete cascade,
  action public.swipe_action not null,
  created_at timestamptz not null default now(),
  unique (actor_id, target_id),
  check (actor_id <> target_id)
);

create index swipes_target_idx on public.swipes (target_id);

alter table public.swipes enable row level security;
revoke insert, update, delete, truncate on public.swipes from authenticated;
create policy swipes_select_own on public.swipes
  for select to authenticated using (actor_id = (select auth.uid()));

-- Minimal block/report tables so the feed can exclude them now; the actions,
-- moderation queue and UI come in phase 5.
create table public.blocks (
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

create index blocks_blocked_idx on public.blocks (blocked_id);

alter table public.blocks enable row level security;
revoke insert, update, delete, truncate on public.blocks from authenticated;
create policy blocks_select_own on public.blocks
  for select to authenticated using (blocker_id = (select auth.uid()));

create table public.reports (
  id bigint generated always as identity primary key,
  reporter_id uuid not null references public.profiles (id) on delete cascade,
  reported_id uuid not null references public.profiles (id) on delete cascade,
  reason text not null,
  created_at timestamptz not null default now(),
  check (reporter_id <> reported_id)
);

create index reports_pair_idx on public.reports (reporter_id, reported_id);

alter table public.reports enable row level security;
revoke insert, update, delete, truncate on public.reports from authenticated;
create policy reports_select_own on public.reports
  for select to authenticated using (reporter_id = (select auth.uid()));

-- "Passer": the profile leaves the feed for feed.pass_recycle_days (Q7). A pass
-- never overrides an existing like.
create function public.pass_profile(p_target_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
begin
  if p_target_id = uid then
    raise exception 'cannot_swipe_self';
  end if;
  insert into public.swipes (actor_id, target_id, action) values (uid, p_target_id, 'pass')
  on conflict (actor_id, target_id) do update
    set created_at = now()
    where public.swipes.action = 'pass';
end;
$$;

-- Feed impressions and photo access -------------------------------------------------
-- A profile's photos are readable by someone the feed served it to in the last 24 h
-- (and, from phase 4, by matches). Impressions also feed profile views statistics.

create table private.feed_impressions (
  viewer_id uuid not null references public.profiles (id) on delete cascade,
  target_id uuid not null references public.profiles (id) on delete cascade,
  served_at timestamptz not null default now(),
  primary key (viewer_id, target_id)
);

create index feed_impressions_target_idx on private.feed_impressions (target_id, served_at desc);

-- In public so storage policies (evaluated as the caller) can use it; it only
-- answers about the caller's own access.
create function public.can_view_photos_of(p_owner text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_owner = (select auth.uid())::text
      or exists (
        select 1 from private.feed_impressions i
        where i.viewer_id = (select auth.uid())
          and i.target_id::text = p_owner
          and i.served_at > now() - interval '24 hours'
      );
$$;

revoke execute on function public.can_view_photos_of(text) from public, anon;
grant execute on function public.can_view_photos_of(text) to authenticated;

create policy photos_select_served on storage.objects for select to authenticated
  using (bucket_id = 'photos' and public.can_view_photos_of((storage.foldername(name))[1]));

-- Compatibility (spec §1-2, DECISIONS Q1, Q2, Q4). Mirror: packages/shared/src/compatibility.ts

create function private.jsonb_genders(p jsonb)
returns public.gender[]
language sql
immutable
set search_path = ''
as $$
  select coalesce(array_agg(x::public.gender), '{}')
  from jsonb_array_elements_text(case when jsonb_typeof(p) = 'array' then p else '[]'::jsonb end) x;
$$;

-- Genders a polyamory composition asks for; null when it sets no constraint.
create function private.composition_genders(p jsonb)
returns public.gender[]
language sql
immutable
set search_path = ''
as $$
  select case
    when p is null or jsonb_typeof(p) <> 'object' or jsonb_typeof(p -> 'kinds') <> 'array'
         or jsonb_array_length(p -> 'kinds') = 0 then null
    else (
      select array_agg(distinct g order by g)
      from jsonb_array_elements_text(p -> 'kinds') k
      cross join lateral unnest(case k
        when 'one_woman' then array['woman']::public.gender[]
        when 'two_women' then array['woman']::public.gender[]
        when 'one_man' then array['man']::public.gender[]
        when 'two_men' then array['man']::public.gender[]
        when 'woman_and_man' then array['woman', 'man']::public.gender[]
        when 'one_any' then enum_range(null::public.gender)
        when 'three_plus' then coalesce(nullif(private.jsonb_genders(p -> 'three_plus_genders'), '{}'),
                                        enum_range(null::public.gender))
        else '{}'::public.gender[]
      end) g
    )
  end;
$$;

-- Candidate drinks through which viewer and candidate match ('{}' = not compatible).
-- p_*_s are decrypted sensitive documents (see private.profile_sensitive).
create function private.match_drinks(
  p_v_gender public.gender, p_v_drinks public.drink[], p_v_s jsonb,
  p_c_gender public.gender, p_c_drinks public.drink[], p_c_s jsonb
)
returns public.drink[]
language plpgsql
stable
set search_path = ''
as $$
declare
  all_genders constant public.gender[] := enum_range(null::public.gender);
  v_seek public.gender[] := private.jsonb_genders(p_v_s -> 'seeking_genders');
  c_seek public.gender[] := private.jsonb_genders(p_c_s -> 'seeking_genders');
  v_friends public.gender[] := coalesce(nullif(private.jsonb_genders(p_v_s -> 'friend_genders'), '{}'), all_genders);
  c_friends public.gender[] := coalesce(nullif(private.jsonb_genders(p_c_s -> 'friend_genders'), '{}'), all_genders);
  v_struct public.relationship_structure := (p_v_s ->> 'structure')::public.relationship_structure;
  c_struct public.relationship_structure := (p_c_s ->> 'structure')::public.relationship_structure;
  v_comp public.gender[] := private.composition_genders(p_v_s -> 'composition');
  c_comp public.gender[] := private.composition_genders(p_c_s -> 'composition');
  result public.drink[];
begin
  select coalesce(array_agg(distinct dc order by dc), '{}') into result
  from unnest(p_v_drinks) dv
  cross join unnest(p_c_drinks) dc
  join public.drink_compatibility m on m.drink_a = dv and m.drink_b = dc and m.compatible
  where case
    when dv = 'beer' and dc = 'beer' then
      p_v_gender = any (c_friends) and p_c_gender = any (v_friends)
    else
      p_c_gender = any (v_seek) and p_v_gender = any (c_seek)
      and (v_struct is null or c_struct is null or exists (
            select 1 from public.structure_compatibility sc
            where sc.structure_a = v_struct and sc.structure_b = c_struct and sc.compatible))
      and (v_comp is null or p_c_gender = any (v_comp))
      and (c_comp is null or p_v_gender = any (c_comp))
  end;
  return result;
end;
$$;

create function private.age_of(p_birth_date date)
returns integer
language sql
stable
set search_path = ''
as $$
  select extract(year from age(current_date, p_birth_date))::integer;
$$;

-- Public distances are ranges only (spec §4). Mirror: distanceBucket in shared.
create function private.distance_bucket(p_meters double precision)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_meters < 5000 then 'lt5'
    when p_meters < 10000 then 'lt10'
    when p_meters < 25000 then 'lt25'
    when p_meters < 50000 then 'lt50'
    when p_meters < 100000 then 'lt100'
    else 'gte100'
  end;
$$;

-- Feed -------------------------------------------------------------------------------
-- Filter order (spec §4): distance/area, then cheap exclusions, then decryption and
-- compatibility (genders, drinks, structure, composition) on the remaining rows only.
-- p_reciprocal: also respect each candidate's own area and age range (Q6); off while
-- the radius is being widened automatically.

create function private.feed_candidates(
  p_viewer_id uuid,
  p_radius_km integer,
  p_reciprocal boolean,
  p_limit integer
)
returns table (candidate_id uuid, distance_m double precision, matched_drinks public.drink[])
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v public.profiles;
  v_s jsonb := private.read_sensitive(p_viewer_id);
  v_drinks public.drink[];
  v_age integer;
  prefs public.search_preferences := private.search_prefs(p_viewer_id);
  default_radius integer := private.config_int('feed.default_radius_km');
  recycle_days integer := private.config_int('feed.pass_recycle_days');
  active_hours integer := private.config_int('activity.badge_window_hours');
begin
  select * into v from public.profiles where id = p_viewer_id;
  v_age := private.age_of(v.birth_date);
  select array_agg(drink order by drink) into v_drinks from public.profile_drinks where user_id = p_viewer_id;

  return query
  with base as materialized (
    select p.id, p.gender, p.last_active_at,
           extensions.st_distance(p.location, v.location) as dist,
           (select array_agg(d.drink order by d.drink) from public.profile_drinks d where d.user_id = p.id) as drinks
    from public.profiles p
    left join public.search_preferences sp on sp.user_id = p.id
    where p.id <> p_viewer_id
      and p.status = 'active'
      and p.location is not null
      and p.verification_status <> 'rejected'
      and case prefs.mode
            when 'radius' then extensions.st_dwithin(p.location, v.location, p_radius_km * 1000.0)
            when 'department' then p.department_code = v.department_code
            else p.region_code = v.region_code
          end
      and private.age_of(p.birth_date) between prefs.age_min and prefs.age_max
      and (not p_reciprocal or (
            case coalesce(sp.mode, 'radius')
              when 'radius' then extensions.st_dwithin(p.location, v.location, coalesce(sp.radius_km, default_radius) * 1000.0)
              when 'department' then p.department_code = v.department_code
              else p.region_code = v.region_code
            end
            and v_age between coalesce(sp.age_min, 18) and coalesce(sp.age_max, 99)))
      and not exists (
            select 1 from public.swipes s
            where s.actor_id = p_viewer_id and s.target_id = p.id
              and (s.action = 'like' or s.created_at > now() - make_interval(days => recycle_days)))
      and not exists (
            select 1 from public.blocks b
            where (b.blocker_id = p_viewer_id and b.blocked_id = p.id)
               or (b.blocker_id = p.id and b.blocked_id = p_viewer_id))
      and not exists (
            select 1 from public.reports r where r.reporter_id = p_viewer_id and r.reported_id = p.id)
      and exists (select 1 from private.profile_sensitive ps where ps.user_id = p.id)
  ),
  scored as (
    select b.id, b.dist, b.last_active_at,
           private.match_drinks(v.gender, v_drinks, v_s, b.gender, b.drinks, private.read_sensitive(b.id)) as matched
    from base b
  )
  select s.id, s.dist, s.matched
  from scored s
  where cardinality(s.matched) > 0
    and (prefs.drinks is null or s.matched && prefs.drinks)
  order by (s.last_active_at > now() - make_interval(hours => active_hours)) desc, s.dist, s.id
  limit p_limit;
end;
$$;

-- What a viewer sees of a candidate: public fields only, distance as a range.
create function private.profile_card(p_candidate_id uuid, p_distance_m double precision, p_matched public.drink[])
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
    'recently_active', p.last_active_at > now() - make_interval(hours => private.config_int('activity.badge_window_hours')),
    'distance', private.distance_bucket(p_distance_m),
    'drinks', coalesce((select jsonb_agg(d.drink order by d.drink) from public.profile_drinks d where d.user_id = p.id), '[]'::jsonb),
    'matched_drinks', to_jsonb(p_matched),
    'orientation', case
        when (s ->> 'orientation_visible')::boolean and (private.country_switches(p.country_code)).orientation_enabled
        then s ->> 'orientation' end,
    'prompts', coalesce((select jsonb_agg(jsonb_build_object('question_code', q.question_code, 'answer', q.answer) order by q.position)
                         from public.profile_prompts q where q.user_id = p.id), '[]'::jsonb),
    -- Until photo moderation exists (phase 5), only rejected photos are hidden.
    'photos', coalesce((select jsonb_agg(jsonb_build_object('id', ph.id, 'storage_path', ph.storage_path) order by ph.position)
                        from public.photos ph where ph.user_id = p.id and ph.moderation_status <> 'rejected'), '[]'::jsonb)
  )
  from public.profiles p
  cross join lateral (select private.read_sensitive(p.id) as s) sens
  where p.id = p_candidate_id;
$$;

-- The feed. Widens the radius automatically (doubling, up to feed.max_radius_km)
-- when fewer than feed.min_results profiles are found (spec §4).
create function public.get_feed(p_limit integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  v public.profiles;
  prefs public.search_preferences;
  page integer := least(coalesce(p_limit, private.config_int('feed.page_size')), 50);
  min_results integer := private.config_int('feed.min_results');
  max_radius integer := private.config_int('feed.max_radius_km');
  radius integer;
  widened boolean := false;
  found_count integer;
  cards jsonb;
begin
  select * into v from public.profiles where id = uid;
  if v.status <> 'active' then
    raise exception 'profile_not_active';
  end if;
  if v.location is null then
    raise exception 'location_required';
  end if;
  perform private.require_sensitive_consent(uid);
  update public.profiles set last_active_at = now() where id = uid;

  prefs := private.search_prefs(uid);
  radius := prefs.radius_km;

  if prefs.mode = 'radius' then
    loop
      select count(*) into found_count from private.feed_candidates(uid, radius, not widened, min_results);
      exit when found_count >= min_results or radius >= max_radius;
      radius := least(radius * 2, max_radius);
      widened := true;
    end loop;
  end if;

  select coalesce(jsonb_agg(private.profile_card(c.candidate_id, c.distance_m, c.matched_drinks) order by c.ord), '[]'::jsonb)
    into cards
  from private.feed_candidates(uid, radius, not widened, page)
       with ordinality as c (candidate_id, distance_m, matched_drinks, ord);

  insert into private.feed_impressions (viewer_id, target_id, served_at)
  select uid, (c ->> 'id')::uuid, now() from jsonb_array_elements(cards) c
  on conflict (viewer_id, target_id) do update set served_at = excluded.served_at;

  return jsonb_build_object(
    'cards', cards,
    'mode', prefs.mode,
    'radius_km', case when prefs.mode = 'radius' then radius end,
    'widened', widened
  );
end;
$$;

-- get_my_profile: adds search preferences, areas and the seed flag ("tester en tant que").
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

do $$
declare
  f text;
begin
  foreach f in array array[
    'public.set_my_search_preferences(public.search_mode, integer, integer, integer, public.drink[])',
    'public.pass_profile(uuid)',
    'public.get_feed(integer)'
  ]
  loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end;
$$;
