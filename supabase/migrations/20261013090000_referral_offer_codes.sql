-- Referral, option B (validated 2026-10-06): a subscribed referrer's free month is a
-- store offer code (App Store offer code / Google Play promo code) redeemed at the next
-- renewal. Codes are generated in the stores and loaded by staff into a pool; the server
-- assigns one per earned reward, for the store the referrer subscribes on. The referee's
-- month is still granted directly (private.grant_free_month).

-- Store of each user's subscription, from RevenueCat events.
create table private.user_store (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  store text not null,
  updated_at timestamptz not null default now()
);

create function private.track_user_store()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.app_user_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
     and new.payload ->> 'store' in ('APP_STORE', 'PLAY_STORE')
     and exists (select 1 from public.profiles where id = new.app_user_id::uuid) then
    insert into private.user_store (user_id, store) values (new.app_user_id::uuid, new.payload ->> 'store')
    on conflict (user_id) do update set store = excluded.store, updated_at = now();
  end if;
  return new;
end;
$$;

create trigger revenuecat_events_track_store
  after insert on private.revenuecat_events
  for each row execute function private.track_user_store();

create table private.offer_code_pool (
  code text primary key,
  store text not null check (store in ('APP_STORE', 'PLAY_STORE')),
  kind text not null default 'free_month' check (kind in ('free_month')),
  loaded_at timestamptz not null default now(),
  expires_at timestamptz,
  assigned_to uuid,  -- no FK: a used code stays used after the account is deleted
  assigned_at timestamptz
);

create index offer_code_pool_free_idx on private.offer_code_pool (store, loaded_at) where assigned_at is null;

alter table private.referral_rewards
  add column offer_code text,
  add column store text;

-- Assigns a code to each earned referrer free month. Rewards wait (status 'earned') when
-- the pool is empty or the store is unknown; they are voided if the subscription expires.
create function private.assign_offer_codes()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  w record;
  picked text;
  n integer := 0;
begin
  for w in
    select r.id, r.user_id, s.store
    from private.referral_rewards r
    join private.user_store s on s.user_id = r.user_id
    where r.status = 'earned' and r.kind = 'free_month' and r.role = 'referrer'
    order by r.created_at
    for update of r
  loop
    select code into picked from private.offer_code_pool
    where store = w.store and assigned_at is null and (expires_at is null or expires_at > now() + interval '7 days')
    order by loaded_at limit 1
    for update skip locked;
    exit when picked is null;
    update private.offer_code_pool set assigned_to = w.user_id, assigned_at = now() where code = picked;
    update private.referral_rewards
       set offer_code = picked, store = w.store, status = 'applied', applied_at = now()
     where id = w.id;
    n := n + 1;
  end loop;
  return n;
end;
$$;

-- Staff helper: load codes exported from App Store Connect / Google Play (logged).
create function private.load_offer_codes(p_actor text, p_store text, p_codes text[], p_expires_at timestamptz default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  n integer;
begin
  insert into private.offer_code_pool (code, store, expires_at)
  select distinct btrim(c), p_store, p_expires_at from unnest(p_codes) c where btrim(c) <> ''
  on conflict (code) do nothing;
  get diagnostics n = row_count;
  perform private.log_access(p_actor, null, 'offer_code_pool', 'loaded ' || n || ' ' || p_store || ' codes');
  return n;
end;
$$;

-- The previous application path (RewardsProvider + apply-rewards) is replaced.
drop function public.service_pending_rewards(integer);
drop function public.service_apply_free_month(bigint);

do $$
begin
  -- Nested: cron.job must not be referenced where pg_cron is not installed.
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (select 1 from cron.job where jobname = 'attractr-apply-rewards') then
      perform cron.unschedule('attractr-apply-rewards');
    end if;
  end if;
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
    result := result || jsonb_build_object('referrals', private.process_referrals(),
                                           'offer_codes', private.assign_offer_codes());
  end if;
  if private.due('daily', interval '1 day') then
    result := result || jsonb_build_object('popularity', private.compute_popularity(),
                                           'monthly_boosts', private.grant_monthly_boosts());
  end if;
  return result;
end;
$$;

-- Rewards now carry the offer code and its store for the referrer.
create or replace function public.get_my_referrals()
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
      select jsonb_agg(jsonb_build_object('role', w.role, 'kind', w.kind, 'value', w.value, 'status', w.status,
                                          'offer_code', w.offer_code, 'store', w.store) order by w.created_at desc)
      from private.referral_rewards w where w.user_id = uid), '[]'::jsonb),
    'free_months_this_year', (select coalesce(sum(value), 0) from private.referral_rewards
                              where user_id = uid and role = 'referrer' and kind = 'free_month' and status <> 'void'
                                and created_at > now() - interval '1 year'),
    'annual_cap_months', private.config_int('referral.annual_cap_months')
  );
end;
$$;
