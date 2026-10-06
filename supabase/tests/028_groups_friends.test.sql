-- Friends groups (spec §8): Bière match to invite, group approval (majority or admin),
-- limited visibility before joining.
begin;
select plan(16);

-- V (Premium, creator), W, Y, Z, X. Beer for all; X also wine.
select tests.create_onboarded_user('3363998430' || n, ('f5000000-0000-4000-8000-00000000000' || n)::uuid, 'woman', '{man}', '{beer}', null)
from generate_series(1, 4) n;
select tests.create_onboarded_user('33639984305', 'f5000000-0000-4000-8000-000000000005', 'man', '{woman}', '{wine}', 'monogamous');
create function pg_temp.u(n int) returns uuid language sql as $$ select ('f5000000-0000-4000-8000-00000000000' || n)::uuid $$;
update public.profiles set first_name = case right(id::text, 1) when '1' then 'Vera' when '2' then 'Wanda' when '3' then 'Yael' when '4' then 'Zoe' else 'Xavier' end
where id::text like 'f5000000-%';
create function pg_temp.match(a int, b int, drinks text) returns void language sql as $$
  insert into public.matches (user_a, user_b, matched_drinks, first_message_deadline)
  values (least(pg_temp.u(a), pg_temp.u(b)), greatest(pg_temp.u(a), pg_temp.u(b)), drinks::public.drink[], now() + interval '1 day')
$$;
select pg_temp.match(1, 2, '{beer}');
select pg_temp.match(2, 3, '{beer}');
select pg_temp.match(3, 4, '{beer}');
select pg_temp.match(1, 5, '{wine}');
insert into private.entitlements (user_id, entitlement, source) values (pg_temp.u(1), 'premium', 'test');

select tests.authenticate_as('f5000000-0000-4000-8000-000000000005');
reset role;
insert into private.entitlements (user_id, entitlement, source) values (pg_temp.u(5), 'premium', 'test');
select tests.authenticate_as('f5000000-0000-4000-8000-000000000005');
select throws_ok($$ select public.create_group('friends', 'Les potes', 'majority') $$, 'P0001', 'beer_required', 'friends groups need the Bière');

select tests.authenticate_as('f5000000-0000-4000-8000-000000000001');
create temp table grp on commit drop as select public.create_group('friends', 'Les potes du jeudi', 'majority') as id;
create temp table inv (id uuid) on commit drop;
grant select, insert, delete on grp, inv to authenticated;
select throws_ok(format('select public.invite_to_group(%L, %L)', (select id from grp), pg_temp.u(5)), 'P0001', 'beer_match_required',
  'only a Bière match can be invited');

-- V alone: her own vote is a majority
insert into inv select public.invite_to_group((select id from grp), pg_temp.u(2));
select tests.authenticate_as('f5000000-0000-4000-8000-000000000002');
select is(public.respond_group_invitation((select id from inv), true), 'joined', 'Wanda joins');

-- W invites Y: V must approve too (strict majority of 2)
delete from inv;
insert into inv select public.invite_to_group((select id from grp), pg_temp.u(3));
select tests.authenticate_as('f5000000-0000-4000-8000-000000000003');
select is(public.get_my_group_invitations() -> 0 -> 'member_first_names', '["Vera", "Wanda"]'::jsonb, 'the newcomer sees the first names');
select is((public.get_my_group_invitations() -> 0 ->> 'size')::int, 2, '... and the size of the group');
select ok(public.get_my_group_invitations() -> 0 -> 'invited_by' ->> 'match_id' is not null, '... and can open the inviter''s profile (their match)');
select ok(not (public.get_my_group_invitations()::text ~ '"(drinks|photos|bio|prompts)"'), '... but nothing else about the members');
select is(public.respond_group_invitation((select id from inv), true), 'waiting_for_group', 'accepting waits for the group');

select tests.authenticate_as('f5000000-0000-4000-8000-000000000001');
select is(
  (select jsonb_object_keys_agg from (select jsonb_agg(k order by k) as jsonb_object_keys_agg
   from jsonb_object_keys(public.get_group((select id from grp)) -> 'invitations' -> 0) k) x),
  '["can_vote", "first_name", "group_approved", "id", "invited_by", "invitee_accepted", "my_vote", "photo_path"]'::jsonb,
  'members see the newcomer''s first name and main photo only');
select public.vote_group_invitation((select id from inv), true);
reset role;
select ok(private.is_group_member((select id from grp), pg_temp.u(3)), 'a majority of members approved: Yael joins');

-- Rejection by the majority
select tests.authenticate_as('f5000000-0000-4000-8000-000000000003');
delete from inv;
insert into inv select public.invite_to_group((select id from grp), pg_temp.u(4));
select tests.authenticate_as('f5000000-0000-4000-8000-000000000001');
select public.vote_group_invitation((select id from inv), false);
select tests.authenticate_as('f5000000-0000-4000-8000-000000000002');
select public.vote_group_invitation((select id from inv), false);
reset role;
select is((select status from public.group_invitations where id = (select id from inv)), 'rejected', 'the majority can refuse');
select ok(not private.is_group_member((select id from grp), pg_temp.u(4)), 'Zoe does not join');

-- Admin mode: only the admin decides
select tests.authenticate_as('f5000000-0000-4000-8000-000000000001');
create temp table grp2 on commit drop as select public.create_group('friends', 'Escalade', 'admin') as id;
grant select on grp2 to authenticated;
delete from inv;
insert into inv select public.invite_to_group((select id from grp2), pg_temp.u(2));
select tests.authenticate_as('f5000000-0000-4000-8000-000000000002');
select public.respond_group_invitation((select id from inv), true);
delete from inv;
insert into inv select public.invite_to_group((select id from grp2), pg_temp.u(3));
select throws_ok($$ select public.vote_group_invitation((select id from inv), true) $$, 'P0001', 'admin_only', 'in admin mode, members do not vote');
select tests.authenticate_as('f5000000-0000-4000-8000-000000000001');
select public.vote_group_invitation((select id from inv), true);
select tests.authenticate_as('f5000000-0000-4000-8000-000000000003');
select is(public.respond_group_invitation((select id from inv), true), 'joined', 'the admin approval is enough');

-- The creator's Premium is required to invite (groups.creator_only_premium)
reset role;
delete from private.entitlements where user_id = pg_temp.u(1);
select tests.authenticate_as('f5000000-0000-4000-8000-000000000002');
select throws_ok(format('select public.invite_to_group(%L, %L)', (select id from grp), pg_temp.u(4)), 'P0001', 'premium_required',
  'no new invitation while the creator is not Premium');
select tests.authenticate_as('f5000000-0000-4000-8000-000000000003');
select lives_ok(format('select public.send_message(%L, %L)', (select c.id from public.conversations c where c.group_id = (select id from grp)), 'On se voit jeudi ?'),
  'the chat itself keeps working');

select * from finish();
rollback;
