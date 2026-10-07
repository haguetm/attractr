-- Phone for every account, suspended accounts (migration 20261019090000).
begin;
select plan(26);

-- A, B: matched. C: suspended then deleted. E: signed up without a phone (email, Google...).
select tests.create_onboarded_user('3363998600' || n, ('fb000000-0000-4000-8000-00000000000' || n)::uuid,
  case when n % 2 = 1 then 'woman' else 'man' end::public.gender, case when n % 2 = 1 then '{man}' else '{woman}' end::public.gender[])
from generate_series(1, 4) n;
create function pg_temp.u(n int) returns uuid language sql as $$ select ('fb000000-0000-4000-8000-00000000000' || n)::uuid $$;
insert into auth.users (instance_id, id, aud, role, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000', pg_temp.u(5), 'authenticated', 'authenticated', 'e@example.fr', now(),
        '{"provider":"email","providers":["email"]}', '{}', now(), now());

-- Phone: declared number (beta) ----------------------------------------------------------
select tests.authenticate_as(pg_temp.u(5));
select is((public.get_my_profile() ->> 'has_phone')::boolean, false, 'an email account starts without a phone');
select throws_ok($$ select public.set_my_phone('+33612345678') $$, 'P0001', 'phone_verification_required',
  'production requires an SMS-verified number');
reset role;
update public.app_config set value = 'false' where key = 'auth.phone_verification_required';
select tests.authenticate_as(pg_temp.u(5));
select throws_ok($$ select public.set_my_phone('0612345678') $$, 'P0001', 'invalid_phone', 'numbers are sent in E.164');
select lives_ok($$ select public.set_my_phone('+33612345678') $$, 'beta: a declared number is accepted');
select is((public.get_my_profile() ->> 'has_phone')::boolean, true, 'the profile now has a phone');
select tests.authenticate_as(pg_temp.u(1));
select throws_ok($$ select public.set_my_phone('+33612345679') $$, 'P0001', 'phone_already_verified',
  'an SMS-verified number cannot be replaced by a declared one');
reset role;
select is((select digest from private.phone_digests where user_id = pg_temp.u(5)),
  encode(extensions.digest('33612345678', 'sha256'), 'hex'), 'only digests are stored, never the number');

-- The declared number is enough for "bloquer mes contacts"
select tests.authenticate_as(pg_temp.u(2));
select public.block_contacts(array[encode(extensions.digest('33612345678', 'sha256'), 'hex')]);
reset role;
select ok(exists (select 1 from public.blocks where blocker_id = pg_temp.u(2) and blocked_id = pg_temp.u(5) and source = 'contacts'),
  'a contact who signed up by email is blocked through the declared number');

-- A number closed for minority stays refused
insert into private.blocked_identities (phone_hash, reason, expires_at) values (private.phone_hash('33699999999'), 'minor', now() + interval '1 year');
select tests.authenticate_as(pg_temp.u(5));
select throws_ok($$ select public.set_my_phone('+33699999999') $$, 'P0001', 'identity_blocked', 'a minor''s number cannot come back');
reset role;

-- Onboarding needs a phone
update public.profiles set status = 'onboarding', verification_status = 'pending' where id = pg_temp.u(4);
insert into public.photos (user_id, storage_path, position) values
  (pg_temp.u(4), pg_temp.u(4) || '/1.jpg', 1), (pg_temp.u(4), pg_temp.u(4) || '/2.jpg', 2);
insert into public.profile_prompts (user_id, position, question_code, answer) values
  (pg_temp.u(4), 1, 'green_flag', 'a'), (pg_temp.u(4), 2, 'perfect_sunday', 'b'), (pg_temp.u(4), 3, 'simple_pleasure', 'c');
select public.service_set_location(pg_temp.u(4), 48.86, 2.35, 'device', 'FR', '75', '11');
update auth.users set phone = null where id = pg_temp.u(4);
delete from private.phone_digests where user_id = pg_temp.u(4);
select tests.authenticate_as(pg_temp.u(4));
select throws_ok($$ select public.complete_onboarding() $$, 'P0001', 'onboarding_incomplete:phone', 'no phone, no profile');
select public.set_my_phone('+33611111111');
select lives_ok($$ select public.complete_onboarding() $$, 'with a phone the onboarding completes');
reset role;

-- Suspensions: matches on hold, then reopened ------------------------------------------------
insert into public.matches (id, user_a, user_b, matched_drinks, first_message_deadline, created_at)
values ('fb100000-0000-4000-8000-000000000001', least(pg_temp.u(1), pg_temp.u(2)), greatest(pg_temp.u(1), pg_temp.u(2)), '{wine}',
        now() - interval '1 hour', now() - interval '25 hours');
insert into public.conversations (id, kind, match_id) values ('fb200000-0000-4000-8000-000000000001', 'match', 'fb100000-0000-4000-8000-000000000001');
insert into public.conversation_members (conversation_id, user_id) values
  ('fb200000-0000-4000-8000-000000000001', pg_temp.u(1)), ('fb200000-0000-4000-8000-000000000001', pg_temp.u(2));
update public.matches set first_message_deadline = now() + interval '1 hour' where id = 'fb100000-0000-4000-8000-000000000001';

update public.profiles set status = 'suspended' where id = pg_temp.u(1);
select is((select status::text from public.matches where id = 'fb100000-0000-4000-8000-000000000001'), 'on_hold',
  'a suspension puts the matches on hold');
select tests.authenticate_as(pg_temp.u(2));
select is(jsonb_array_length(public.get_my_matches()), 0, 'the other person no longer sees the match');
select throws_ok($$ select public.send_message('fb200000-0000-4000-8000-000000000001', 'Tu es là ?') $$, 'P0001', 'match_closed',
  'and cannot write into the void');
reset role;

select throws_ok($$ select private.mod_lift_suspension('moderateur:test', pg_temp.u(1), 'ok') $$, 'P0001', 'invalid_request',
  'lifting needs a reason');
select throws_ok($$ select private.mod_lift_suspension('moderateur:test', pg_temp.u(2), 'sanction terminée') $$, 'P0001', 'not_suspended',
  'only a suspended account can be lifted');
update public.matches set first_message_deadline = now() - interval '1 minute' where id = 'fb100000-0000-4000-8000-000000000001';
select lives_ok($$ select private.mod_lift_suspension('moderateur:test', pg_temp.u(1), 'sanction terminée') $$, 'lift the suspension');
select is((select status::text from public.matches where id = 'fb100000-0000-4000-8000-000000000001'), 'active', 'the match reopens');
select ok((select first_message_deadline > now() + interval '23 hours' from public.matches where id = 'fb100000-0000-4000-8000-000000000001'),
  'with a fresh window for the first message');
select ok(exists (select 1 from private.access_log where subject_user_id = pg_temp.u(1) and reason like 'suspension lifted:%'),
  'the decision is logged');

-- Both suspended: lifting one keeps the match on hold
update public.profiles set status = 'suspended' where id in (pg_temp.u(1), pg_temp.u(2));
select private.mod_lift_suspension('moderateur:test', pg_temp.u(1), 'sanction terminée');
select is((select status::text from public.matches where id = 'fb100000-0000-4000-8000-000000000001'), 'on_hold',
  'a match stays on hold while the other side is suspended');

-- Deleted while suspended: a trace, and a return goes to review --------------------------------
insert into private.face_templates (user_id, face_id) values (pg_temp.u(3), 'face-of-c');
update public.profiles set status = 'suspended' where id = pg_temp.u(3);
delete from auth.users where id = pg_temp.u(3);
select ok(exists (select 1 from private.blocked_identities where reason = 'suspended' and face_id = 'face-of-c'
                  and phone_hash = private.phone_hash('33639986003')), 'deleting a suspended account leaves a trace');
update public.profiles set status = 'active' where id = pg_temp.u(2);
delete from auth.users where id = pg_temp.u(2);
select is((select count(*)::int from private.blocked_identities where reason = 'suspended'), 1, 'other deletions leave none');

select lives_ok($$ select tests.create_user('33639986003', 'fb000000-0000-4000-8000-000000000006') $$,
  'the number can sign up again (only minors are refused)');
create temp table selfie on commit drop as
  with s as (insert into private.selfie_submissions (user_id, storage_path) values (pg_temp.u(6), pg_temp.u(6) || '/s.jpg') returning id)
  select id from s;
update public.profiles set birth_date = '1990-01-01' where id = pg_temp.u(6);
select is(private.apply_selfie_result((select id from selfie), true, 36, 0.95, 'another-face'), 'review', 'but the selfie goes to review');
select is((select reason || ':' || priority from private.moderation_queue where subject_user_id = pg_temp.u(6)), 'returning_account:1',
  'flagged first as a returning account');

select * from finish();
rollback;
