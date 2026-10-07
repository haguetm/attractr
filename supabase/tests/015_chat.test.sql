-- Match chat: membership, 24 h window, extension, unmatch, reminders (spec §5).
begin;
select plan(26);

select tests.create_onboarded_user('33639983001', 'f0000000-0000-4000-8000-00000000000a', 'woman', '{man}');
select tests.create_onboarded_user('33639983002', 'f0000000-0000-4000-8000-00000000000b', 'man', '{woman}');
select tests.create_onboarded_user('33639983003', 'f0000000-0000-4000-8000-00000000000c', 'man', '{woman}');
select tests.create_onboarded_user('33639983004', 'f0000000-0000-4000-8000-00000000000d', 'man', '{woman}');
select tests.create_onboarded_user('33639983005', 'f0000000-0000-4000-8000-00000000000e', 'man', '{woman}');

-- Matches A-B (fresh), A-D (window over), A-E (window ends in 1 h), each with its conversation.
create function pg_temp.match(p_match uuid, p_conv uuid, a uuid, b uuid, deadline timestamptz) returns void language sql as $$
  insert into public.matches (id, user_a, user_b, matched_drinks, first_message_deadline) values (p_match, a, b, '{wine}', deadline);
  insert into public.conversations (id, kind, match_id) values (p_conv, 'match', p_match);
  insert into public.conversation_members (conversation_id, user_id) values (p_conv, a), (p_conv, b);
$$;
select pg_temp.match('f1000000-0000-4000-8000-0000000000ab', 'f2000000-0000-4000-8000-0000000000ab',
  'f0000000-0000-4000-8000-00000000000a', 'f0000000-0000-4000-8000-00000000000b', now() + interval '24 hours');
select pg_temp.match('f1000000-0000-4000-8000-0000000000ad', 'f2000000-0000-4000-8000-0000000000ad',
  'f0000000-0000-4000-8000-00000000000a', 'f0000000-0000-4000-8000-00000000000d', now() - interval '1 minute');
select pg_temp.match('f1000000-0000-4000-8000-0000000000ae', 'f2000000-0000-4000-8000-0000000000ae',
  'f0000000-0000-4000-8000-00000000000a', 'f0000000-0000-4000-8000-00000000000e', now() + interval '1 hour');
insert into public.photos (user_id, storage_path, position, moderation_status)
values ('f0000000-0000-4000-8000-00000000000e', 'f0000000-0000-4000-8000-00000000000e/1.jpg', 1, 'approved');

-- Membership
select tests.authenticate_as('f0000000-0000-4000-8000-00000000000c');
select throws_ok($$ select public.send_message('f2000000-0000-4000-8000-0000000000ab', 'Salut') $$,
  'P0001', 'conversation_not_found', 'only members can write');

select tests.authenticate_as('f0000000-0000-4000-8000-00000000000a');
select throws_ok($$ select public.send_message('f2000000-0000-4000-8000-0000000000ab', '   ') $$,
  'P0001', 'message_length', 'empty messages are refused');
select lives_ok($$ select public.send_message('f2000000-0000-4000-8000-0000000000ab', 'Salut ! Ta réponse sur la ponctualité m''a plu.') $$,
  'first message sent within 24 h');
select throws_ok($$ insert into public.messages (conversation_id, sender_id, body) values ('f2000000-0000-4000-8000-0000000000ab', auth.uid(), 'x') $$,
  '42501', null, 'messages are only written through send_message');

select tests.authenticate_as('f0000000-0000-4000-8000-00000000000c');
select is_empty($$ select 1 from public.messages $$, 'non-members read no messages');
select is_empty($$ select 1 from public.conversations $$, 'non-members see no conversation');
select is_empty($$ select 1 from public.matches $$, 'non-members see no match');

select tests.authenticate_as('f0000000-0000-4000-8000-00000000000b');
select is((select count(*)::int from public.messages), 1, 'the other member reads the message');
select is((select (m ->> 'unread_count')::int from jsonb_array_elements(public.get_my_matches()) m
           where m ->> 'match_id' = 'f1000000-0000-4000-8000-0000000000ab'), 1, 'one unread message');
select ok((select (m ->> 'my_turn')::boolean from jsonb_array_elements(public.get_my_matches()) m
           where m ->> 'match_id' = 'f1000000-0000-4000-8000-0000000000ab'), 'it is B''s turn');
select public.mark_conversation_read('f2000000-0000-4000-8000-0000000000ab');
select is((select (m ->> 'unread_count')::int from jsonb_array_elements(public.get_my_matches()) m
           where m ->> 'match_id' = 'f1000000-0000-4000-8000-0000000000ab'), 0, 'reading clears the counter');
select public.send_message('f2000000-0000-4000-8000-0000000000ab', 'Merci !');

select tests.authenticate_as('f0000000-0000-4000-8000-00000000000a');
select ok((public.get_match_profile('f1000000-0000-4000-8000-0000000000ab') ->> 'recently_active')::boolean,
  'replying earns the activity badge (Q16)');
select throws_ok($$ select * from private.notification_outbox $$, '42501', null, 'the notification outbox is server-only');
reset role;
select is((select count(*)::int from private.notification_outbox where kind = 'new_message'), 2, 'each message notifies the other member');

-- 24 h window
select tests.authenticate_as('f0000000-0000-4000-8000-00000000000a');
select throws_ok($$ select public.send_message('f2000000-0000-4000-8000-0000000000ad', 'Trop tard ?') $$,
  'P0001', 'match_expired', 'no first message after the window');
select ok(not (public.get_my_matches() @> '[{"match_id":"f1000000-0000-4000-8000-0000000000ad"}]'), 'expired matches leave the list');
select lives_ok($$ select public.extend_match('f1000000-0000-4000-8000-0000000000ae') $$, 'the window can be extended once');
select throws_ok($$ select public.extend_match('f1000000-0000-4000-8000-0000000000ae') $$,
  'P0001', 'match_extension_unavailable', 'only match.max_extensions extensions');

-- Photos are visible between matches, not after unmatching
select ok(public.can_view_photo('f0000000-0000-4000-8000-00000000000e/1.jpg'), 'match photos are readable');
select lives_ok($$ select public.unmatch('f1000000-0000-4000-8000-0000000000ae') $$, 'unmatch in one tap');
select ok(not public.can_view_photo('f0000000-0000-4000-8000-00000000000e/1.jpg'), 'but not after unmatching');
select throws_ok($$ select public.send_message('f2000000-0000-4000-8000-0000000000ae', 'Coucou') $$,
  'P0001', 'match_closed', 'no message after unmatching');

-- Scheduled jobs
reset role;
select is(private.expire_matches(), 1, 'the job marks expired matches');
update public.matches set first_message_deadline = now() + interval '2 hours', first_message_at = null, status = 'active', extensions_used = 0
 where id = 'f1000000-0000-4000-8000-0000000000ae';
select is(private.queue_first_message_reminders(), 2, 'both are reminded before the window ends');
-- A wrote last, 25 h ago, and B has not answered.
delete from public.messages
 where conversation_id = 'f2000000-0000-4000-8000-0000000000ab' and sender_id = 'f0000000-0000-4000-8000-00000000000b';
update public.messages set created_at = now() - interval '25 hours'
 where conversation_id = 'f2000000-0000-4000-8000-0000000000ab';
select is(private.queue_your_turn(), 1, '"à ton tour" for the person who has not answered');
select is(private.queue_your_turn(), 0, 'and only once per message');

select * from finish();
rollback;
