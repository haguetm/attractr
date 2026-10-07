-- Hardening before the beta (migration 20261018090000): photo access in Storage, birth
-- date lock, selfie results, contact blocks, RevenueCat environments, couple erasure,
-- written answers.
begin;
select plan(24);

-- A: viewer. B, C: men in A's group (C only invited). D: outsider. E, F: a couple.
select tests.create_onboarded_user('3363998500' || n, ('fa000000-0000-4000-8000-00000000000' || n)::uuid,
  case when n = 1 then 'woman' else 'man' end::public.gender, case when n = 1 then '{man}' else '{woman}' end::public.gender[])
from generate_series(1, 6) n;
create function pg_temp.u(n int) returns uuid language sql as $$ select ('fa000000-0000-4000-8000-00000000000' || n)::uuid $$;
create function pg_temp.path(n int, f text) returns text language sql as $$ select pg_temp.u(n)::text || '/' || f $$;

insert into public.photos (user_id, storage_path, position, moderation_status) values
  (pg_temp.u(2), pg_temp.path(2, 'main.jpg'), 1, 'approved'),
  (pg_temp.u(2), pg_temp.path(2, 'second.jpg'), 2, 'approved'),
  (pg_temp.u(2), pg_temp.path(2, 'pending.jpg'), 3, 'pending'),
  (pg_temp.u(3), pg_temp.path(3, 'main.jpg'), 1, 'approved');
insert into storage.objects (bucket_id, name, owner_id)
select 'photos', storage_path, user_id::text from public.photos where user_id in (pg_temp.u(2), pg_temp.u(3));

insert into public.groups (id, kind, name, created_by, admin_id)
values ('fa100000-0000-4000-8000-000000000001', 'friends', 'Les potes', pg_temp.u(1), pg_temp.u(1));
insert into public.conversations (kind, group_id) values ('group', 'fa100000-0000-4000-8000-000000000001');
insert into public.group_members (group_id, user_id) values
  ('fa100000-0000-4000-8000-000000000001', pg_temp.u(1)), ('fa100000-0000-4000-8000-000000000001', pg_temp.u(2));
insert into public.group_invitations (group_id, invitee_id, invited_by, expires_at)
values ('fa100000-0000-4000-8000-000000000001', pg_temp.u(3), pg_temp.u(1), now() + interval '7 days');

create function pg_temp.visible(p_name text) returns boolean language sql as $$
  select exists (select 1 from storage.objects where bucket_id = 'photos' and name = p_name)
$$;
grant execute on function pg_temp.visible(text) to authenticated;

-- Photos in Storage
select tests.authenticate_as(pg_temp.u(1));
select ok(pg_temp.visible(pg_temp.path(2, 'main.jpg')), 'a group member sees another member''s main photo');
select ok(not pg_temp.visible(pg_temp.path(2, 'second.jpg')), '... but not their other photos');
select ok(pg_temp.visible(pg_temp.path(3, 'main.jpg')), 'members see a pending invitee''s main photo');
select lives_ok($$ select public.get_group('fa100000-0000-4000-8000-000000000001') $$, 'opening the group');
select throws_ok(format('select public.like_profile(%L, %L, %L)', pg_temp.u(2), 'photo', (select id from public.photos where storage_path = pg_temp.path(2, 'main.jpg'))),
  'P0001', 'profile_unavailable', 'does not let members like each other''s profile');
select tests.authenticate_as(pg_temp.u(4));
select ok(not pg_temp.visible(pg_temp.path(2, 'main.jpg')), 'an outsider sees nothing');
reset role;
insert into private.feed_impressions (viewer_id, target_id) values (pg_temp.u(4), pg_temp.u(2));
select tests.authenticate_as(pg_temp.u(4));
select ok(pg_temp.visible(pg_temp.path(2, 'second.jpg')), 'the feed shows all approved photos of a served profile');
select ok(not pg_temp.visible(pg_temp.path(2, 'pending.jpg')), '... never one awaiting moderation');
select tests.authenticate_as(pg_temp.u(2));
select ok(pg_temp.visible(pg_temp.path(2, 'pending.jpg')), 'the owner sees all their photos');

-- Birth date lock
select tests.authenticate_as(pg_temp.u(1));
select throws_ok($$ select public.set_my_birth_date(null) $$, 'P0001', 'invalid_request', 'the birth date cannot be erased');
select throws_ok($$ select public.set_my_birth_date('1990-01-01') $$, 'P0001', 'birth_date_locked', '... nor changed');

-- Written answers only go through set_my_prompts
select throws_ok($$ insert into public.profile_prompts (user_id, position, question_code, answer)
                    values (auth.uid(), 1, 'green_flag', 'x') $$, '42501', null, 'no direct write on written answers');

-- Contact blocks: no answer tells whether a number has an account
select lives_ok($$ select public.block_contacts(array[encode(extensions.digest('33600000999', 'sha256'), 'hex')]) $$,
  'block contacts that are not on the app');
select is((public.get_my_blocks() ->> 'contacts_blocked')::boolean, true, 'the answer only says the user asked for it');
select throws_ok($$ select public.block_contacts(array['00']) $$, 'P0001', 'contacts_block_cooldown', 'one run per cooldown');
select public.unblock_contacts();
select throws_ok($$ select public.block_contacts(array['00']) $$, 'P0001', 'contacts_block_cooldown', 'unblocking does not reset it');
reset role;

-- Selfie results: an incomplete answer is never verified
create temp table selfie on commit drop as
  with s as (insert into private.selfie_submissions (user_id, storage_path) values (pg_temp.u(4), pg_temp.path(4, 's.jpg')) returning id)
  select id from s;
select is(private.apply_selfie_result((select id from selfie), true, null, null, null), 'review', 'missing age, confidence or face: human review');
select is((select verification_status::text from public.profiles where id = pg_temp.u(4)), 'pending', 'the profile is not verified');

-- RevenueCat: sandbox / test store events change nothing unless allowed
create function pg_temp.event(id text, env text) returns jsonb language sql as $$
  select jsonb_build_object('id', id, 'type', 'INITIAL_PURCHASE', 'app_user_id', pg_temp.u(1)::text, 'environment', env,
                            'product_id', 'premium_monthly', 'expiration_at_ms', (extract(epoch from now() + interval '30 days') * 1000)::bigint)
$$;
select is(private.apply_revenuecat_event(pg_temp.event('fa-ev1', 'SANDBOX')), 'ignored_environment', 'sandbox events are ignored by default');
select ok(not private.is_premium(pg_temp.u(1)), 'and grant nothing');
update public.app_config set value = '["PRODUCTION", "SANDBOX"]' where key = 'revenuecat.allowed_environments';
select is(private.apply_revenuecat_event(pg_temp.event('fa-ev2', 'SANDBOX')), 'premium_active', 'the beta can allow them');
select ok(private.is_premium(pg_temp.u(1)), 'then they grant Premium');

-- Couple erasure takes the couple's photos with it
create temp table cpl on commit drop as select private.create_couple(pg_temp.u(5), pg_temp.u(6)) as id;
insert into public.photos (user_id, storage_path, position, moderation_status)
select id, id::text || '/shared.jpg', 1, 'approved' from cpl;
delete from auth.users where id = pg_temp.u(5);
select ok(not exists (select 1 from public.profiles where id = (select id from cpl)), 'a partner''s deletion erases the couple');
select ok(exists (select 1 from private.storage_cleanup where bucket = 'photos' and path = (select id::text || '/shared.jpg' from cpl)),
  'and queues its photos for deletion');

select * from finish();
rollback;
