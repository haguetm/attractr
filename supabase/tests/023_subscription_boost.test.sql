-- RevenueCat events, Premium status, boosts (spec §10).
begin;
select plan(18);

select tests.create_onboarded_user('3363998380' || n, ('e1000000-0000-4000-8000-00000000000' || n)::uuid, 'woman', '{man}')
from generate_series(1, 2) n;
select tests.create_onboarded_user('33639983803', 'e1000000-0000-4000-8000-000000000003', 'man', '{woman}');
select tests.create_onboarded_user('33639983804', 'e1000000-0000-4000-8000-000000000004', 'man', '{woman}');
-- Same place for everyone (feed ordering checks).
select public.service_set_location(id, 48.8566, 2.3522, 'device', 'FR', '75', '11') from public.profiles where id::text like 'e1000000-%';

create function pg_temp.event(p_id text, p_type text, p_user text, p_product text default 'premium_monthly', p_expires interval default interval '30 days')
returns jsonb language sql as $$
  select jsonb_build_object('id', p_id, 'type', p_type, 'app_user_id', p_user, 'product_id', p_product,
    -- floor: a rounded-up millisecond would put the purchase a little in the future.
    'purchased_at_ms', floor(extract(epoch from now()) * 1000)::bigint,
    'expiration_at_ms', (extract(epoch from now() + p_expires) * 1000)::bigint)
$$;

-- Subscription lifecycle
select is(private.apply_revenuecat_event(pg_temp.event('ev1', 'INITIAL_PURCHASE', 'e1000000-0000-4000-8000-000000000001')), 'premium_active',
  'a purchase activates Premium');
select ok(private.is_premium('e1000000-0000-4000-8000-000000000001') and private.is_paying_subscriber('e1000000-0000-4000-8000-000000000001'),
  'the user is a paying Premium subscriber');
select is(private.apply_revenuecat_event(pg_temp.event('ev1', 'INITIAL_PURCHASE', 'e1000000-0000-4000-8000-000000000001')), 'duplicate',
  'webhook retries are idempotent');
select is(private.apply_revenuecat_event(pg_temp.event('ev2', 'INITIAL_PURCHASE', '$RCAnonymousID:abc')), 'unknown_user',
  'anonymous RevenueCat ids are ignored');
select is(private.apply_revenuecat_event(pg_temp.event('ev3', 'CANCELLATION', 'e1000000-0000-4000-8000-000000000001')), 'recorded',
  'a cancellation keeps Premium until the period ends');
select ok(private.is_premium('e1000000-0000-4000-8000-000000000001'), 'still Premium after cancelling');
select is(private.apply_revenuecat_event(pg_temp.event('ev4', 'EXPIRATION', 'e1000000-0000-4000-8000-000000000001')), 'premium_expired',
  'expiration ends Premium');
select ok(not private.is_premium('e1000000-0000-4000-8000-000000000001'), 'no longer Premium');

-- Boosts
select tests.authenticate_as('e1000000-0000-4000-8000-000000000003');
select throws_ok($$ select public.activate_boost() $$, 'P0001', 'no_boost_credit', 'a boost needs a credit');
reset role;
select is(private.apply_revenuecat_event(pg_temp.event('ev5', 'NON_RENEWING_PURCHASE', 'e1000000-0000-4000-8000-000000000003', 'boost_single')),
  'boost_credited', 'buying a boost adds a credit');
select tests.authenticate_as('e1000000-0000-4000-8000-000000000003');
select lives_ok($$ select public.activate_boost() $$, 'the boost starts');
select throws_ok($$ select public.activate_boost() $$, 'P0001', 'boost_already_active', 'one boost at a time');
select ok((public.get_my_boost() -> 'last' ->> 'ends_at')::timestamptz between now() + interval '29 minutes' and now() + interval '31 minutes',
  'a boost lasts boost.duration_minutes');

-- Boosted profiles come first in the zone
select tests.authenticate_as('e1000000-0000-4000-8000-000000000002');
select is(public.get_feed(50) -> 'cards' -> 0 ->> 'id', 'e1000000-0000-4000-8000-000000000003', 'the boosted profile is shown first');
select tests.authenticate_as('e1000000-0000-4000-8000-000000000003');
select is((public.get_my_boost() -> 'last' ->> 'views')::int, 1, 'the boost reports the views obtained');

-- One free boost per month for Premium users
reset role;
insert into private.entitlements (user_id, entitlement, source) values ('e1000000-0000-4000-8000-000000000004', 'premium', 'test');
select is(private.grant_monthly_boosts(), 1, 'Premium users get their monthly boost');
select is(private.grant_monthly_boosts(), 0, 'only once per month');
select tests.authenticate_as('e1000000-0000-4000-8000-000000000004');
select is((public.get_my_profile() ->> 'boost_credits')::int, 1, 'the credit is visible in the profile');

select * from finish();
rollback;
