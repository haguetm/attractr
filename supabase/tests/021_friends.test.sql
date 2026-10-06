-- Friends (spec §7): link or pseudo, both sides accept, verified only, 10 max, private list.
begin;
select plan(20);

-- A, B, C verified; U unverified.
select tests.create_onboarded_user('3363998360' || n, ('d1000000-0000-4000-8000-00000000000' || n)::uuid) from generate_series(1, 4) n;
update public.profiles set verification_status = 'verified' where id::text like 'd1000000-%' and id <> 'd1000000-0000-4000-8000-000000000004';
update public.profiles set username = 'bob_' || right(id::text, 1) where id::text like 'd1000000-%';

-- Pseudo
select tests.authenticate_as('d1000000-0000-4000-8000-000000000001');
select throws_ok($$ select public.set_my_username('A') $$, 'P0001', 'invalid_username', 'pseudo format checked');
select throws_ok($$ select public.set_my_username('bob_2') $$, 'P0001', 'username_taken', 'pseudo unique');
select lives_ok($$ select public.set_my_username('alice.75') $$, 'pseudo set');

-- Request by pseudo, then acceptance
select lives_ok($$ select public.request_friend_by_username('BOB_2') $$, 'request by pseudo (case-insensitive)');
select is((public.get_my_friends() -> 'outgoing' -> 0 ->> 'first_name'), 'Test', 'the request appears as sent');
select throws_ok($$ select public.request_friend_by_username('bob_4') $$, 'P0001', 'friend_unavailable', 'unverified accounts cannot be added');
select throws_ok($$ select public.request_friend_by_username('nobody') $$, 'P0001', 'friend_unavailable', 'unknown pseudo, same answer');
select throws_ok($$ select public.request_friend_by_username('alice.75') $$, 'P0001', 'cannot_befriend_self', 'not oneself');

select tests.authenticate_as('d1000000-0000-4000-8000-000000000002');
select is(jsonb_array_length(public.get_my_friends() -> 'incoming'), 1, 'B sees the incoming request');
select lives_ok($$ select public.respond_friend_request('d1000000-0000-4000-8000-000000000001', true) $$, 'B accepts');
select is(jsonb_array_length(public.get_my_friends() -> 'friends'), 1, 'they are friends');

-- Privacy: C sees nothing of A and B's friendship
select tests.authenticate_as('d1000000-0000-4000-8000-000000000003');
select is_empty($$ select 1 from public.friendships $$, 'a friend list is private');
select throws_ok($$ insert into public.friendships (user_a, user_b, requested_by) values ('d1000000-0000-4000-8000-000000000001', auth.uid(), auth.uid()) $$,
  '42501', null, 'friendships are only written through RPCs');

-- Link: single use, sharing it is the owner's acceptance
select tests.authenticate_as('d1000000-0000-4000-8000-000000000001');
create temp table invite on commit drop as select public.create_friend_invite() as code;
grant select on invite to authenticated;
select tests.authenticate_as('d1000000-0000-4000-8000-000000000003');
select is(public.preview_friend_invite((select code from invite)) ->> 'first_name', 'Test', 'the link shows the owner''s first name only');
select lives_ok($$ select public.accept_friend_invite((select code from invite)) $$, 'opening the link creates the friendship');
select throws_ok($$ select public.accept_friend_invite((select code from invite)) $$, 'P0001', 'invite_invalid', 'a link works once');

-- Limit
reset role;
update public.app_config set value = '2' where key = 'friends.max';
select tests.authenticate_as('d1000000-0000-4000-8000-000000000001');
select is((public.get_my_friends() -> 'friends')::text like '%bob_2%' and (public.get_my_friends() -> 'friends')::text like '%bob_3%', true,
  'A has two friends');
reset role;
update public.profiles set verification_status = 'verified' where id = 'd1000000-0000-4000-8000-000000000004';
select tests.authenticate_as('d1000000-0000-4000-8000-000000000001');
select throws_ok($$ select public.request_friend_by_username('bob_4') $$, 'P0001', 'friend_limit_reached', 'friends.max is enforced');

-- Removing and blocking end the friendship
select lives_ok($$ select public.remove_friend('d1000000-0000-4000-8000-000000000003') $$, 'remove a friend');
select public.block_profile('d1000000-0000-4000-8000-000000000002');
select is(jsonb_array_length(public.get_my_friends() -> 'friends'), 0, 'blocking ends the friendship');

select * from finish();
rollback;
