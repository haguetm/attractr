begin;
select plan(17);

-- alice: onboarded (wine, monogamous). bob: fresh account.
select tests.create_onboarded_user('33639982001', 'a1000000-0000-4000-8000-000000000001');
select tests.create_user('33639982002', 'b1000000-0000-4000-8000-000000000002');

-- Age and identity -----------------------------------------------------------
select tests.authenticate_as('b1000000-0000-4000-8000-000000000002');
select throws_ok(
  format($$ select public.set_my_birth_date(%L) $$, (current_date - interval '17 years')::date),
  'P0001', 'underage', 'under 18 is rejected');
select lives_ok(
  format($$ select public.set_my_birth_date(%L) $$, (current_date - interval '18 years')::date),
  'exactly 18 is accepted');
select throws_ok(
  format($$ select public.set_my_birth_date(%L) $$, (current_date - interval '40 years')::date),
  'P0001', 'birth_date_locked', 'birth date cannot change once set');

-- Sensitive writes need the separate consent ------------------------------------
select throws_ok($$ select public.set_my_seeking('{woman}') $$, 'P0001', 'sensitive_consent_required',
  'seeking genders refused without sensitive-data consent');
select throws_ok($$ select public.set_my_intent('single', '{beer}') $$, 'P0001', 'sensitive_consent_required',
  'intent refused without sensitive-data consent');
select public.grant_consent('sensitive_data', 1);
select throws_ok($$ select public.set_my_seeking('{}') $$, 'P0001', 'seeking_genders_required',
  'at least one sought gender');
select lives_ok($$ select public.set_my_seeking('{woman}') $$, 'seeking genders saved');
select is((public.get_my_profile() -> 'sensitive' -> 'friend_genders'), '["woman", "man", "non_binary"]'::jsonb,
  'friend genders default to everyone (Q2)');
select throws_ok($$ select public.set_my_intent('closed_couple', '{beer,wine}', 'monogamous') $$,
  'P0001', 'closed_couple_beer_only', 'RPC enforces the intent rules');

-- Drink change cooldown (spec §1, Q12) ------------------------------------------
select tests.authenticate_as('a1000000-0000-4000-8000-000000000001');
select lives_ok($$ select public.set_my_intent('single', '{coffee}', 'open_to_explore') $$,
  'first change after onboarding is allowed');
select throws_ok($$ select public.set_my_intent('single', '{cocktail}', 'open_to_explore') $$,
  'P0001', 'drink_change_cooldown', 'second change within 7 days is refused');
select lives_ok($$ select public.set_my_intent('single', '{coffee}', 'polyamorous', '{"kinds":["one_any"]}') $$,
  'same drinks with another structure is not a drink change');

reset role;
update public.profiles set drinks_changed_at = now() - interval '8 days' where id = 'a1000000-0000-4000-8000-000000000001';
select tests.authenticate_as('a1000000-0000-4000-8000-000000000001');
select lives_ok($$ select public.set_my_intent('single', '{beer,coffee}', 'polyamorous') $$,
  'change allowed again after 7 days');
reset role;
select is(
  (select array_agg(reason order by id) from private.drink_change_history where user_id = 'a1000000-0000-4000-8000-000000000001'),
  array['initial', 'user', 'user'], 'private history records every drink change');

-- Orientation and bio ----------------------------------------------------------
select tests.authenticate_as('a1000000-0000-4000-8000-000000000001');
select throws_ok($$ select public.set_my_orientation('not_a_label', true) $$, 'P0001', 'unknown_orientation_label',
  'orientation label must come from the list');
select throws_ok($$ update public.profiles set bio = repeat('a', 301) where id = auth.uid() $$, 'P0001', 'bio_too_long',
  'bio limited to profile.bio_max_length');

reset role;
insert into public.country_config (country_code, orientation_enabled) values ('XX', false);
update public.profiles set country_code = 'XX' where id = 'a1000000-0000-4000-8000-000000000001';
select tests.authenticate_as('a1000000-0000-4000-8000-000000000001');
select throws_ok($$ select public.set_my_orientation('queer', true) $$, 'P0001', 'orientation_disabled_in_country',
  'orientation can be disabled per country');

select * from finish();
rollback;
