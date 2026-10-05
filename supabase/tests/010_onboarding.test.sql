-- Phase 2 onboarding RPCs: answers, referral code, photos, selfie, location, completion.
begin;
select plan(26);

select tests.create_onboarded_user('33639982601', 'a7000000-0000-4000-8000-000000000001');
select tests.create_user('33639982602', 'b7000000-0000-4000-8000-000000000002');
-- Fake uploaded files (the app uploads through the Storage API).
insert into storage.objects (bucket_id, name, owner_id) values
  ('photos', 'a7000000-0000-4000-8000-000000000001/1.jpg', 'a7000000-0000-4000-8000-000000000001'),
  ('photos', 'a7000000-0000-4000-8000-000000000001/2.jpg', 'a7000000-0000-4000-8000-000000000001'),
  ('photos', 'a7000000-0000-4000-8000-000000000001/3.jpg', 'a7000000-0000-4000-8000-000000000001'),
  ('photos', 'b7000000-0000-4000-8000-000000000002/1.jpg', 'b7000000-0000-4000-8000-000000000002'),
  ('selfies', 'a7000000-0000-4000-8000-000000000001/selfie.jpg', 'a7000000-0000-4000-8000-000000000001');

select tests.authenticate_as('a7000000-0000-4000-8000-000000000001');

-- Completion is refused while steps are missing ------------------------------------
select throws_ok($$ select public.complete_onboarding() $$, 'P0001', 'onboarding_incomplete:prompts',
  'cannot finish without written answers');

-- Written answers --------------------------------------------------------------------
select throws_ok($$ select public.set_my_prompts('[{"question_code":"green_flag","answer":"a"}]') $$,
  'P0001', 'prompts_exactly_three', 'exactly three answers');
select throws_ok($$ select public.set_my_prompts('[{"question_code":"green_flag","answer":"a"},{"question_code":"green_flag","answer":"b"},{"question_code":"perfect_sunday","answer":"c"}]') $$,
  'P0001', 'prompts_duplicate_question', 'three different questions');
select throws_ok($$ select public.set_my_prompts('[{"question_code":"nope","answer":"a"},{"question_code":"green_flag","answer":"b"},{"question_code":"perfect_sunday","answer":"c"}]') $$,
  'P0001', 'unknown_prompt_question', 'questions come from the list');
select throws_ok(format($$ select public.set_my_prompts('[{"question_code":"makes_me_laugh","answer":"%s"},{"question_code":"green_flag","answer":"b"},{"question_code":"perfect_sunday","answer":"c"}]') $$, repeat('x', 151)),
  'P0001', 'prompt_answer_length', 'answers are limited to 150 characters');
select lives_ok($$ select public.set_my_prompts('[{"question_code":"makes_me_laugh","answer":"Les jeux de mots"},{"question_code":"green_flag","answer":"La ponctualité"},{"question_code":"perfect_sunday","answer":"Marché"}]') $$,
  'valid answers saved');
select results_eq($$ select position::int, question_code from public.profile_prompts order by position $$,
  $$ values (1, 'makes_me_laugh'), (2, 'green_flag'), (3, 'perfect_sunday') $$, 'answers stored in order');

-- Referral code ------------------------------------------------------------------------
select throws_ok($$ select public.set_my_referral_code('a b', false) $$, 'P0001', 'invalid_referral_code',
  'malformed referral code rejected');
select lives_ok($$ select public.set_my_referral_code('ami-2026', true) $$, 'referral code recorded');

-- Photos -------------------------------------------------------------------------------
select throws_ok($$ select public.complete_onboarding() $$, 'P0001', 'onboarding_incomplete:photos',
  'cannot finish without photos');
select throws_ok($$ select public.add_my_photo('a7000000-0000-4000-8000-000000000001/missing.jpg') $$,
  'P0001', 'storage_object_not_found', 'photo must be uploaded first');
select throws_ok($$ select public.add_my_photo('b7000000-0000-4000-8000-000000000002/1.jpg') $$,
  'P0001', 'storage_object_not_found', 'cannot claim someone else''s file');
select lives_ok($$ select public.add_my_photo('a7000000-0000-4000-8000-000000000001/1.jpg') $$, 'first photo added');
select lives_ok($$ select public.add_my_photo('a7000000-0000-4000-8000-000000000001/2.jpg') $$, 'second photo added');
reset role;
update public.app_config set value = '2' where key = 'photos.max_count';
select tests.authenticate_as('a7000000-0000-4000-8000-000000000001');
select throws_ok($$ select public.add_my_photo('a7000000-0000-4000-8000-000000000001/3.jpg') $$,
  'P0001', 'photos_max_reached', 'photo count limited by photos.max_count');

select lives_ok($$ select public.reorder_my_photos(array(select id from public.photos order by position desc)) $$,
  'photos can be reordered');
select is((select storage_path from public.photos where position = 1), 'a7000000-0000-4000-8000-000000000001/2.jpg',
  'new order applied');
select throws_ok($$ select public.reorder_my_photos(array[gen_random_uuid()]) $$, 'P0001', 'photo_order_mismatch',
  'reorder must list exactly the user''s photos');

-- Storage isolation
select is((select count(*)::int from storage.objects where name like 'b7000000%'), 0,
  'a user cannot list another user''s files');

-- Selfie ----------------------------------------------------------------------------------
select throws_ok($$ select public.complete_onboarding() $$, 'P0001', 'onboarding_incomplete:selfie',
  'cannot finish without the verification selfie');
select lives_ok($$ select public.submit_my_selfie('a7000000-0000-4000-8000-000000000001/selfie.jpg') $$, 'selfie submitted');
select is((select verification_status::text from public.profiles), 'pending', 'profile awaits verification');

-- Location (Edge Function only) ------------------------------------------------------------
select throws_ok($$ select public.service_set_location(auth.uid(), 48.85, 2.35, 'device', 'FR') $$, '42501', null,
  'the app cannot set its own location and country');
select throws_ok($$ select public.complete_onboarding() $$, 'P0001', 'onboarding_incomplete:location',
  'cannot finish without a location');
reset role;
set local role service_role;
select public.service_set_location('a7000000-0000-4000-8000-000000000001', 48.85, 2.35, 'device', 'fr');
reset role;

select tests.authenticate_as('a7000000-0000-4000-8000-000000000001');
select lives_ok($$ select public.complete_onboarding() $$, 'onboarding completes when everything is there');
select is((select status::text || ':' || country_code from public.profiles), 'active:FR',
  'profile is active with a server-side country');

select * from finish();
rollback;
