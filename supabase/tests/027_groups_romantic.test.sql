-- Romantic / polyamory groups (spec §8): everyone matched with everyone, 6 max, Premium creator.
begin;
select plan(16);

-- A (woman, Premium), B, C, D (men). All open to explore, wine.
select tests.create_onboarded_user('33639984201', 'f4000000-0000-4000-8000-00000000000a', 'woman', '{man,woman}', '{wine}', 'open_to_explore');
select tests.create_onboarded_user('3363998420' || n, ('f4000000-0000-4000-8000-00000000000' || n)::uuid, 'man', '{woman,man}', '{wine}', 'open_to_explore')
from generate_series(2, 4) n;
create function pg_temp.u(c text) returns uuid language sql as $$
  select ('f4000000-0000-4000-8000-00000000000' || case c when 'A' then 'a' when 'B' then '2' when 'C' then '3' else '4' end)::uuid
$$;
create function pg_temp.match(a text, b text) returns void language sql as $$
  insert into public.matches (user_a, user_b, matched_drinks, first_message_deadline)
  values (least(pg_temp.u(a), pg_temp.u(b)), greatest(pg_temp.u(a), pg_temp.u(b)), '{wine}', now() + interval '1 day')
$$;
select pg_temp.match('A', 'B');
select pg_temp.match('A', 'C');
select pg_temp.match('A', 'D');

select tests.authenticate_as('f4000000-0000-4000-8000-000000000002');
select throws_ok($$ select public.create_group('romantic', 'Trio', 'majority') $$, 'P0001', 'premium_required', 'only Premium users create groups');

reset role;
insert into private.entitlements (user_id, entitlement, source) values (pg_temp.u('A'), 'premium', 'test');
select tests.authenticate_as('f4000000-0000-4000-8000-00000000000a');
create temp table grp on commit drop as select public.create_group('romantic', 'Dimanche à trois', 'majority') as id;
grant select on grp to authenticated;
select isnt_empty($$ select 1 from grp $$, 'A creates a romantic group');

-- B is matched with A (the only member): invited, accepts, joins
create temp table inv on commit drop as select public.invite_to_group((select id from grp), 'f4000000-0000-4000-8000-000000000002') as id;
grant select on inv to authenticated;
select tests.authenticate_as('f4000000-0000-4000-8000-000000000002');
select is(public.get_my_group_invitations() -> 0 ->> 'name', 'Dimanche à trois', 'B sees the invitation');
select is(public.respond_group_invitation((select id from inv), true), 'joined', 'B joins (no vote in romantic groups)');

-- C is matched with A but not with B
select tests.authenticate_as('f4000000-0000-4000-8000-00000000000a');
select throws_ok($$ select public.invite_to_group((select id from grp), 'f4000000-0000-4000-8000-000000000003') $$,
  'P0001', 'must_match_all_members', 'every member must have matched with the newcomer');
select ok(not (public.get_group_invite_candidates((select id from grp)) @> '[{"first_name":"Test"}]'), 'C is not offered as a candidate');
reset role;
select pg_temp.match('B', 'C');
select tests.authenticate_as('f4000000-0000-4000-8000-00000000000a');
truncate inv;
insert into inv select public.invite_to_group((select id from grp), 'f4000000-0000-4000-8000-000000000003');
select tests.authenticate_as('f4000000-0000-4000-8000-000000000003');
select is(public.respond_group_invitation((select id from inv), true), 'joined', 'C joins once matched with A and B');

-- Group chat: members only
select lives_ok(format('select public.send_message(%L, %L)', (select c.id from public.conversations c where c.group_id = (select id from grp)), 'Bonjour à vous deux'),
  'members write in the group');
select tests.authenticate_as('f4000000-0000-4000-8000-000000000004');
select is_empty($$ select 1 from public.messages $$, 'non-members read nothing');
select throws_ok($$ select public.get_group((select id from grp)) $$, 'P0001', 'group_not_found', 'non-members cannot open the group');

-- Size limit
reset role;
update public.app_config set value = '3' where key = 'groups.romantic_max_members';
select pg_temp.match('B', 'D');
select pg_temp.match('C', 'D');
select tests.authenticate_as('f4000000-0000-4000-8000-00000000000a');
select throws_ok($$ select public.invite_to_group((select id from grp), 'f4000000-0000-4000-8000-000000000004') $$,
  'P0001', 'group_full', 'groups.romantic_max_members enforced');
reset role;
update public.app_config set value = '6' where key = 'groups.romantic_max_members';

-- A match ending before acceptance cancels the invitation
select tests.authenticate_as('f4000000-0000-4000-8000-00000000000a');
truncate inv;
insert into inv select public.invite_to_group((select id from grp), 'f4000000-0000-4000-8000-000000000004');
reset role;
update public.matches set status = 'unmatched' where user_a = least(pg_temp.u('C'), pg_temp.u('D')) and user_b = greatest(pg_temp.u('C'), pg_temp.u('D'));
select tests.authenticate_as('f4000000-0000-4000-8000-000000000004');
select is(public.respond_group_invitation((select id from inv), true), 'cancelled', 'rules are checked again when joining');

-- Blocking: the blocker leaves the shared group (Q17)
select tests.authenticate_as('f4000000-0000-4000-8000-000000000003');
select public.block_profile('f4000000-0000-4000-8000-000000000002');
reset role;
select ok(not private.is_group_member((select id from grp), pg_temp.u('C')), 'the blocker leaves the group');
select ok(private.is_group_member((select id from grp), pg_temp.u('B')), 'the blocked member stays');

-- Leaving: the admin role passes on
select tests.authenticate_as('f4000000-0000-4000-8000-00000000000a');
select public.leave_group((select id from grp));
select tests.authenticate_as('f4000000-0000-4000-8000-000000000002');
select ok((public.get_group((select id from grp)) ->> 'is_admin')::boolean, 'the oldest remaining member becomes admin');
select public.leave_group((select id from grp));
reset role;
select is((select status from public.groups where id = (select id from grp)), 'closed', 'an empty group is closed');

select * from finish();
rollback;
