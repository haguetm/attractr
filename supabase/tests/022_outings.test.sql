-- Group outings (spec §7): inside a match, each side invites its friends, friends get a
-- card with no profile access, 3 to 8 participants, private feedback afterwards.
begin;
select plan(21);

-- V and W are matched. F1, F2 are V's friends, G1 is W's friend, X is nobody's friend.
select tests.create_onboarded_user('3363998370' || n, ('d2000000-0000-4000-8000-00000000000' || n)::uuid) from generate_series(1, 6) n;
update public.profiles set verification_status = 'verified' where id::text like 'd2000000-%';
create function pg_temp.u(n int) returns uuid language sql as $$ select ('d2000000-0000-4000-8000-00000000000' || n)::uuid $$;
update public.profiles set first_name = case right(id::text, 1)
  when '1' then 'Vera' when '2' then 'Will' when '3' then 'Fanny' when '4' then 'Fred' when '5' then 'Gael' else 'Xavier' end
where id::text like 'd2000000-%';
insert into public.matches (id, user_a, user_b, first_message_deadline, first_message_at) values
  ('d2100000-0000-4000-8000-000000000001', pg_temp.u(1), pg_temp.u(2), now() + interval '1 day', now());
insert into public.friendships (user_a, user_b, requested_by, status, accepted_at) values
  (least(pg_temp.u(1), pg_temp.u(3)), greatest(pg_temp.u(1), pg_temp.u(3)), pg_temp.u(1), 'accepted', now()),
  (least(pg_temp.u(1), pg_temp.u(4)), greatest(pg_temp.u(1), pg_temp.u(4)), pg_temp.u(1), 'accepted', now()),
  (least(pg_temp.u(2), pg_temp.u(5)), greatest(pg_temp.u(2), pg_temp.u(5)), pg_temp.u(2), 'accepted', now());

select tests.authenticate_as('d2000000-0000-4000-8000-000000000001');
select throws_ok($$ select public.create_outing('d2100000-0000-4000-8000-000000000001', 'Bar du coin', now() - interval '1 hour') $$,
  'P0001', 'outing_in_past', 'an outing is in the future');
create temp table outing on commit drop as
  select public.create_outing('d2100000-0000-4000-8000-000000000001', 'Péniche, quai de la Loire', now() + interval '3 days') as id;
grant select on outing to authenticated;
select isnt_empty($$ select 1 from outing $$, 'an outing is proposed inside the match');
select throws_ok($$ select public.create_outing('d2100000-0000-4000-8000-000000000001', 'Ailleurs', now() + interval '4 days') $$,
  'P0001', 'outing_already_planned', 'one planned outing per match');

-- Each side invites its own friends
select lives_ok($$ select public.invite_to_outing((select id from outing), array['d2000000-0000-4000-8000-000000000003', 'd2000000-0000-4000-8000-000000000004']::uuid[]) $$,
  'V invites her friends');
select throws_ok($$ select public.invite_to_outing((select id from outing), array['d2000000-0000-4000-8000-000000000005']::uuid[]) $$,
  'P0001', 'not_a_friend', 'V cannot invite W''s friends');
select tests.authenticate_as('d2000000-0000-4000-8000-000000000002');
select lives_ok($$ select public.invite_to_outing((select id from outing), array['d2000000-0000-4000-8000-000000000005']::uuid[]) $$,
  'W invites his friend');
select is((public.get_match_outing('d2100000-0000-4000-8000-000000000001') ->> 'participants')::int, 5, 'two matched + three friends');
select ok(not exists (select 1 from jsonb_array_elements(public.get_match_outing('d2100000-0000-4000-8000-000000000001') -> 'invitations') i
                      where not (i ->> 'mine')::boolean and i ->> 'friend_id' is not null), 'the other side''s friends are first names only');

-- Outsiders see nothing
select tests.authenticate_as('d2000000-0000-4000-8000-000000000006');
select throws_ok($$ select public.get_match_outing('d2100000-0000-4000-8000-000000000001') $$, 'P0001', 'match_not_found', 'outsiders cannot read the outing');
select throws_ok($$ select * from public.outings $$, '42501', null, 'outings are not readable directly');
select is(public.get_my_outing_invitations(), '[]'::jsonb, 'no card for people not invited');

-- The friend's card: day, place, time, first names; nothing else
select tests.authenticate_as('d2000000-0000-4000-8000-000000000003');
select is((public.get_my_outing_invitations() -> 0 -> 'matched_first_names'), '["Vera", "Will"]'::jsonb, 'the card shows the two first names');
select ok(not ((public.get_my_outing_invitations() -> 0) ?| array['match_id', 'user_id', 'drinks', 'photos', 'profile']),
  'the card exposes no profile, drink or id');
select throws_ok($$ select public.get_match_outing('d2100000-0000-4000-8000-000000000001') $$, 'P0001', 'match_not_found',
  'friends cannot open the match');
select lives_ok($$ select public.respond_to_outing((select id from outing), true) $$, 'je viens');
select tests.authenticate_as('d2000000-0000-4000-8000-000000000004');
select public.respond_to_outing((select id from outing), false);
select tests.authenticate_as('d2000000-0000-4000-8000-000000000001');
select is((public.get_match_outing('d2100000-0000-4000-8000-000000000001') ->> 'participants')::int, 4, 'declined invitations do not count');

-- Max participants
reset role;
update public.app_config set value = '4' where key = 'outings.max_participants';
select tests.authenticate_as('d2000000-0000-4000-8000-000000000004');
select throws_ok($$ select public.respond_to_outing((select id from outing), true) $$, 'P0001', 'outing_full', 'outings.max_participants enforced');

-- Feedback after the outing, private
select throws_ok($$ select public.give_outing_feedback((select id from outing), 5) $$, 'P0001', 'outing_not_found',
  'only participants give feedback');
reset role;
update public.outings set starts_at = now() - interval '4 hours' where id = (select id from outing);
select is(private.queue_outing_feedback(), 3, 'feedback requested from the pair and the friend who went');
select tests.authenticate_as('d2000000-0000-4000-8000-000000000003');
select lives_ok($$ select public.give_outing_feedback((select id from outing), 4, 'Super soirée') $$, 'private feedback recorded');

-- Ending the match cancels the outing for the friends
reset role;
update public.matches set status = 'unmatched' where id = 'd2100000-0000-4000-8000-000000000001';
select tests.authenticate_as('d2000000-0000-4000-8000-000000000005');
select is(public.get_my_outing_invitations() -> 0 ->> 'status', 'cancelled', 'an ended match cancels its outing');

select * from finish();
rollback;
