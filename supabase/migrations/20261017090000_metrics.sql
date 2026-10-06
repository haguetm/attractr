-- Retention (D1, D7, D30) and daily KPIs (spec §14 phase 11). Server-side source of
-- truth, independent from PostHog.
--
-- Privacy: activity is recorded against a random metrics_id, never the user id. The link
-- user -> metrics_id is deleted with the account, so a deleted user's days stay counted
-- (no survivor bias) but cannot be tied back to anyone. Only the activation day, the
-- main drink at activation and active days are kept; raw rows expire after
-- metrics.raw_retention_days. Daily KPIs are aggregates. Seed and couple profiles are
-- excluded.

insert into public.app_config (key, value, description, is_public) values
  ('metrics.timezone', '"Europe/Paris"', 'Time zone used to cut days for metrics.', false),
  ('metrics.retention_window_days', '7', 'Day N retention = active at least once on days N .. N+window-1 after activation (provisoire).', false),
  ('metrics.raw_retention_days', '400', 'Pseudonymous activity rows older than this are deleted (provisoire).', false);

alter table public.profiles add column activated_at timestamptz;
update public.profiles set activated_at = created_at where status <> 'onboarding' and activated_at is null;

create table private.metrics_subjects (
  metrics_id uuid primary key default gen_random_uuid(),
  activated_on date not null,
  main_drink public.drink,
  deleted_on date
);

create index metrics_subjects_cohort_idx on private.metrics_subjects (activated_on);

-- The only place where a user id meets a metrics_id. Erased with the account.
create table private.metrics_links (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  metrics_id uuid not null unique references private.metrics_subjects (metrics_id) on delete cascade
);

create table private.metrics_activity (
  metrics_id uuid not null references private.metrics_subjects (metrics_id) on delete cascade,
  day date not null,
  primary key (metrics_id, day)
);

create index metrics_activity_day_idx on private.metrics_activity (day);

create function private.metrics_today(p_at timestamptz default now())
returns date
language sql
stable
security definer
set search_path = ''
as $$
  select (p_at at time zone (private.config('metrics.timezone') #>> '{}'))::date;
$$;

-- First activation stamps activated_at (whoever performs the update).
create function private.profiles_stamp_activation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'active' and old.status = 'onboarding' and new.activated_at is null then
    new.activated_at := now();
  end if;
  return new;
end;
$$;

create trigger profiles_stamp_activation
  before update of status on public.profiles
  for each row execute function private.profiles_stamp_activation();

create function private.metrics_track_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  mid uuid;
begin
  if new.is_seed or new.is_couple or new.activated_at is null then
    return null;
  end if;
  select metrics_id into mid from private.metrics_links where user_id = new.id;
  if mid is null then
    insert into private.metrics_subjects (activated_on, main_drink)
    values (
      private.metrics_today(new.activated_at),
      (select pd.drink from public.profile_drinks pd join public.drinks d on d.code = pd.drink
        where pd.user_id = new.id order by d.sort_order limit 1))
    returning metrics_id into mid;
    insert into private.metrics_links (user_id, metrics_id) values (new.id, mid);
    insert into private.metrics_activity (metrics_id, day)
    values (mid, private.metrics_today(new.activated_at)) on conflict do nothing;
  end if;
  insert into private.metrics_activity (metrics_id, day)
  values (mid, private.metrics_today(new.last_active_at)) on conflict do nothing;
  return null;
end;
$$;

create trigger profiles_metrics_track
  after update of status, last_active_at, activated_at on public.profiles
  for each row
  when (new.activated_at is not null)
  execute function private.metrics_track_profile();

-- Account deletion: the subject stays, anonymous, with its deletion day.
create function private.metrics_link_deleted()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update private.metrics_subjects set deleted_on = private.metrics_today() where metrics_id = old.metrics_id;
  return null;
end;
$$;

create trigger metrics_links_deleted
  after delete on private.metrics_links
  for each row execute function private.metrics_link_deleted();

-- App opened (foreground). Cheap: one activity day per user and day.
create function public.touch_my_activity()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
begin
  update public.profiles set last_active_at = now()
   where id = uid and status in ('active', 'paused')
     and private.metrics_today(last_active_at) <> private.metrics_today();
end;
$$;

revoke execute on function public.touch_my_activity() from public, anon;
grant execute on function public.touch_my_activity() to authenticated;

-- Retention by cohort ----------------------------------------------------------------
-- Day N retention: share of a cohort active at least once on days N .. N+window-1 after
-- its activation day (D1 uses a one-day window). A cohort counts for day N only once
-- that window is over. Rates are null for immature cohorts; cohorts under
-- p_min_size users are hidden (small-number privacy).
create function private.metrics_retention(
  p_from date,
  p_to date,
  p_grain text default 'week',
  p_min_size integer default 5,
  p_today date default null
)
returns table (
  cohort date,
  main_drink text,
  users integer,
  d1 numeric,
  d7 numeric,
  d30 numeric
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  w integer := private.config_int('metrics.retention_window_days');
  today date := coalesce(p_today, private.metrics_today());
begin
  if p_grain not in ('day', 'week', 'month') then
    raise exception 'invalid_grain';
  end if;
  return query
  with s as (
    select m.metrics_id, m.activated_on, date_trunc(p_grain, m.activated_on)::date as c, m.main_drink::text as drink,
      exists (select 1 from private.metrics_activity a where a.metrics_id = m.metrics_id
              and a.day = m.activated_on + 1) as r1,
      exists (select 1 from private.metrics_activity a where a.metrics_id = m.metrics_id
              and a.day between m.activated_on + 7 and m.activated_on + 7 + w - 1) as r7,
      exists (select 1 from private.metrics_activity a where a.metrics_id = m.metrics_id
              and a.day between m.activated_on + 30 and m.activated_on + 30 + w - 1) as r30
    from private.metrics_subjects m
    where m.activated_on between p_from and p_to
  )
  select s.c,
         case when grouping(s.drink) = 1 then 'all' else coalesce(s.drink, 'none') end,
         count(*)::integer,
         round(avg(s.r1::int) filter (where s.activated_on + 1 < today), 3),
         round(avg(s.r7::int) filter (where s.activated_on + 7 + w - 1 < today), 3),
         round(avg(s.r30::int) filter (where s.activated_on + 30 + w - 1 < today), 3)
  from s
  group by grouping sets ((s.c), (s.c, s.drink))
  having count(*) >= p_min_size
  order by 1, 2;
end;
$$;

-- Daily KPIs ----------------------------------------------------------------------
-- Snapshotted once a day for the previous day, so later account deletions do not
-- rewrite history. Counts only, no identifier.
create table private.metrics_daily (
  day date primary key,
  signups integer not null,
  activations integer not null,
  dau integer not null,
  wau integer not null,
  mau integer not null,
  likes integer not null,
  passes integer not null,
  matches integer not null,
  first_messages integer not null,
  messages integer not null,
  reports integer not null,
  premium_active integer not null,
  boosts integer not null,
  deletions integer not null,
  computed_at timestamptz not null default now()
);

create function private.snapshot_daily_metrics(p_day date default null)
returns date
language plpgsql
security definer
set search_path = ''
as $$
declare
  d date := coalesce(p_day, private.metrics_today() - 1);
  tz text := private.config('metrics.timezone') #>> '{}';
  t0 timestamptz := (d::timestamp at time zone tz);
  t1 timestamptz := ((d + 1)::timestamp at time zone tz);
begin
  insert into private.metrics_daily (day, signups, activations, dau, wau, mau, likes, passes, matches,
                                     first_messages, messages, reports, premium_active, boosts, deletions)
  select d,
    (select count(*) from public.profiles where created_at >= t0 and created_at < t1 and not is_seed and not is_couple),
    (select count(*) from private.metrics_subjects where activated_on = d),
    (select count(distinct metrics_id) from private.metrics_activity where day = d),
    (select count(distinct metrics_id) from private.metrics_activity where day between d - 6 and d),
    (select count(distinct metrics_id) from private.metrics_activity where day between d - 29 and d),
    (select count(*) from public.swipes where action = 'like' and created_at >= t0 and created_at < t1),
    (select count(*) from public.swipes where action = 'pass' and created_at >= t0 and created_at < t1),
    (select count(*) from public.matches where created_at >= t0 and created_at < t1),
    (select count(*) from public.matches where first_message_at >= t0 and first_message_at < t1),
    (select count(*) from public.messages where created_at >= t0 and created_at < t1),
    (select count(*) from public.reports where created_at >= t0 and created_at < t1),
    (select count(distinct e.user_id) from private.entitlements e join public.profiles p on p.id = e.user_id
      where e.entitlement = 'premium' and not p.is_seed and e.starts_at < t1 and (e.expires_at is null or e.expires_at > t1)),
    (select count(*) from public.boosts where starts_at >= t0 and starts_at < t1),
    (select count(*) from private.metrics_subjects where deleted_on = d)
  on conflict (day) do update set
    signups = excluded.signups, activations = excluded.activations, dau = excluded.dau, wau = excluded.wau,
    mau = excluded.mau, likes = excluded.likes, passes = excluded.passes, matches = excluded.matches,
    first_messages = excluded.first_messages, messages = excluded.messages, reports = excluded.reports,
    premium_active = excluded.premium_active, boosts = excluded.boosts, deletions = excluded.deletions,
    computed_at = now();
  return d;
end;
$$;

create function private.purge_metrics()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  n integer;
begin
  delete from private.metrics_activity
   where day < private.metrics_today() - private.config_int('metrics.raw_retention_days');
  get diagnostics n = row_count;
  delete from private.metrics_subjects s
   where s.deleted_on is not null
     and s.activated_on < private.metrics_today() - private.config_int('metrics.raw_retention_days');
  return n;
end;
$$;

-- Dashboard payload, read by the `metrics` Edge Function (service role only).
create function public.service_metrics_dashboard(p_days integer default 90)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  today date := private.metrics_today();
begin
  if p_days not between 7 and 400 then
    raise exception 'invalid_range';
  end if;
  return jsonb_build_object(
    'generated_at', now(),
    'retention_window_days', private.config_int('metrics.retention_window_days'),
    'retention', (select coalesce(jsonb_agg(to_jsonb(r)), '[]')
                  from private.metrics_retention(today - p_days, today, 'week') r),
    'daily', (select coalesce(jsonb_agg(to_jsonb(m) - 'computed_at' order by m.day), '[]')
              from private.metrics_daily m where m.day > today - p_days)
  );
end;
$$;

revoke execute on function public.service_metrics_dashboard(integer) from public, anon, authenticated;
grant execute on function public.service_metrics_dashboard(integer) to service_role;

-- Daily job: snapshot of yesterday and purge.
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
    'outing_feedback', private.queue_outing_feedback(),
    'group_invitations', private.expire_group_invitations(),
    'couples', private.refresh_all_couples()
  );
begin
  if private.due('referrals', interval '1 hour') then
    result := result || jsonb_build_object('referrals', private.process_referrals(),
                                           'offer_codes', private.assign_offer_codes());
  end if;
  if private.due('daily', interval '1 day') then
    result := result || jsonb_build_object('popularity', private.compute_popularity(),
                                           'monthly_boosts', private.grant_monthly_boosts(),
                                           'metrics_day', private.snapshot_daily_metrics(),
                                           'metrics_purged', private.purge_metrics());
  end if;
  return result;
end;
$$;

-- Pseudonymous id for product analytics (PostHog). Random, never the user id, erased
-- with the account.
alter table public.profiles add column analytics_id uuid not null default gen_random_uuid();

create function public.get_my_analytics_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select analytics_id from public.profiles where id = auth.uid();
$$;

revoke execute on function public.get_my_analytics_id() from public, anon;
grant execute on function public.get_my_analytics_id() to authenticated;
