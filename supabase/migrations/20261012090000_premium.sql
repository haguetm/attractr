-- Phase 7 (spec §9, §10): subscription through RevenueCat, Premium features
-- (advanced filters, who liked you, incognito, rewind, passport, statistics, popularity
-- indicator), boosts, and referral. Store-facing logic stays behind RevenueCat and the
-- RewardsProvider (Edge Functions); this file holds the rules.

insert into public.app_config (key, value, description, is_public) values
  ('premium.recently_active_days', '3', '"Actifs récemment" filter: active within this many days (provisoire).', true),
  ('boost.monthly_free', '1', 'Boosts offered each calendar month to Premium users.', true),
  ('rewind.window_hours', '24', 'A pass can be undone within this many hours (Premium).', false),
  ('profile.max_interests', '5', 'Max interests on a profile.', true),
  ('revenuecat.entitlement', '"premium"', 'RevenueCat entitlement identifier for Premium.', true),
  ('revenuecat.referee_offer', '"referee_first_month_50"', 'Promotional offer shown to a referee with a discount reward (store-side id).', true),
  ('revenuecat.referrer_offer', '"referrer_discount_10"', 'Promotional offer shown to a non-subscribed referrer with a discount reward.', true);

-- Profile details used by the advanced filters ---------------------------------------------

alter table public.profiles
  add column education_level text check (education_level in ('secondary', 'bac', 'bac_2', 'bac_3', 'bac_5', 'doctorate', 'other')),
  add column height_cm smallint check (height_cm between 120 and 230),
  add column incognito boolean not null default false;

create table public.interests (
  code text primary key check (code ~ '^[a-z_]+$'),
  sort_order smallint not null,
  active boolean not null default true
);

insert into public.interests (code, sort_order) values
  ('music', 1), ('concerts', 2), ('cinema', 3), ('series', 4), ('reading', 5), ('travel', 6), ('hiking', 7),
  ('running', 8), ('climbing', 9), ('yoga', 10), ('cooking', 11), ('restaurants', 12), ('board_games', 13),
  ('video_games', 14), ('art', 15), ('museums', 16), ('photography', 17), ('dance', 18), ('theatre', 19),
  ('volunteering', 20), ('animals', 21), ('nature', 22), ('tech', 23), ('fashion', 24);

alter table public.interests enable row level security;
revoke insert, update, delete, truncate on public.interests from authenticated;
create policy interests_read on public.interests for select to authenticated using (true);

create table public.profile_interests (
  user_id uuid not null references public.profiles (id) on delete cascade,
  interest_code text not null references public.interests (code),
  primary key (user_id, interest_code)
);

alter table public.profile_interests enable row level security;
revoke insert, update, delete, truncate on public.profile_interests from authenticated;
create policy profile_interests_select_own on public.profile_interests
  for select to authenticated using (user_id = (select auth.uid()));

-- Optional details, for everyone (filtering on them is Premium).
create function public.set_my_details(p_education_level text, p_height_cm integer, p_interests text[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
begin
  if coalesce(cardinality(p_interests), 0) > private.config_int('profile.max_interests') then
    raise exception 'too_many_interests';
  end if;
  if exists (select 1 from unnest(coalesce(p_interests, '{}')) i where not exists (
    select 1 from public.interests x where x.code = i and x.active)) then
    raise exception 'unknown_interest';
  end if;
  update public.profiles set education_level = p_education_level, height_cm = p_height_cm where id = uid;
  delete from public.profile_interests where user_id = uid;
  insert into public.profile_interests (user_id, interest_code)
  select distinct uid, i from unnest(coalesce(p_interests, '{}')) i;
end;
$$;

-- Entitlements from RevenueCat ------------------------------------------------------------------

alter table private.entitlements
  add column product_id text,
  add column updated_at timestamptz not null default now();

create unique index entitlements_revenuecat_idx on private.entitlements (user_id, entitlement) where source = 'revenuecat';

-- Paid subscription (not referral or promo months): decides "parrain abonné" (spec §9).
create function private.is_paying_subscriber(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from private.entitlements e
    where e.user_id = p_user_id and e.entitlement = 'premium' and e.source = 'revenuecat'
      and e.starts_at <= now() and (e.expires_at is null or e.expires_at > now())
  );
$$;

create function private.premium_until(p_user_id uuid)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select max(coalesce(e.expires_at, 'infinity'::timestamptz)) from private.entitlements e
  where e.user_id = p_user_id and e.entitlement = 'premium' and (e.expires_at is null or e.expires_at > now());
$$;

create table private.revenuecat_events (
  id text primary key,
  type text not null,
  app_user_id text,
  payload jsonb not null,
  outcome text,
  received_at timestamptz not null default now()
);

-- Boosts --------------------------------------------------------------------------------------

create table private.boost_credits (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  source text not null check (source in ('purchase', 'monthly', 'gift', 'test')),
  created_at timestamptz not null default now(),
  used_at timestamptz
);

create index boost_credits_user_idx on private.boost_credits (user_id) where used_at is null;

create table public.boosts (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  starts_at timestamptz not null default now(),
  ends_at timestamptz not null
);

create index boosts_active_idx on public.boosts (user_id, ends_at);

alter table public.boosts enable row level security;
revoke insert, update, delete, truncate on public.boosts from authenticated;
create policy boosts_select_own on public.boosts for select to authenticated using (user_id = (select auth.uid()));

create function private.is_boosted(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.boosts b where b.user_id = p_user_id and now() between b.starts_at and b.ends_at);
$$;

-- Profile views (one per viewer and day): statistics, boost results, popularity minimum.
create table private.profile_view_events (
  target_id uuid not null references public.profiles (id) on delete cascade,
  viewer_id uuid not null references public.profiles (id) on delete cascade,
  view_day date not null default current_date,
  viewed_at timestamptz not null default now(),
  primary key (target_id, viewer_id, view_day)
);

create index profile_view_events_target_idx on private.profile_view_events (target_id, viewed_at desc);

-- RevenueCat webhook events (spec §10, prices configured in RevenueCat) -------------------------

create function private.apply_revenuecat_event(p_event jsonb)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  ev_id text := p_event ->> 'id';
  ev_type text := p_event ->> 'type';
  raw_user text := p_event ->> 'app_user_id';
  uid uuid;
  product text := coalesce(p_event ->> 'product_id', '');
  expires timestamptz := case when p_event ? 'expiration_at_ms' and p_event ->> 'expiration_at_ms' is not null
                              then to_timestamp((p_event ->> 'expiration_at_ms')::bigint / 1000.0) end;
  purchased timestamptz := coalesce(case when p_event ->> 'purchased_at_ms' is not null
                                         then to_timestamp((p_event ->> 'purchased_at_ms')::bigint / 1000.0) end, now());
  result text := 'recorded';
  from_id text;
begin
  if ev_id is null or ev_type is null then
    raise exception 'invalid_event';
  end if;
  if exists (select 1 from private.revenuecat_events where id = ev_id) then
    return 'duplicate';
  end if;
  insert into private.revenuecat_events (id, type, app_user_id, payload) values (ev_id, ev_type, raw_user, p_event);

  if raw_user ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    uid := raw_user::uuid;
  end if;
  if ev_type <> 'TRANSFER' and (uid is null or not exists (select 1 from public.profiles where id = uid)) then
    update private.revenuecat_events set outcome = 'unknown_user' where id = ev_id;
    return 'unknown_user';
  end if;

  if ev_type = 'NON_RENEWING_PURCHASE' and product like 'boost%' then
    insert into private.boost_credits (user_id, source) values (uid, 'purchase');
    result := 'boost_credited';
  elsif ev_type in ('INITIAL_PURCHASE', 'RENEWAL', 'PRODUCT_CHANGE', 'UNCANCELLATION', 'SUBSCRIPTION_EXTENDED', 'TEMPORARY_ENTITLEMENT_GRANT') then
    insert into private.entitlements (user_id, entitlement, source, starts_at, expires_at, product_id)
    values (uid, 'premium', 'revenuecat', purchased, expires, product)
    on conflict (user_id, entitlement) where source = 'revenuecat'
    do update set expires_at = excluded.expires_at, product_id = excluded.product_id, updated_at = now(),
                  starts_at = least(private.entitlements.starts_at, excluded.starts_at);
    if ev_type = 'INITIAL_PURCHASE' then
      -- The referral discount (if any) was used on this first payment.
      update private.referral_rewards set status = 'applied', applied_at = now()
       where user_id = uid and kind = 'discount' and status = 'earned';
    end if;
    result := 'premium_active';
  elsif ev_type = 'EXPIRATION' then
    update private.entitlements set expires_at = least(coalesce(expires_at, now()), now()), updated_at = now()
     where user_id = uid and source = 'revenuecat';
    -- Free months not yet applied stop with the referrer's subscription (spec §9).
    update private.referral_rewards set status = 'void'
     where user_id = uid and kind = 'free_month' and status = 'earned';
    result := 'premium_expired';
  elsif ev_type = 'TRANSFER' then
    for from_id in select jsonb_array_elements_text(coalesce(p_event -> 'transferred_from', '[]')) loop
      if from_id ~* '^[0-9a-f-]{36}$' and exists (select 1 from jsonb_array_elements_text(coalesce(p_event -> 'transferred_to', '[]')) t
                                                  where t ~* '^[0-9a-f-]{36}$') then
        update private.entitlements
           set user_id = (select t::uuid from jsonb_array_elements_text(p_event -> 'transferred_to') t
                          where t ~* '^[0-9a-f-]{36}$' limit 1), updated_at = now()
         where user_id = from_id::uuid and source = 'revenuecat';
      end if;
    end loop;
    result := 'transferred';
  end if;

  update private.revenuecat_events set outcome = result where id = ev_id;
  return result;
end;
$$;

create function public.service_apply_revenuecat_event(p_event jsonb)
returns text
language sql
security definer
set search_path = ''
as $$
  select private.apply_revenuecat_event(p_event);
$$;

-- Boost (spec §10): 30 minutes at the top of the zone, with the views obtained -----------------

create function public.activate_boost()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  credit_id bigint;
  ends timestamptz;
begin
  if (select status from public.profiles where id = uid) <> 'active' then
    raise exception 'profile_not_active';
  end if;
  if private.is_boosted(uid) then
    raise exception 'boost_already_active';
  end if;
  select id into credit_id from private.boost_credits
  where user_id = uid and used_at is null order by created_at limit 1 for update skip locked;
  if credit_id is null then
    raise exception 'no_boost_credit';
  end if;
  update private.boost_credits set used_at = now() where id = credit_id;
  insert into public.boosts (user_id, ends_at)
  values (uid, now() + make_interval(mins => private.config_int('boost.duration_minutes')))
  returning ends_at into ends;
  return jsonb_build_object('ends_at', ends);
end;
$$;

create function public.get_my_boost()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'credits', (select count(*) from private.boost_credits c where c.user_id = (select auth.uid()) and c.used_at is null),
    'last', (select jsonb_build_object(
                'starts_at', b.starts_at, 'ends_at', b.ends_at, 'active', now() between b.starts_at and b.ends_at,
                'views', (select count(*) from private.profile_view_events e
                          where e.target_id = b.user_id and e.viewed_at between b.starts_at and b.ends_at))
             from public.boosts b where b.user_id = (select auth.uid()) order by b.starts_at desc limit 1)
  );
$$;

create function private.grant_monthly_boosts()
returns integer
language sql
security definer
set search_path = ''
as $$
  with granted as (
    insert into private.boost_credits (user_id, source)
    select p.id, 'monthly' from public.profiles p
    where p.status in ('active', 'paused') and private.is_premium(p.id)
      and not exists (select 1 from private.boost_credits c where c.user_id = p.id and c.source = 'monthly'
                      and c.created_at >= date_trunc('month', now()))
    returning 1
  )
  select count(*)::integer from granted;
$$;

-- Search preferences: Premium filters and passport ------------------------------------------------

alter table public.search_preferences
  add column verified_only boolean not null default false,
  add column recently_active boolean not null default false,
  add column education_levels text[],
  add column height_min smallint check (height_min between 120 and 230),
  add column height_max smallint check (height_max between 120 and 230),
  add column interests text[],
  add column compositions text[],
  add column passport_location extensions.geography(Point, 4326),
  add column passport_label text check (char_length(passport_label) <= 80);

drop function public.set_my_search_preferences(public.search_mode, integer, integer, integer, public.drink[]);

-- p_premium: {verified_only, recently_active, education_levels, height_min, height_max,
-- interests, compositions}. Refused without Premium; ignored by the feed if Premium ends.
create function public.set_my_search_preferences(
  p_mode public.search_mode,
  p_radius_km integer,
  p_age_min integer,
  p_age_max integer,
  p_drinks public.drink[] default null,
  p_premium jsonb default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  p public.profiles;
  premium_set boolean := p_premium is not null and p_premium <> '{}'::jsonb;
  t text[];
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
  if premium_set and not private.is_premium(uid) then
    raise exception 'premium_required';
  end if;

  insert into public.search_preferences (user_id, mode, radius_km, age_min, age_max, drinks, updated_at)
  values (uid, p_mode, p_radius_km, p_age_min, p_age_max, p_drinks, now())
  on conflict (user_id) do update
    set mode = excluded.mode, radius_km = excluded.radius_km, age_min = excluded.age_min,
        age_max = excluded.age_max, drinks = excluded.drinks, updated_at = excluded.updated_at;

  if p_premium is not null then
    update public.search_preferences set
      verified_only = coalesce((p_premium ->> 'verified_only')::boolean, false),
      recently_active = coalesce((p_premium ->> 'recently_active')::boolean, false),
      education_levels = nullif(array(select jsonb_array_elements_text(coalesce(p_premium -> 'education_levels', '[]'))), '{}'),
      height_min = (p_premium ->> 'height_min')::smallint,
      height_max = (p_premium ->> 'height_max')::smallint,
      interests = nullif(array(select jsonb_array_elements_text(coalesce(p_premium -> 'interests', '[]'))), '{}'),
      compositions = nullif(array(select jsonb_array_elements_text(coalesce(p_premium -> 'compositions', '[]'))), '{}')
    where user_id = uid;
  end if;
end;
$$;

-- Passport (Premium): search around another place. Set by the update-location Edge Function.
create function public.service_set_passport(p_user_id uuid, p_lat double precision, p_lon double precision, p_label text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_premium(p_user_id) then
    raise exception 'premium_required';
  end if;
  insert into public.search_preferences (user_id) values (p_user_id) on conflict (user_id) do nothing;
  update public.search_preferences
     set passport_location = private.snap_point(p_lat, p_lon), passport_label = left(p_label, 80), mode = 'radius', updated_at = now()
   where user_id = p_user_id;
end;
$$;

create function public.clear_my_passport()
returns void
language sql
security definer
set search_path = ''
as $$
  update public.search_preferences set passport_location = null, passport_label = null, updated_at = now()
  where user_id = (select auth.uid());
$$;

-- Incognito (Premium): visible only to people you liked.
create function public.set_my_incognito(p_enabled boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
begin
  if p_enabled and not private.is_premium(uid) then
    raise exception 'premium_required';
  end if;
  update public.profiles set incognito = p_enabled where id = uid;
end;
$$;

-- Popularity indicator (Premium, P1-P6) ------------------------------------------------------------
-- Daily ranking of likes received over popularity.window_days (likes during the person's
-- own boosts excluded), within the same département and main drink.

create table private.popularity (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  level text check (level in ('high', 'medium', 'low')),
  computed_at timestamptz not null default now()
);

create function private.compute_popularity()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  window_days integer := private.config_int('popularity.window_days');
  min_age integer := private.config_int('popularity.min_profile_age_days');
  min_views integer := private.config_int('popularity.min_views');
  high_share numeric := (private.config('popularity.high_share'))::numeric;
  low_share numeric := (private.config('popularity.low_share'))::numeric;
  n integer;
begin
  delete from private.popularity;
  with stats as (
    select p.id, p.department_code as zone,
           (select d.drink from public.profile_drinks d where d.user_id = p.id order by (d.drink = 'beer'), d.drink limit 1) as main_drink,
           (select count(*) from public.swipes s
            where s.target_id = p.id and s.action = 'like' and s.created_at > now() - make_interval(days => window_days)
              and not exists (select 1 from public.boosts b where b.user_id = p.id and s.created_at between b.starts_at and b.ends_at)) as likes,
           (select count(*) from private.profile_view_events e where e.target_id = p.id) as views
    from public.profiles p
    where p.status = 'active' and p.department_code is not null
      and p.created_at < now() - make_interval(days => min_age)
  ),
  ranked as (
    -- size uses an unordered window: with ORDER BY, count(*) would be a running count.
    select id,
           percent_rank() over (partition by zone, main_drink order by likes) as pr,
           count(*) over (partition by zone, main_drink) as size
    from stats where views >= min_views
  )
  insert into private.popularity (user_id, level)
  select id, case when size < 5 then null
                  when pr > 1 - high_share then 'high'
                  when pr < low_share then 'low'
                  else 'medium' end
  from ranked;
  get diagnostics n = row_count;
  return n;
end;
$$;

-- Shown level: only high/low (P1), never for incognito profiles (P6).
create function private.popularity_level(p_user_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select pop.level from private.popularity pop
  join public.profiles p on p.id = pop.user_id
  where pop.user_id = p_user_id and pop.level in ('high', 'low') and not (p.incognito and private.is_premium(p.id));
$$;

-- Feed (replaces phase 3): passport origin, incognito, Premium filters, boosts first ----------------

create or replace function private.feed_candidates(
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
  premium boolean := private.is_premium(p_viewer_id);
  origin extensions.geography;
  default_radius integer := private.config_int('feed.default_radius_km');
  recycle_days integer := private.config_int('feed.pass_recycle_days');
  active_hours integer := private.config_int('activity.badge_window_hours');
  recent_days integer := private.config_int('premium.recently_active_days');
begin
  select * into v from public.profiles where id = p_viewer_id;
  v_age := private.age_of(v.birth_date);
  select array_agg(drink order by drink) into v_drinks from public.profile_drinks where user_id = p_viewer_id;
  -- Passport (Premium): distances are measured from the chosen place.
  origin := case when premium and prefs.passport_location is not null then prefs.passport_location else v.location end;

  return query
  with base as materialized (
    select p.id, p.gender, p.last_active_at,
           extensions.st_distance(p.location, origin) as dist,
           (select array_agg(d.drink order by d.drink) from public.profile_drinks d where d.user_id = p.id) as drinks
    from public.profiles p
    left join public.search_preferences sp on sp.user_id = p.id
    where p.id <> p_viewer_id
      and p.status = 'active'
      and p.location is not null
      and p.verification_status <> 'rejected'
      and case prefs.mode
            when 'radius' then extensions.st_dwithin(p.location, origin, p_radius_km * 1000.0)
            when 'department' then p.department_code = v.department_code
            else p.region_code = v.region_code
          end
      and private.age_of(p.birth_date) between prefs.age_min and prefs.age_max
      and (not p_reciprocal or (
            case coalesce(sp.mode, 'radius')
              when 'radius' then extensions.st_dwithin(p.location, origin, coalesce(sp.radius_km, default_radius) * 1000.0)
              when 'department' then p.department_code = v.department_code
              else p.region_code = v.region_code
            end
            and v_age between coalesce(sp.age_min, 18) and coalesce(sp.age_max, 99)))
      -- Incognito (Premium): only visible to people they liked.
      and (not p.incognito or not private.is_premium(p.id) or exists (
            select 1 from public.swipes s where s.actor_id = p.id and s.target_id = p_viewer_id and s.action = 'like'))
      -- Premium filters, applied only while the viewer is Premium.
      and (not premium or (
            (not prefs.verified_only or p.verification_status = 'verified')
            and (not prefs.recently_active or p.last_active_at > now() - make_interval(days => recent_days))
            and (prefs.education_levels is null or p.education_level = any (prefs.education_levels))
            and (prefs.height_min is null or p.height_cm >= prefs.height_min)
            and (prefs.height_max is null or p.height_cm <= prefs.height_max)
            and (prefs.interests is null or exists (
                  select 1 from public.profile_interests pi where pi.user_id = p.id and pi.interest_code = any (prefs.interests)))))
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
    select b.id, b.dist, b.last_active_at, sens.s,
           private.match_drinks(v.gender, v_drinks, v_s, b.gender, b.drinks, sens.s) as matched,
           private.is_boosted(b.id) as boosted
    from base b
    cross join lateral (select private.read_sensitive(b.id) as s) sens
  )
  select sc.id, sc.dist, sc.matched
  from scored sc
  where cardinality(sc.matched) > 0
    and (prefs.drinks is null or sc.matched && prefs.drinks)
    -- "Composition recherchée" (Premium): what a polyamorous candidate is looking for.
    and (not premium or prefs.compositions is null or coalesce(sc.s -> 'composition' -> 'kinds', '[]'::jsonb) ?| prefs.compositions)
  order by sc.boosted desc,
           (sc.last_active_at > now() - make_interval(hours => active_hours)) desc,
           sc.dist, sc.id
  limit p_limit;
end;
$$;

-- Cards with the popularity indicator for Premium viewers, and daily view events.
create or replace function public.get_feed(p_limit integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  v public.profiles;
  prefs public.search_preferences;
  premium boolean;
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
  premium := private.is_premium(uid);
  radius := prefs.radius_km;

  if prefs.mode = 'radius' then
    loop
      select count(*) into found_count from private.feed_candidates(uid, radius, not widened, min_results);
      exit when found_count >= min_results or radius >= max_radius;
      radius := least(radius * 2, max_radius);
      widened := true;
    end loop;
  end if;

  select coalesce(jsonb_agg(
           private.profile_card(c.candidate_id, c.distance_m, c.matched_drinks)
           || case when premium then jsonb_build_object('popularity', private.popularity_level(c.candidate_id)) else '{}'::jsonb end
           order by c.ord), '[]'::jsonb)
    into cards
  from private.feed_candidates(uid, radius, not widened, page)
       with ordinality as c (candidate_id, distance_m, matched_drinks, ord);

  insert into private.feed_impressions (viewer_id, target_id, served_at)
  select uid, (c ->> 'id')::uuid, now() from jsonb_array_elements(cards) c
  on conflict (viewer_id, target_id) do update set served_at = excluded.served_at;

  insert into private.profile_view_events (target_id, viewer_id)
  select (c ->> 'id')::uuid, uid from jsonb_array_elements(cards) c
  on conflict (target_id, viewer_id, view_day) do nothing;

  return jsonb_build_object(
    'cards', cards,
    'mode', prefs.mode,
    'radius_km', case when prefs.mode = 'radius' then radius end,
    'widened', widened,
    'passport', case when premium and prefs.passport_location is not null then prefs.passport_label end
  );
end;
$$;

-- Who liked you (Premium): verified profiles only, still waiting for an answer.
create function public.get_likes_received()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  cards jsonb;
begin
  if not private.is_premium(uid) then
    raise exception 'premium_required';
  end if;
  select coalesce(jsonb_agg(
           private.profile_card(p.id, extensions.st_distance(p.location, me.location), '{}')
           || jsonb_build_object('liked_at', s.created_at, 'liked_target', jsonb_build_object('kind', s.target_kind, 'ref', s.target_ref),
                                 'popularity', private.popularity_level(p.id))
           order by s.created_at desc), '[]'::jsonb)
    into cards
  from public.swipes s
  join public.profiles p on p.id = s.actor_id and p.status = 'active' and p.verification_status = 'verified'
  cross join (select location from public.profiles where id = uid) me
  where s.target_id = uid and s.action = 'like'
    and not exists (select 1 from public.swipes mine where mine.actor_id = uid and mine.target_id = s.actor_id)
    and not private.is_blocked_pair(uid, s.actor_id);

  -- Their photos become readable, as for a feed card.
  insert into private.feed_impressions (viewer_id, target_id, served_at)
  select uid, (c ->> 'id')::uuid, now() from jsonb_array_elements(cards) c
  on conflict (viewer_id, target_id) do update set served_at = excluded.served_at;
  return cards;
end;
$$;

-- Rewind (Premium): undo the last pass and show that profile again.
create function public.rewind_last_pass()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  last public.swipes;
begin
  if not private.is_premium(uid) then
    raise exception 'premium_required';
  end if;
  select * into last from public.swipes
  where actor_id = uid and action = 'pass'
    and created_at > now() - make_interval(hours => private.config_int('rewind.window_hours'))
  order by created_at desc limit 1;
  if last.id is null then
    raise exception 'nothing_to_rewind';
  end if;
  delete from public.swipes where id = last.id;
  insert into private.feed_impressions (viewer_id, target_id) values (uid, last.target_id)
  on conflict (viewer_id, target_id) do update set served_at = now();
  return private.profile_card(last.target_id,
    (select extensions.st_distance(a.location, b.location) from public.profiles a, public.profiles b where a.id = uid and b.id = last.target_id),
    private.match_drinks(
      (select gender from public.profiles where id = uid), (select array_agg(drink order by drink) from public.profile_drinks where user_id = uid),
      private.read_sensitive(uid),
      (select gender from public.profiles where id = last.target_id), (select array_agg(drink order by drink) from public.profile_drinks where user_id = last.target_id),
      private.read_sensitive(last.target_id)));
end;
$$;

-- Statistics (Premium): views, likes per photo and per answer, own popularity level (P5).
create function public.get_my_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
begin
  if not private.is_premium(uid) then
    raise exception 'premium_required';
  end if;
  return jsonb_build_object(
    'views_7d', (select count(*) from private.profile_view_events where target_id = uid and viewed_at > now() - interval '7 days'),
    'views_30d', (select count(*) from private.profile_view_events where target_id = uid and viewed_at > now() - interval '30 days'),
    'likes_7d', (select count(*) from public.swipes where target_id = uid and action = 'like' and created_at > now() - interval '7 days'),
    'likes_30d', (select count(*) from public.swipes where target_id = uid and action = 'like' and created_at > now() - interval '30 days'),
    'photos', coalesce((select jsonb_agg(jsonb_build_object('id', ph.id, 'storage_path', ph.storage_path, 'position', ph.position,
                          'likes', (select count(*) from public.swipes s where s.target_id = uid and s.action = 'like'
                                    and s.target_kind = 'photo' and s.target_ref = ph.id::text)) order by ph.position)
                        from public.photos ph where ph.user_id = uid), '[]'::jsonb),
    'prompts', coalesce((select jsonb_agg(jsonb_build_object('question_code', q.question_code,
                          'likes', (select count(*) from public.swipes s where s.target_id = uid and s.action = 'like'
                                    and s.target_kind = 'prompt' and s.target_ref = q.question_code)) order by q.position)
                         from public.profile_prompts q where q.user_id = uid), '[]'::jsonb),
    'popularity', (select level from private.popularity where user_id = uid)
  );
end;
$$;

-- Photos of people who liked you are readable once listed (get_likes_received writes an
-- impression); nothing to change in can_view_photos_of.

-- Referral (spec §9) -------------------------------------------------------------------------------

create table public.referral_codes (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  code text not null unique check (code ~ '^[A-Z0-9-]{4,32}$'),
  created_at timestamptz not null default now()
);

alter table public.referral_codes enable row level security;
revoke insert, update, delete, truncate on public.referral_codes from authenticated;
create policy referral_codes_select_own on public.referral_codes for select to authenticated using (user_id = (select auth.uid()));

create table private.referrals (
  id bigint generated always as identity primary key,
  referrer_id uuid not null references public.profiles (id) on delete cascade,
  referee_id uuid not null unique references public.profiles (id) on delete cascade,
  status text not null default 'signed_up' check (status in ('signed_up', 'validated', 'rejected')),
  reject_reason text,
  created_at timestamptz not null default now(),
  validated_at timestamptz
);

create table private.referral_rewards (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  referral_id bigint not null references private.referrals (id) on delete cascade,
  role text not null check (role in ('referrer', 'referee')),
  kind text not null check (kind in ('free_month', 'discount')),
  value numeric not null,
  status text not null default 'earned' check (status in ('earned', 'applied', 'void')),
  created_at timestamptz not null default now(),
  applied_at timestamptz
);

create index referral_rewards_user_idx on private.referral_rewards (user_id, status);

create function public.get_my_referral_code()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  existing text;
  candidate text;
begin
  select code into existing from public.referral_codes where user_id = uid;
  if existing is not null then
    return existing;
  end if;
  loop
    candidate := upper(encode(extensions.gen_random_bytes(4), 'hex'));
    exit when not exists (select 1 from public.referral_codes where code = candidate);
  end loop;
  insert into public.referral_codes (user_id, code) values (uid, candidate);
  return candidate;
end;
$$;

-- Stacks a free month after the user's current Premium end.
create function private.grant_free_month(p_user_id uuid, p_reward_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  starts timestamptz := greatest(now(), coalesce(private.premium_until(p_user_id), now()));
begin
  if starts = 'infinity'::timestamptz then
    starts := now();
  end if;
  insert into private.entitlements (user_id, entitlement, source, starts_at, expires_at)
  values (p_user_id, 'premium', 'referral', starts, starts + interval '1 month');
  update private.referral_rewards set status = 'applied', applied_at = now() where id = p_reward_id;
end;
$$;

-- Hourly: links signup codes to referrers, then validates referees once verified and
-- active for referral.referee_validation_days. Rewards (spec §9):
--   paying referrer: 1 free month (applied by the RewardsProvider, capped per year), referee 1 month;
--   non-paying referrer: a discount on a future subscription, referee 50 % on the first payment.
create function private.process_referrals()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
  linked integer := 0;
  validated integer := 0;
  months_this_year numeric;
  referee_reward bigint;
begin
  -- 1. New signups with a code
  for r in
    select s.user_id as referee_id, s.code, c.user_id as referrer_id
    from private.signup_referrals s
    join public.profiles p on p.id = s.user_id and p.status <> 'onboarding'
    left join public.referral_codes c on c.code = s.code
    where not exists (select 1 from private.referrals x where x.referee_id = s.user_id)
  loop
    insert into private.referrals (referrer_id, referee_id, status, reject_reason)
    values (coalesce(r.referrer_id, r.referee_id), r.referee_id,
            case when r.referrer_id is null or r.referrer_id = r.referee_id then 'rejected' else 'signed_up' end,
            case when r.referrer_id is null then 'unknown_code' when r.referrer_id = r.referee_id then 'self_referral' end);
    linked := linked + 1;
  end loop;

  -- 2. Validation: verified selfie and account active for N days
  for r in
    select x.id, x.referrer_id, x.referee_id
    from private.referrals x
    join public.profiles referee on referee.id = x.referee_id
    join public.profiles referrer on referrer.id = x.referrer_id
    where x.status = 'signed_up'
      and referee.verification_status = 'verified' and referee.status = 'active'
      and referee.created_at < now() - make_interval(days => private.config_int('referral.referee_validation_days'))
    for update of x
  loop
    update private.referrals set status = 'validated', validated_at = now() where id = r.id;
    validated := validated + 1;

    if private.is_paying_subscriber(r.referrer_id) then
      select coalesce(sum(value), 0) into months_this_year from private.referral_rewards
      where user_id = r.referrer_id and role = 'referrer' and kind = 'free_month' and status <> 'void'
        and created_at > now() - interval '1 year';
      if months_this_year < private.config_int('referral.annual_cap_months') then
        insert into private.referral_rewards (user_id, referral_id, role, kind, value)
        values (r.referrer_id, r.id, 'referrer', 'free_month', private.config_int('referral.premium_months_per_referee'));
      end if;
      -- The referee gets their month right away.
      insert into private.referral_rewards (user_id, referral_id, role, kind, value)
      values (r.referee_id, r.id, 'referee', 'free_month', 1)
      returning id into referee_reward;
      perform private.grant_free_month(r.referee_id, referee_reward);
    else
      if jsonb_typeof(private.config('referral.non_subscriber_referrer_discount_pct')) = 'number' then
        insert into private.referral_rewards (user_id, referral_id, role, kind, value)
        values (r.referrer_id, r.id, 'referrer', 'discount', private.config_int('referral.non_subscriber_referrer_discount_pct'));
      end if;
      insert into private.referral_rewards (user_id, referral_id, role, kind, value)
      values (r.referee_id, r.id, 'referee', 'discount', private.config_int('referral.referee_first_payment_discount_pct'));
    end if;

    -- "Devenir ami de mon parrain" (same rules as any friendship, silently skipped otherwise).
    if exists (select 1 from private.signup_referrals s where s.user_id = r.referee_id and s.befriend_referrer) then
      begin
        perform private.check_friendable(r.referee_id, r.referrer_id);
        perform private.accept_friendship(r.referee_id, r.referrer_id, r.referee_id);
      exception when others then
        null;
      end;
    end if;
  end loop;

  return jsonb_build_object('linked', linked, 'validated', validated);
end;
$$;

-- The referrer only sees statuses ("inscrit et vérifié"), never who (spec §9).
create function public.get_my_referrals()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
begin
  return jsonb_build_object(
    'code', public.get_my_referral_code(),
    'referrals', coalesce((
      select jsonb_agg(jsonb_build_object(
        'status', case when x.status = 'validated' then 'validated'
                       when p.verification_status = 'verified' then 'verified'
                       else 'signed_up' end,
        'created_at', x.created_at) order by x.created_at desc)
      from private.referrals x join public.profiles p on p.id = x.referee_id
      where x.referrer_id = uid and x.status <> 'rejected'), '[]'::jsonb),
    'rewards', coalesce((
      select jsonb_agg(jsonb_build_object('role', w.role, 'kind', w.kind, 'value', w.value, 'status', w.status) order by w.created_at desc)
      from private.referral_rewards w where w.user_id = uid), '[]'::jsonb),
    'free_months_this_year', (select coalesce(sum(value), 0) from private.referral_rewards
                              where user_id = uid and role = 'referrer' and kind = 'free_month' and status <> 'void'
                                and created_at > now() - interval '1 year'),
    'annual_cap_months', private.config_int('referral.annual_cap_months')
  );
end;
$$;

-- RewardsProvider queue (apply-rewards Edge Function): referrer free months to apply store-side.
create function public.service_pending_rewards(p_limit integer default 100)
returns table (id bigint, user_id uuid, kind text, value numeric)
language sql
stable
security definer
set search_path = ''
as $$
  select w.id, w.user_id, w.kind, w.value from private.referral_rewards w
  where w.status = 'earned' and w.kind = 'free_month' and w.role = 'referrer'
  order by w.created_at limit p_limit;
$$;

-- Mock / local application of a free month (the real provider grants it in RevenueCat first).
create function public.service_apply_free_month(p_reward_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  w private.referral_rewards;
begin
  select * into w from private.referral_rewards where id = p_reward_id and status = 'earned' and kind = 'free_month' for update;
  if w.id is null then
    raise exception 'reward_not_found';
  end if;
  perform private.grant_free_month(w.user_id, w.id);
end;
$$;

-- Scheduled jobs: daily and hourly parts are gated by private.job_runs ------------------------------

create table private.job_runs (
  name text primary key,
  last_run timestamptz not null
);

create function private.due(p_name text, p_every interval)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (select 1 from private.job_runs where name = p_name and last_run > now() - p_every) then
    return false;
  end if;
  insert into private.job_runs (name, last_run) values (p_name, now())
  on conflict (name) do update set last_run = excluded.last_run;
  return true;
end;
$$;

create or replace function private.run_scheduled_jobs()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  result jsonb := jsonb_build_object(
    'expired', private.expire_matches(),
    'reminders', private.queue_first_message_reminders(),
    'your_turn', private.queue_your_turn(),
    'outing_feedback', private.queue_outing_feedback()
  );
begin
  if private.due('referrals', interval '1 hour') then
    result := result || jsonb_build_object('referrals', private.process_referrals());
  end if;
  if private.due('daily', interval '1 day') then
    result := result || jsonb_build_object('popularity', private.compute_popularity(),
                                           'monthly_boosts', private.grant_monthly_boosts());
  end if;
  return result;
end;
$$;

-- get_my_profile: Premium status, incognito, details, boosts --------------------------------------

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

-- Grants ----------------------------------------------------------------------------------------

do $$
declare
  f text;
begin
  foreach f in array array[
    'public.set_my_details(text, integer, text[])',
    'public.activate_boost()',
    'public.get_my_boost()',
    'public.set_my_search_preferences(public.search_mode, integer, integer, integer, public.drink[], jsonb)',
    'public.clear_my_passport()',
    'public.set_my_incognito(boolean)',
    'public.get_likes_received()',
    'public.rewind_last_pass()',
    'public.get_my_stats()',
    'public.get_my_referral_code()',
    'public.get_my_referrals()'
  ]
  loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;

  foreach f in array array[
    'public.service_apply_revenuecat_event(jsonb)',
    'public.service_set_passport(uuid, double precision, double precision, text)',
    'public.service_pending_rewards(integer)',
    'public.service_apply_free_month(bigint)'
  ]
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end;
$$;
