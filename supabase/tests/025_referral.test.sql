-- Referral (spec §9): anonymous statuses, validation after 7 days and a verified selfie,
-- rewards depending on whether the referrer pays, annual cap, anti-abuse, friendship.
begin;
select plan(17);

-- P: paying referrer. N: non-paying referrer. R1..R3 referees. S: self-referral.
select tests.create_onboarded_user('3363998400' || n, ('e3000000-0000-4000-8000-00000000000' || n)::uuid) from generate_series(1, 6) n;
create function pg_temp.u(n int) returns uuid language sql as $$ select ('e3000000-0000-4000-8000-00000000000' || n)::uuid $$;
update public.profiles set verification_status = 'verified' where id::text like 'e3000000-%';
insert into private.entitlements (user_id, entitlement, source, expires_at) values (pg_temp.u(1), 'premium', 'revenuecat', now() + interval '20 days');
insert into public.referral_codes (user_id, code) values (pg_temp.u(1), 'PARRAIN1'), (pg_temp.u(2), 'PARRAIN2'), (pg_temp.u(6), 'MOIMEME6');
insert into private.signup_referrals (user_id, code, befriend_referrer) values
  (pg_temp.u(3), 'PARRAIN1', true), (pg_temp.u(4), 'PARRAIN2', false), (pg_temp.u(5), 'INCONNU9', false), (pg_temp.u(6), 'MOIMEME6', false);

-- Linking
select is(private.process_referrals() ->> 'linked', '4', 'signup codes are linked');
select is((select reject_reason from private.referrals where referee_id = pg_temp.u(5)), 'unknown_code', 'unknown codes are rejected');
select is((select reject_reason from private.referrals where referee_id = pg_temp.u(6)), 'self_referral', 'self-referral is refused');
select is(private.process_referrals() ->> 'validated', '0', 'not validated before 7 days');

-- The referrer only sees statuses
select tests.authenticate_as('e3000000-0000-4000-8000-000000000001');
select is(public.get_my_referrals() -> 'referrals' -> 0 ->> 'status', 'verified', '"inscrit et vérifié"');
select ok(not (public.get_my_referrals()::text like '%e3000000-0000-4000-8000-000000000003%'), 'never who');
select throws_ok($$ select * from private.referrals $$, '42501', null, 'referral rows are server-only');

-- Validation after 7 days
reset role;
update public.profiles set created_at = now() - interval '8 days' where id in (pg_temp.u(3), pg_temp.u(4));
select is(private.process_referrals() ->> 'validated', '2', 'referees validated after 7 days with a verified selfie');

-- Paying referrer: a free month to apply store-side; referee: a month right away
select is((select kind || ':' || status from private.referral_rewards where user_id = pg_temp.u(1)), 'free_month:earned',
  'the paying referrer earns a free month');
select ok(private.is_premium(pg_temp.u(3)) and not private.is_paying_subscriber(pg_temp.u(3)), 'the referee gets a free Premium month');
select ok(private.are_friends(pg_temp.u(1), pg_temp.u(3)), '"devenir ami de mon parrain"');

-- Non-paying referrer: discounts only, never a free subscription
select is((select string_agg(role || ':' || kind || ':' || value, ',' order by role) from private.referral_rewards where referral_id =
           (select id from private.referrals where referee_id = pg_temp.u(4))), 'referee:discount:50,referrer:discount:10',
  'non-paying referrer: 10 % for them, 50 % on the referee''s first payment');
select ok(not private.is_premium(pg_temp.u(2)), 'no free subscription for a non-paying referrer');

-- Applying the free month (mock provider path)
set local role service_role;
select public.service_apply_free_month((select id from public.service_pending_rewards() where user_id = pg_temp.u(1)));
reset role;
select ok((select expires_at from private.entitlements where user_id = pg_temp.u(1) and source = 'referral')
          > now() + interval '49 days', 'the free month is added after the paid period');

-- First payment uses the referee's discount
select private.apply_revenuecat_event(jsonb_build_object('id', 'evr1', 'type', 'INITIAL_PURCHASE', 'app_user_id', pg_temp.u(4)::text,
  'product_id', 'premium_monthly', 'expiration_at_ms', (extract(epoch from now() + interval '30 days') * 1000)::bigint));
select is((select status from private.referral_rewards where user_id = pg_temp.u(4)), 'applied', 'the discount is used on the first payment');

-- Annual cap
update public.app_config set value = '1' where key = 'referral.annual_cap_months';
insert into private.signup_referrals (user_id, code) values (pg_temp.u(2), 'PARRAIN1');
update public.profiles set created_at = now() - interval '8 days' where id = pg_temp.u(2);
select private.process_referrals();
select is((select count(*)::int from private.referral_rewards where user_id = pg_temp.u(1) and role = 'referrer'), 1,
  'no more free months beyond the annual cap');

-- Earned months stop with the referrer's subscription
update private.referral_rewards set status = 'earned' where user_id = pg_temp.u(1);
select private.apply_revenuecat_event(jsonb_build_object('id', 'evr2', 'type', 'EXPIRATION', 'app_user_id', pg_temp.u(1)::text));
select is((select status from private.referral_rewards where user_id = pg_temp.u(1)), 'void', 'unapplied months stop with the subscription');

select * from finish();
rollback;
