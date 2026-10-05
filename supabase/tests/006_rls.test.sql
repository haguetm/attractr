-- Access rules: a user never reads another user's private rows or sensitive fields.
begin;
select plan(20);

select tests.create_onboarded_user('33639982301', 'a4000000-0000-4000-8000-00000000000a',
  'woman', '{woman}', '{cocktail}', 'polyamorous');
select tests.create_onboarded_user('33639982302', 'b4000000-0000-4000-8000-00000000000b',
  'man', '{woman}', '{wine}', 'monogamous');
insert into public.profile_prompts (user_id, position, question_code, answer)
  values ('a4000000-0000-4000-8000-00000000000a', 1, 'green_flag', 'Réponse privée de A');
select private.write_sensitive('a4000000-0000-4000-8000-00000000000a', '{"orientation":"lesbian","orientation_visible":false}');

-- As B ----------------------------------------------------------------------
select tests.authenticate_as('b4000000-0000-4000-8000-00000000000b');

select is((select count(*)::int from public.profiles), 1, 'B sees only its own profile row');
select is_empty($$ select 1 from public.profiles where id = 'a4000000-0000-4000-8000-00000000000a' $$,
  'B cannot read A''s profile');
select is_empty($$ select 1 from public.profile_drinks where user_id = 'a4000000-0000-4000-8000-00000000000a' $$,
  'B cannot read A''s drinks');
select is_empty($$ select 1 from public.profile_prompts where user_id = 'a4000000-0000-4000-8000-00000000000a' $$,
  'B cannot read A''s written answers');
select is_empty($$ select 1 from public.consents where user_id = 'a4000000-0000-4000-8000-00000000000a' $$,
  'B cannot read A''s consents');

select throws_ok($$ select * from private.profile_sensitive $$, '42501', null,
  'B cannot reach the sensitive table');
select throws_ok($$ select private.read_sensitive('a4000000-0000-4000-8000-00000000000a') $$, '42501', null,
  'B cannot call the decryption function');
select throws_ok($$ select private.admin_read_sensitive('b', 'a4000000-0000-4000-8000-00000000000a', 'curiosity') $$,
  '42501', null, 'B cannot call back-office functions');
select throws_ok($$ select * from private.drink_change_history $$, '42501', null,
  'drink history is reserved to moderation');
select ok(
  not (public.get_my_profile()::text like '%lesbian%' or public.get_my_profile()::text like '%a4000000%'),
  'get_my_profile only returns the caller''s data');

-- Writes on someone else's rows
select lives_ok($$ update public.profiles set bio = 'hacked' where id = 'a4000000-0000-4000-8000-00000000000a' $$,
  'update on A''s row runs but matches nothing');
select throws_ok($$ insert into public.profile_prompts (user_id, position, question_code, answer)
                   values ('a4000000-0000-4000-8000-00000000000a', 2, 'green_flag', 'x') $$,
  '42501', null, 'B cannot write A''s answers');

-- Protected columns of one's own row
select throws_ok($$ update public.profiles set verification_status = 'verified' where id = auth.uid() $$,
  '42501', null, 'a user cannot verify themself');
select throws_ok($$ update public.profiles set status = 'active' where id = auth.uid() $$,
  '42501', null, 'a user cannot change their status directly');
select throws_ok($$ insert into public.profile_drinks (user_id, drink) values (auth.uid(), 'beer') $$,
  '42501', null, 'drinks are only written through set_my_intent');

-- Configuration
select is_empty($$ select 1 from public.app_config where not is_public $$,
  'server-only config keys are hidden');
select throws_ok($$ update public.app_config set value = '1000' where key = 'likes.free_quota' $$,
  '42501', null, 'users cannot change the configuration');

reset role;
select is((select bio from public.profiles where id = 'a4000000-0000-4000-8000-00000000000a'), null,
  'A''s bio is untouched');

-- Anonymous ---------------------------------------------------------------------
set local role anon;
select throws_ok($$ select * from public.profiles $$, '42501', null, 'anon cannot read profiles');
select throws_ok($$ select public.get_my_profile() $$, '42501', null, 'anon cannot call profile RPCs');

select * from finish();
rollback;
