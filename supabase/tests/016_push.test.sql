-- Push tokens and the server-side notification queue.
begin;
select plan(8);

select tests.create_onboarded_user('33639983101', 'f3000000-0000-4000-8000-00000000000a');
select tests.create_onboarded_user('33639983102', 'f3000000-0000-4000-8000-00000000000b', 'man', '{woman}');

select tests.authenticate_as('f3000000-0000-4000-8000-00000000000a');
select lives_ok($$ select public.register_push_token('ExponentPushToken[aaaaaaaaaaaa]', 'ios') $$, 'register a device');
select is((select count(*)::int from public.push_tokens), 1, 'the owner sees their token');
select throws_ok($$ select public.service_pending_notifications() $$, '42501', null, 'the app cannot read the queue');
select throws_ok($$ select public.service_mark_notifications('{}', '{}') $$, '42501', null, 'the app cannot mark notifications');

select tests.authenticate_as('f3000000-0000-4000-8000-00000000000b');
select is_empty($$ select 1 from public.push_tokens $$, 'tokens of others are hidden');
-- Same device signed in with another account: the token moves to that account.
select public.register_push_token('ExponentPushToken[aaaaaaaaaaaa]', 'ios');
reset role;
select is((select user_id::text from public.push_tokens), 'f3000000-0000-4000-8000-00000000000b', 'a token belongs to the last account');

select private.notify('f3000000-0000-4000-8000-00000000000b', 'new_match', '{"match_id":"x"}');
set local role service_role;
select is((select tokens from public.service_pending_notifications() where user_id = 'f3000000-0000-4000-8000-00000000000b'),
  array['ExponentPushToken[aaaaaaaaaaaa]'], 'the sender gets pending rows with tokens');
select public.service_mark_notifications(array(select id from public.service_pending_notifications()), '{}');
select is_empty($$ select 1 from public.service_pending_notifications() $$, 'sent rows leave the queue');

select * from finish();
rollback;
