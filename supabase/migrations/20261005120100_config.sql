-- Runtime configuration. Every value marked "provisoire" in the spec lives here,
-- never hard-coded. Change values with an UPDATE, no redeploy needed.

create table public.app_config (
  key text primary key check (key ~ '^[a-z_]+(\.[a-z_]+)+$'),
  value jsonb not null,
  description text not null,
  -- Public keys are readable by signed-in users (UI limits, labels); others are server-only.
  is_public boolean not null default false,
  updated_at timestamptz not null default now()
);

alter table public.app_config enable row level security;
revoke insert, update, delete, truncate on public.app_config from authenticated;
create policy app_config_read_public on public.app_config
  for select to authenticated using (is_public);

insert into public.app_config (key, value, description, is_public) values
  ('likes.free_quota', '25', 'Likes per rolling window for free users (provisoire).', true),
  ('likes.quota_window_hours', '24', 'Rolling window for the free like quota, in hours.', true),
  ('drinks.change_cooldown_days', '7', 'Minimum days between two drink changes.', true),
  ('profile.bio_max_length', '300', 'Max characters of the individual bio (DECISIONS Q9).', true),
  ('match.first_message_window_hours', '24', 'Time to send the first message after a match.', true),
  ('match.extension_hours', '24', 'Duration of one first-message extension (Q14).', true),
  ('match.max_extensions', '1', 'Free first-message extensions per match (Q14).', true),
  ('feed.pass_recycle_days', '30', 'Days before a passed profile can reappear (Q7).', false),
  ('moderation.misleading_warning_threshold', '3', 'Validated "misleading intent" reports before a warning (Q15).', false),
  ('moderation.misleading_suspension_threshold', '4', 'Validated "misleading intent" reports before suspension (Q15).', false),
  ('activity.badge_window_hours', '72', 'A reply within this window earns the activity badge (Q16).', false),
  ('groups.join_request_expiry_hours', '48', 'Expiry of a pending friends-group join request (Q18).', true),
  ('groups.creator_only_premium', 'true', 'Only the group creator needs Premium (provisoire).', false),
  ('referral.referee_validation_days', '7', 'Days of activity before a referee is validated.', false),
  ('referral.premium_months_per_referee', '1', 'Free months for a Premium referrer per validated referee.', false),
  ('referral.annual_cap_months', '6', 'Max free months a referrer can earn per year.', false),
  ('referral.referee_first_payment_discount_pct', '50', 'Referee discount on first payment when the referrer is not subscribed (provisoire).', false),
  ('referral.non_subscriber_referrer_discount_pct', 'null', 'Discount on the future subscription of a non-subscribed referrer. TO DECIDE before phase 7.', false),
  ('boost.duration_minutes', '30', 'Duration of a boost.', true),
  ('popularity.window_days', '7', 'Rolling window for the popularity indicator (P2).', false),
  ('popularity.high_share', '0.2', 'Top share of the zone labelled "beaucoup de likes" (P2).', false),
  ('popularity.low_share', '0.2', 'Bottom share of the zone labelled "peu de likes" (P2).', false),
  ('popularity.min_profile_age_days', '7', 'No indicator before this profile age (P3).', false),
  ('popularity.min_views', '50', 'No indicator before this many views (P3, value to confirm).', false),
  ('compliance.minor_trace_retention_days', '365', 'Retention of face template + phone hash after closing a minor account (Q22, legal validation pending).', false),
  ('dev.impersonation_enabled', 'false', 'Enables "tester en tant que". Also requires APP_ENV=development; never true in production.', false),
  ('providers.mode', '"mock"', 'External providers implementation: "mock" or "real".', false);

-- Country switches for sensitive fields (spec §12, DECISIONS Q21).
-- Row '*' is the default for countries without a dedicated row.
create table public.country_config (
  country_code text primary key check (country_code = '*' or country_code ~ '^[A-Z]{2}$'),
  orientation_enabled boolean not null default true,
  structure_enabled boolean not null default true,
  composition_enabled boolean not null default true,
  note text
);

alter table public.country_config enable row level security;
revoke insert, update, delete, truncate on public.country_config from authenticated;
create policy country_config_read on public.country_config
  for select to authenticated using (true);

insert into public.country_config (country_code, note) values
  ('*', 'Default. The list of countries where fields must be disabled is pending legal input.'),
  ('FR', 'Test market.');

-- Helpers ------------------------------------------------------------------

create function private.config(p_key text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v jsonb;
begin
  select value into v from public.app_config where key = p_key;
  if not found then
    raise exception 'config_missing: %', p_key;
  end if;
  return v;
end;
$$;

create function private.config_int(p_key text)
returns integer
language plpgsql
stable
set search_path = ''
as $$
declare
  v jsonb := private.config(p_key);
begin
  if jsonb_typeof(v) <> 'number' then
    raise exception 'config_not_a_number: %', p_key;
  end if;
  return v::integer;
end;
$$;

create function private.country_switches(p_country_code text)
returns public.country_config
language sql
stable
security definer
set search_path = ''
as $$
  select c.*
  from public.country_config c
  where c.country_code in (coalesce(p_country_code, '*'), '*')
  order by (c.country_code = '*')  -- the specific row wins over the default
  limit 1;
$$;
