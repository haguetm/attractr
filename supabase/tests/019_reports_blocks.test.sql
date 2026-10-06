-- Reports, blocks (incl. phone contacts), pause mode, sanctions, scam rules.
begin;
select plan(23);

-- V: woman. M1..M5: men. V and M1 are matched.
select tests.create_onboarded_user('33639983400', 'b9000000-0000-4000-8000-000000000000', 'woman', '{man}');
select tests.create_onboarded_user('3363998340' || n, ('b9000000-0000-4000-8000-00000000000' || n)::uuid, 'man', '{woman}')
from generate_series(1, 5) n;
insert into public.matches (id, user_a, user_b, first_message_deadline) values
  ('b9100000-0000-4000-8000-000000000001', 'b9000000-0000-4000-8000-000000000000', 'b9000000-0000-4000-8000-000000000001', now() + interval '1 day');
insert into public.conversations (id, kind, match_id) values ('b9200000-0000-4000-8000-000000000001', 'match', 'b9100000-0000-4000-8000-000000000001');
insert into public.conversation_members (conversation_id, user_id) values
  ('b9200000-0000-4000-8000-000000000001', 'b9000000-0000-4000-8000-000000000000'),
  ('b9200000-0000-4000-8000-000000000001', 'b9000000-0000-4000-8000-000000000001');

-- Scam rules in the chat
select tests.authenticate_as('b9000000-0000-4000-8000-000000000001');
select throws_ok($$ select public.send_message('b9200000-0000-4000-8000-000000000001', 'Regarde mon site www.exemple.com') $$,
  'P0001', 'links_not_allowed_yet', 'links are refused in the first messages');
select throws_ok($$ select public.send_message('b9200000-0000-4000-8000-000000000001', 'Ajoute-moi sur insta.gg/moi') $$,
  'P0001', 'links_not_allowed_yet', 'short links too');
select lives_ok($$ select public.send_message('b9200000-0000-4000-8000-000000000001', 'Tu peux me faire un virement par Western Union ?') $$,
  'money requests are delivered');
reset role;
select ok(exists (select 1 from private.moderation_queue where kind = 'message_review' and reason = 'money_request'
                  and subject_user_id = 'b9000000-0000-4000-8000-000000000001'), 'but sent to human review');
select ok(not private.looks_like_money_request('On se voit samedi pour un café ?'), 'ordinary messages are not flagged');

-- Report from the chat, blocking at the same time
select tests.authenticate_as('b9000000-0000-4000-8000-000000000000');
select lives_ok($$ select public.report_profile('b9000000-0000-4000-8000-000000000001', 'scam', 'Demande d''argent', 'b9200000-0000-4000-8000-000000000001') $$,
  'report from a chat');
select throws_ok($$ select public.report_profile('b9000000-0000-4000-8000-000000000002', 'nonsense') $$, '23514', null,
  'unknown reasons are refused');
select throws_ok($$ select public.report_profile(auth.uid(), 'other') $$, 'P0001', 'cannot_report_self', 'cannot report oneself');
reset role;
select is((select status::text from public.matches where id = 'b9100000-0000-4000-8000-000000000001'), 'unmatched',
  'reporting with block closes the match');
select ok(exists (select 1 from public.blocks where blocker_id = 'b9000000-0000-4000-8000-000000000000'
                  and blocked_id = 'b9000000-0000-4000-8000-000000000001' and source = 'report'), 'and blocks the person');

-- Suspected minor is urgent
select tests.authenticate_as('b9000000-0000-4000-8000-000000000000');
select public.report_profile('b9000000-0000-4000-8000-000000000002', 'suspected_minor', null, null, false);
reset role;
select is((select priority::int from private.moderation_queue where kind = 'report' and reason = 'suspected_minor'), 1,
  '"suspicion de mineur" is reviewed first');

-- Daily limit
update public.app_config set value = '2' where key = 'reports.daily_limit';
select tests.authenticate_as('b9000000-0000-4000-8000-000000000000');
select throws_ok($$ select public.report_profile('b9000000-0000-4000-8000-000000000003', 'other') $$, 'P0001', 'report_limit_reached',
  'reports are limited per day');

-- Manual block / unblock
select lives_ok($$ select public.block_profile('b9000000-0000-4000-8000-000000000003') $$, 'block a profile');
select ok(public.get_my_blocks() -> 'profiles' @> '[{"id":"b9000000-0000-4000-8000-000000000003"}]', 'the owner sees whom they blocked');
select lives_ok($$ select public.unblock_profile('b9000000-0000-4000-8000-000000000003') $$, 'unblock');

-- Contacts: digests of E.164 digits; nothing returned, nothing stored
select public.block_contacts(array[encode(extensions.digest('33639983404', 'sha256'), 'hex'), encode(extensions.digest('33600000000', 'sha256'), 'hex')]);
reset role;
select ok(exists (select 1 from public.blocks where blocker_id = 'b9000000-0000-4000-8000-000000000000'
                  and blocked_id = 'b9000000-0000-4000-8000-000000000004' and source = 'contacts'), 'a contact on the app is blocked');
select tests.authenticate_as('b9000000-0000-4000-8000-000000000000');
select is((public.get_my_blocks() ->> 'contacts_blocked')::boolean, true, 'contact blocks are only reported as a yes/no');
select ok(not (public.get_my_blocks() -> 'profiles')::text like '%b9000000-0000-4000-8000-000000000004%', 'contact blocks are not listed');

-- Pause mode
select tests.authenticate_as('b9000000-0000-4000-8000-000000000005');
select public.set_my_paused(true);
reset role;
select is((select status::text from public.profiles where id = 'b9000000-0000-4000-8000-000000000005'), 'paused', 'pause hides the profile');
select tests.authenticate_as('b9000000-0000-4000-8000-000000000005');
select public.set_my_paused(false);
reset role;
select is((select status::text from public.profiles where id = 'b9000000-0000-4000-8000-000000000005'), 'active', 'and comes back');

-- Misleading intent: warning at the 3rd validated report, suspension at the 4th (Q15)
update public.app_config set value = '10' where key = 'reports.daily_limit';
insert into public.reports (reporter_id, reported_id, reason)
select ('b9000000-0000-4000-8000-00000000000' || n)::uuid, 'b9000000-0000-4000-8000-000000000000', 'misleading_intent'
from generate_series(1, 4) n;
insert into private.moderation_queue (kind, subject_user_id, ref_id, reason)
select 'report', reported_id, id::text, reason from public.reports where reason = 'misleading_intent';
create function pg_temp.resolve_next() returns text language sql as $$
  select private.mod_resolve_report('moderator:test',
    (select q.id from private.moderation_queue q where q.kind = 'report' and q.reason = 'misleading_intent' and q.status = 'open' order by q.id limit 1),
    'validated')
$$;
select pg_temp.resolve_next();
select pg_temp.resolve_next();
select is(pg_temp.resolve_next(), 'warned', 'third validated report: warning');
select is(pg_temp.resolve_next(), 'suspended', 'fourth: suspension');
select is((select status::text from public.profiles where id = 'b9000000-0000-4000-8000-000000000000'), 'suspended', 'the profile is suspended');

select * from finish();
rollback;
