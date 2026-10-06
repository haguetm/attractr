-- get_feed: compatibility, exclusions, reciprocity, widening, areas, card content.
-- Seed profiles also live in the database: assertions target specific test users.
begin;
select plan(26);

-- V (viewer): woman seeking men, wine, monogamous, Paris.
select tests.create_onboarded_user('33639982701', 'c0000000-0000-4000-8000-00000000000f', 'woman', '{man}', '{wine}', 'monogamous');
-- A: compatible man, ~3 km away.          B: cocktail (incompatible drink).
-- C: man seeking men (genders).            E: compatible, Lille (~204 km).
-- F: compatible but paused.                H: compatible, Versailles (other département, same région).
select tests.create_onboarded_user('33639982702', 'c0000000-0000-4000-8000-00000000000a', 'man', '{woman}', '{wine}', 'monogamous');
select tests.create_onboarded_user('33639982703', 'c0000000-0000-4000-8000-00000000000b', 'man', '{woman}', '{cocktail}', 'open_to_explore');
select tests.create_onboarded_user('33639982704', 'c0000000-0000-4000-8000-00000000000c', 'man', '{man}', '{wine}', 'monogamous');
select tests.create_onboarded_user('33639982705', 'c0000000-0000-4000-8000-00000000000e', 'man', '{woman}', '{wine}', 'monogamous');
select tests.create_onboarded_user('33639982706', 'c0000000-0000-4000-8000-0000000000f0', 'man', '{woman}', '{wine}', 'monogamous');
select tests.create_onboarded_user('33639982707', 'c0000000-0000-4000-8000-0000000000a1', 'man', '{woman}', '{coffee}', 'monogamous');
select tests.create_onboarded_user('33639982708', 'c0000000-0000-4000-8000-0000000000b1', 'woman', '{man}', '{wine}', 'monogamous', false);

select public.service_set_location('c0000000-0000-4000-8000-00000000000f', 48.8566, 2.3522, 'device', 'FR', '75', '11');
select public.service_set_location('c0000000-0000-4000-8000-00000000000a', 48.8800, 2.3800, 'device', 'FR', '75', '11');
select public.service_set_location('c0000000-0000-4000-8000-00000000000b', 48.8600, 2.3500, 'device', 'FR', '75', '11');
select public.service_set_location('c0000000-0000-4000-8000-00000000000c', 48.8500, 2.3600, 'device', 'FR', '75', '11');
select public.service_set_location('c0000000-0000-4000-8000-00000000000e', 50.6292, 3.0573, 'device', 'FR', '59', '32');
select public.service_set_location('c0000000-0000-4000-8000-0000000000f0', 48.8700, 2.3400, 'device', 'FR', '75', '11');
select public.service_set_location('c0000000-0000-4000-8000-0000000000a1', 48.8049, 2.1204, 'device', 'FR', '78', '11');
update public.profiles set status = 'paused' where id = 'c0000000-0000-4000-8000-0000000000f0';
-- Force widening up to the max radius so Lille is reached.
update public.app_config set value = '50' where key = 'feed.min_results';

-- Only active profiles get a feed
select tests.authenticate_as('c0000000-0000-4000-8000-0000000000b1');
select throws_ok($$ select public.get_feed() $$, 'P0001', 'profile_not_active', 'onboarding profiles have no feed');
select throws_ok($$ select public.set_my_search_preferences('department', null, 18, 99) $$, 'P0001', 'area_unknown',
  'area search needs a known département');

select tests.authenticate_as('c0000000-0000-4000-8000-00000000000f');
create temp table feed on commit drop as select public.get_feed(50) as f;
grant select on feed to authenticated;

select ok((select f -> 'cards' @> '[{"id":"c0000000-0000-4000-8000-00000000000a"}]' from feed), 'compatible nearby profile is shown');
select ok((select not (f -> 'cards' @> '[{"id":"c0000000-0000-4000-8000-00000000000b"}]') from feed), 'incompatible drink is hidden');
select ok((select not (f -> 'cards' @> '[{"id":"c0000000-0000-4000-8000-00000000000c"}]') from feed), 'genders must match both ways');
select ok((select not (f -> 'cards' @> '[{"id":"c0000000-0000-4000-8000-0000000000f0"}]') from feed), 'paused profiles are hidden');
select ok((select f -> 'cards' @> '[{"id":"c0000000-0000-4000-8000-00000000000e"}]' from feed), 'radius widened up to Lille');
select ok((select (f ->> 'widened')::boolean and (f ->> 'radius_km')::int = 300 from feed), 'feed reports the widening');

-- Card content: ranges and public fields only
select is((select c ->> 'distance' from feed, jsonb_array_elements(f -> 'cards') c
           where c ->> 'id' = 'c0000000-0000-4000-8000-00000000000a'), 'lt5', 'distance shown as a range');
select ok((select not (c ?| array['birth_date', 'location', 'phone', 'sensitive', 'seeking_genders',
                                  'structure', 'situation', 'composition', 'country_code'])
           from feed, jsonb_array_elements(f -> 'cards') c
           where c ->> 'id' = 'c0000000-0000-4000-8000-00000000000a'), 'card exposes no private field');
select is((select c -> 'matched_drinks' from feed, jsonb_array_elements(f -> 'cards') c
           where c ->> 'id' = 'c0000000-0000-4000-8000-00000000000a'), '["wine"]'::jsonb, 'card tells which drink matched');

-- Photos become readable for profiles the feed served
select ok(public.can_view_photos_of('c0000000-0000-4000-8000-00000000000a'), 'photos of a served profile are readable');
select ok(not public.can_view_photos_of('c0000000-0000-4000-8000-00000000000b'), 'photos of other profiles are not');

-- Pass and recycle (Q7)
select lives_ok($$ select public.pass_profile('c0000000-0000-4000-8000-00000000000a') $$, 'pass a profile');
select ok(not (public.get_feed(50) -> 'cards' @> '[{"id":"c0000000-0000-4000-8000-00000000000a"}]'), 'passed profile leaves the feed');
reset role;
update public.swipes set created_at = now() - interval '31 days' where target_id = 'c0000000-0000-4000-8000-00000000000a';
select tests.authenticate_as('c0000000-0000-4000-8000-00000000000f');
select ok(public.get_feed(50) -> 'cards' @> '[{"id":"c0000000-0000-4000-8000-00000000000a"}]', 'passed profile returns after feed.pass_recycle_days');
select throws_ok($$ select public.pass_profile(auth.uid()) $$, 'P0001', 'cannot_swipe_self', 'cannot pass oneself');

-- Blocks (both directions) and reports
reset role;
insert into public.blocks (blocker_id, blocked_id) values ('c0000000-0000-4000-8000-00000000000e', 'c0000000-0000-4000-8000-00000000000f');
insert into public.reports (reporter_id, reported_id, reason) values ('c0000000-0000-4000-8000-00000000000f', 'c0000000-0000-4000-8000-00000000000a', 'test');
select tests.authenticate_as('c0000000-0000-4000-8000-00000000000f');
select ok(not (public.get_feed(50) -> 'cards' @> '[{"id":"c0000000-0000-4000-8000-00000000000e"}]'), 'someone who blocked me is hidden');
select ok(not (public.get_feed(50) -> 'cards' @> '[{"id":"c0000000-0000-4000-8000-00000000000a"}]'), 'someone I reported is hidden');

-- Reciprocity (Q6), without widening
reset role;
delete from public.reports;
update public.app_config set value = '0' where key = 'feed.min_results';
insert into public.search_preferences (user_id, radius_km) values ('c0000000-0000-4000-8000-00000000000a', 1);
select tests.authenticate_as('c0000000-0000-4000-8000-00000000000f');
select ok(not (public.get_feed(50) -> 'cards' @> '[{"id":"c0000000-0000-4000-8000-00000000000a"}]'), 'candidate radius is respected');
select ok(not (public.get_feed(50) ->> 'widened')::boolean, 'no widening when enough profiles');
reset role;
update public.search_preferences set radius_km = null, age_min = 40, age_max = 50 where user_id = 'c0000000-0000-4000-8000-00000000000a';
select tests.authenticate_as('c0000000-0000-4000-8000-00000000000f');
select ok(not (public.get_feed(50) -> 'cards' @> '[{"id":"c0000000-0000-4000-8000-00000000000a"}]'), 'candidate age range is respected');

-- Areas: département, then région
select public.set_my_search_preferences('department', null, 18, 99);
select ok(not (public.get_feed(50) -> 'cards' @> '[{"id":"c0000000-0000-4000-8000-0000000000a1"}]'), 'département search excludes other départements');
select public.set_my_search_preferences('region', null, 18, 99);
select ok(public.get_feed(50) -> 'cards' @> '[{"id":"c0000000-0000-4000-8000-0000000000a1"}]', 'région search includes the whole région');
select throws_ok($$ select public.set_my_search_preferences('radius', 1000, 18, 99) $$, 'P0001', 'invalid_radius',
  'radius limited to feed.max_radius_km');
select throws_ok($$ select public.set_my_search_preferences('radius', 25, 30, 20) $$, 'P0001', 'invalid_age_range',
  'age range must be ordered');

select * from finish();
rollback;
