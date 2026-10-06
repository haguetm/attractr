-- Premium features: filters, who liked you, incognito, rewind, passport, statistics.
begin;
select plan(21);

-- V: woman seeking men (Paris). M1..M4 men seeking women in Paris, L in Lyon.
select tests.create_onboarded_user('33639983900', 'e2000000-0000-4000-8000-000000000000', 'woman', '{man}');
select tests.create_onboarded_user('3363998390' || n, ('e2000000-0000-4000-8000-00000000000' || n)::uuid, 'man', '{woman}')
from generate_series(1, 5) n;
create function pg_temp.u(n int) returns uuid language sql as $$ select ('e2000000-0000-4000-8000-00000000000' || n)::uuid $$;
select public.service_set_location(pg_temp.u(n), 48.8566 + n * 0.001, 2.3522, 'device', 'FR', '75', '11') from generate_series(0, 4) n;
select public.service_set_location(pg_temp.u(5), 45.764, 4.8357, 'device', 'FR', '69', '84');
update public.profiles set verification_status = 'verified' where id in (pg_temp.u(1), pg_temp.u(2));
update public.profiles set height_cm = 185, education_level = 'bac_5' where id = pg_temp.u(1);
insert into public.profile_interests (user_id, interest_code) values (pg_temp.u(2), 'climbing');
insert into public.photos (id, user_id, storage_path, position, moderation_status) values
  ('e2100000-0000-4000-8000-000000000000', pg_temp.u(0), pg_temp.u(0) || '/1.jpg', 1, 'approved');
create function pg_temp.feed_has(n int) returns boolean language sql as $$
  select public.get_feed(50) -> 'cards' @> jsonb_build_array(jsonb_build_object('id', pg_temp.u(n)))
$$;
update public.app_config set value = '0' where key = 'feed.min_results';

-- Without Premium
select tests.authenticate_as('e2000000-0000-4000-8000-000000000000');
select throws_ok($$ select public.set_my_search_preferences('radius', 25, 18, 99, null, '{"verified_only": true}') $$,
  'P0001', 'premium_required', 'advanced filters are Premium');
select throws_ok($$ select public.set_my_incognito(true) $$, 'P0001', 'premium_required', 'incognito is Premium');
select throws_ok($$ select public.get_likes_received() $$, 'P0001', 'premium_required', 'who liked you is Premium');
select throws_ok($$ select public.rewind_last_pass() $$, 'P0001', 'premium_required', 'rewind is Premium');
select throws_ok($$ select public.get_my_stats() $$, 'P0001', 'premium_required', 'statistics are Premium');
select ok(not (public.get_feed(50) -> 'cards' -> 0 ? 'popularity'), 'no popularity indicator without Premium');

-- With Premium
reset role;
insert into private.entitlements (user_id, entitlement, source) values (pg_temp.u(0), 'premium', 'test');
select tests.authenticate_as('e2000000-0000-4000-8000-000000000000');
select ok(public.get_feed(50) -> 'cards' -> 0 ? 'popularity', 'Premium cards carry the popularity indicator');
select public.set_my_search_preferences('radius', 25, 18, 99, null, '{"verified_only": true}');
select ok(pg_temp.feed_has(1) and not pg_temp.feed_has(3), '"vérifiés uniquement"');
select public.set_my_search_preferences('radius', 25, 18, 99, null, '{"height_min": 180, "education_levels": ["bac_5"]}');
select ok(pg_temp.feed_has(1) and not pg_temp.feed_has(2), 'height and education filters');
select public.set_my_search_preferences('radius', 25, 18, 99, null, '{"interests": ["climbing"]}');
select ok(pg_temp.feed_has(2) and not pg_temp.feed_has(1), 'interests filter');
select public.set_my_search_preferences('radius', 25, 18, 99, null, '{}');

-- Filters stop applying when Premium ends
reset role;
update public.search_preferences set verified_only = true where user_id = pg_temp.u(0);
delete from private.entitlements where user_id = pg_temp.u(0);
select tests.authenticate_as('e2000000-0000-4000-8000-000000000000');
select ok(pg_temp.feed_has(3), 'Premium filters are ignored once Premium ends');
reset role;
insert into private.entitlements (user_id, entitlement, source) values (pg_temp.u(0), 'premium', 'test');
update public.search_preferences set verified_only = false where user_id = pg_temp.u(0);

-- Incognito: M4 only visible to people he liked
insert into private.entitlements (user_id, entitlement, source) values (pg_temp.u(4), 'premium', 'test');
update public.profiles set incognito = true where id = pg_temp.u(4);
select tests.authenticate_as('e2000000-0000-4000-8000-000000000000');
select ok(not pg_temp.feed_has(4), 'an incognito profile is hidden');
reset role;
insert into private.feed_impressions (viewer_id, target_id) values (pg_temp.u(4), pg_temp.u(0));
select tests.authenticate_as('e2000000-0000-4000-8000-000000000004');
select public.like_profile(pg_temp.u(0), 'photo', 'e2100000-0000-4000-8000-000000000000');
select tests.authenticate_as('e2000000-0000-4000-8000-000000000000');
select ok(pg_temp.feed_has(4), '... but visible to the people he liked');

-- Who liked you: verified likers only
reset role;
insert into private.feed_impressions (viewer_id, target_id) values (pg_temp.u(1), pg_temp.u(0));
select tests.authenticate_as('e2000000-0000-4000-8000-000000000001');
select public.like_profile(pg_temp.u(0), 'photo', 'e2100000-0000-4000-8000-000000000000');
select tests.authenticate_as('e2000000-0000-4000-8000-000000000000');
select ok(public.get_likes_received() @> jsonb_build_array(jsonb_build_object('id', pg_temp.u(1))), 'verified likers are listed');
select ok(not (public.get_likes_received() @> jsonb_build_array(jsonb_build_object('id', pg_temp.u(4)))), 'unverified likers are not');

-- Rewind
select public.pass_profile(pg_temp.u(3));
select ok(not pg_temp.feed_has(3), 'passed profile hidden');
select is(public.rewind_last_pass() ->> 'id', pg_temp.u(3)::text, 'rewind brings back the last passed profile');
select ok(pg_temp.feed_has(3), 'and it is back in the feed');

-- Passport: search around Lyon
reset role;
select public.service_set_passport(pg_temp.u(0), 45.764, 4.8357, 'Lyon');
select tests.authenticate_as('e2000000-0000-4000-8000-000000000000');
select ok(pg_temp.feed_has(5) and not pg_temp.feed_has(1), 'the passport moves the search to another city');
select is(public.get_feed(50) ->> 'passport', 'Lyon', 'the feed says where it searches');
select public.clear_my_passport();

-- Statistics: likes per photo
select is((public.get_my_stats() -> 'photos' -> 0 ->> 'likes')::int, 2, 'likes per photo');

select * from finish();
rollback;
