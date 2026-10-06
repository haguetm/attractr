-- Couple accounts (spec §6).
begin;
select plan(30);

-- L (woman) and H (man) form an open couple. I: man open to couples. J: man not open to
-- couples. K: woman, Bière only. M and N: a second couple (closed). O: onboarding user.
select tests.create_onboarded_user('33639984401', 'f6000000-0000-4000-8000-00000000001a', 'woman', '{man,woman}', '{coffee}', 'open_to_explore');
select tests.create_onboarded_user('33639984402', 'f6000000-0000-4000-8000-00000000001b', 'man', '{woman,man}', '{coffee}', 'open_to_explore');
select tests.create_onboarded_user('33639984403', 'f6000000-0000-4000-8000-00000000001c', 'man', '{woman}', '{coffee}', 'open_to_explore');
select tests.create_onboarded_user('33639984404', 'f6000000-0000-4000-8000-00000000001d', 'man', '{woman}', '{coffee}', 'open_to_explore');
select tests.create_onboarded_user('33639984405', 'f6000000-0000-4000-8000-00000000001e', 'woman', '{man}', '{beer}', null);
select tests.create_onboarded_user('33639984406', 'f6000000-0000-4000-8000-00000000001f', 'woman', '{man}', '{wine}', 'monogamous');
select tests.create_onboarded_user('33639984407', 'f6000000-0000-4000-8000-000000000020', 'man', '{woman}', '{wine}', 'monogamous');
select tests.create_onboarded_user('33639984408', 'f6000000-0000-4000-8000-000000000021', 'woman', '{man}', '{wine}', 'monogamous', false);
create function pg_temp.u(c text) returns uuid language sql as $$
  select ('f6000000-0000-4000-8000-0000000000' || case c when 'L' then '1a' when 'H' then '1b' when 'I' then '1c' when 'J' then '1d'
          when 'K' then '1e' when 'M' then '1f' when 'N' then '20' else '21' end)::uuid
$$;
update public.profiles set verification_status = 'verified',
  first_name = case right(id::text, 2) when '1a' then 'Lea' when '1b' then 'Hugo' when '1c' then 'Ilan' when '1d' then 'Jules'
               when '1e' then 'Kim' when '1f' then 'Maud' when '20' then 'Noe' else 'Olga' end
where id::text like 'f6000000-%';
update public.profiles set username = lower(first_name || right(id::text, 2)) where id::text like 'f6000000-%';
update public.profiles set open_to_couples = true where id = pg_temp.u('I');
select public.service_set_location(id, 48.8566, 2.3522, 'device', 'FR', '75', '11') from public.profiles where id::text like 'f6000000-%';
insert into public.profile_prompts (user_id, position, question_code, answer) values (pg_temp.u('I'), 1, 'green_flag', 'La curiosité');
update public.app_config set value = '0' where key = 'feed.min_results';

-- Path A: request by pseudo, accepted by the partner
select tests.authenticate_as('f6000000-0000-4000-8000-00000000001a');
select lives_ok($$ select public.request_couple_by_username('hugo1b') $$, 'Lea invites Hugo by pseudo');
select tests.authenticate_as('f6000000-0000-4000-8000-00000000001b');
create temp table cpl on commit drop as
  select public.respond_couple_request((public.get_my_couple() -> 'invitations' -> 0 ->> 'id')::uuid, true) as id;
grant select on cpl to authenticated;
select isnt_empty($$ select 1 from cpl where id is not null $$, 'Hugo accepts: the couple exists');
select is(public.get_my_couple() -> 'couple' ->> 'status', 'setup', 'not published before its profile is complete');
select throws_ok($$ select public.create_couple_invitation() $$, 'P0001', 'already_in_couple', 'one couple per person');

-- Path B: the partner must finish their own signup first
select tests.authenticate_as('f6000000-0000-4000-8000-00000000001f');
create temp table code on commit drop as select public.create_couple_invitation() as c;
grant select on code to authenticated;
select tests.authenticate_as('f6000000-0000-4000-8000-000000000021');
select throws_ok($$ select public.accept_couple_invitation((select c from code)) $$, 'P0001', 'onboarding_required',
  'the invited partner completes their own signup (age, selfie, consents) first');

-- Profile, shared photo approved by both, moderation, publication
select tests.authenticate_as('f6000000-0000-4000-8000-00000000001a');
select is(public.set_couple_profile('open', '{coffee}', 'open_to_explore', null, '{person}', '{man,woman}', 'On aime les brunchs'), 'setup',
  'still waiting for a shared photo');
reset role;
insert into storage.objects (bucket_id, name, owner_id) values ('photos', (select id from cpl) || '/1.jpg', pg_temp.u('L')::text);
select tests.authenticate_as('f6000000-0000-4000-8000-00000000001a');
create temp table photo on commit drop as select public.add_couple_photo((select id from cpl) || '/1.jpg') as id;
grant select on photo to authenticated;
select throws_ok($$ select public.approve_couple_photo((select id from photo), true) $$, 'P0001', 'photo_not_found',
  'the uploader cannot approve their own shared photo');
select tests.authenticate_as('f6000000-0000-4000-8000-00000000001b');
select public.approve_couple_photo((select id from photo), true);
reset role;
select public.service_record_photo_result((select id from photo), 0.01, 0.01);
select tests.authenticate_as('f6000000-0000-4000-8000-00000000001b');
select is(public.get_my_couple() -> 'couple' ->> 'status', 'published', 'published once both partners agreed and are verified');

-- Who sees the couple
create function pg_temp.feed_has(n text, as_couple boolean default false) returns boolean language sql as $$
  select public.get_feed(50, as_couple) -> 'cards' @> jsonb_build_array(jsonb_build_object('id', case when n = 'C' then (select id from cpl) else pg_temp.u(n) end))
$$;
select tests.authenticate_as('f6000000-0000-4000-8000-00000000001c');
select ok(pg_temp.feed_has('C'), 'an individual open to couples sees the couple');
select ok(public.get_feed(50) -> 'cards' -> 0 -> 'couple' -> 'first_names' = '["Lea", "Hugo"]', 'the card shows both first names and the couple badge');
select tests.authenticate_as('f6000000-0000-4000-8000-00000000001d');
select ok(not pg_temp.feed_has('C'), 'not open to couples: no couple in the feed');
select tests.authenticate_as('f6000000-0000-4000-8000-00000000001e');
select ok(not pg_temp.feed_has('C'), 'Bière only: an open coffee couple does not match');

-- The couple's feed
select tests.authenticate_as('f6000000-0000-4000-8000-00000000001a');
select ok(pg_temp.feed_has('I', true), 'browsing as the couple shows compatible people');
select ok(not pg_temp.feed_has('H', true) and not pg_temp.feed_has('C'), 'never the partners or their own couple');

-- A couple like needs both partners
create temp table approval on commit drop as select public.propose_couple_like(pg_temp.u('I'), 'prompt', 'green_flag') as id;
grant select on approval to authenticated;
select throws_ok($$ select public.decide_couple_like((select id from approval), true) $$, 'P0001', 'partner_must_approve',
  'the proposer cannot approve alone');
select is_empty($$ select 1 from public.swipes where actor_id = (select id from cpl) $$, 'nothing is sent before the partner agrees');
select tests.authenticate_as('f6000000-0000-4000-8000-00000000001b');
select is((public.decide_couple_like((select id from approval), true) ->> 'matched')::boolean, false, 'the partner approves: the like is sent');

-- I likes back: match, transparent chat with both partners
select tests.authenticate_as('f6000000-0000-4000-8000-00000000001c');
select is((public.like_profile((select id from cpl), 'photo', (select id::text from photo)) ->> 'matched')::boolean, true, 'mutual like with the couple');
reset role;
create temp table conv on commit drop as
  select c.id from public.conversations c join public.matches m on m.id = c.match_id where (select id from cpl) in (m.user_a, m.user_b);
grant select on conv to authenticated;
select is((select count(*)::int from public.conversation_members where conversation_id = (select id from conv)), 3,
  'the conversation includes both partners and the third person');
select tests.authenticate_as('f6000000-0000-4000-8000-00000000001b');
select ok((public.get_my_matches() -> 0 ->> 'as_couple')::boolean, 'Hugo sees the couple match');
select lives_ok(format('select public.send_message(%L, %L)', (select id from conv), 'Salut Ilan, c''est Hugo !'), 'a partner writes in the couple chat');
select tests.authenticate_as('f6000000-0000-4000-8000-00000000001a');
select is((select count(*)::int from public.messages), 1, 'the other partner reads it too');

-- Personal matches stay personal
reset role;
insert into public.matches (user_a, user_b, matched_drinks, first_message_deadline)
values (least(pg_temp.u('L'), pg_temp.u('J')), greatest(pg_temp.u('L'), pg_temp.u('J')), '{coffee}', now() + interval '1 day');
insert into public.conversations (kind, match_id) select 'match', id from public.matches where pg_temp.u('J') in (user_a, user_b);
insert into public.conversation_members (conversation_id, user_id)
select c.id, unnest(array[pg_temp.u('L'), pg_temp.u('J')]) from public.conversations c join public.matches m on m.id = c.match_id where pg_temp.u('J') in (m.user_a, m.user_b);
select tests.authenticate_as('f6000000-0000-4000-8000-00000000001b');
select ok(not (public.get_my_matches()::text like '%Jules%'), 'Hugo never sees Lea''s personal matches');
select is((select count(*)::int from public.swipes where actor_id = pg_temp.u('L')), 0, '... nor her personal likes');

-- Open couple: a partner may hide their individual profile
select public.set_my_couple_visibility(true);
select tests.authenticate_as('f6000000-0000-4000-8000-00000000001c');
select ok(not pg_temp.feed_has('H'), 'a hidden individual profile leaves the feeds');

-- Closed couple: Bière only, individual profiles too
reset role;
select private.create_couple(pg_temp.u('M'), pg_temp.u('N'));
select tests.authenticate_as('f6000000-0000-4000-8000-00000000001f');
select public.set_couple_profile('closed', '{wine}', null, null, '{person}', null, null);
reset role;
select is((select array_agg(drink)::text from public.profile_drinks where user_id = pg_temp.u('M')), '{beer}',
  'closing the couple switches each partner to Bière only');
select is((select reason from private.drink_change_history where user_id = pg_temp.u('N') order by id desc limit 1), 'couple_closed',
  'the forced change is recorded without cooldown');

-- Leaving in one tap; deleting a partner's account erases the couple
select tests.authenticate_as('f6000000-0000-4000-8000-00000000001b');
select lives_ok($$ select public.leave_couple() $$, 'one partner leaves, no consent needed');
reset role;
select ok(not exists (select 1 from public.profiles where id = (select id from cpl))
          and not exists (select 1 from public.conversations where id = (select id from conv)),
  'the couple profile, its matches and chats are erased');
delete from auth.users where id = pg_temp.u('M');
select ok(private.couple_of(pg_temp.u('N')) is null and not exists (select 1 from public.profiles where is_couple and first_name like 'Maud%'),
  'deleting a partner''s account erases the couple profile');

select * from finish();
rollback;
