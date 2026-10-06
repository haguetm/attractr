-- Moderation internals are unreachable from the app; suspended users lose access.
begin;
select plan(8);

select tests.create_onboarded_user('33639983501', 'c9000000-0000-4000-8000-00000000000a');
select tests.authenticate_as('c9000000-0000-4000-8000-00000000000a');

select throws_ok($$ select * from private.moderation_queue $$, '42501', null, 'the queue is server-only');
select throws_ok($$ select private.mod_queue('me') $$, '42501', null, 'moderator functions are server-only');
select throws_ok($$ select * from private.face_templates $$, '42501', null, 'face references are server-only');
select throws_ok($$ select * from private.blocked_identities $$, '42501', null, 'blocked identities are server-only');
select throws_ok($$ select public.service_latest_selfie(auth.uid()) $$, '42501', null, 'selfie internals are service-only');
select throws_ok($$ select public.service_pending_deletions() $$, '42501', null, 'deletion queue is service-only');

reset role;
update public.profiles set status = 'suspended' where id = 'c9000000-0000-4000-8000-00000000000a';
select tests.authenticate_as('c9000000-0000-4000-8000-00000000000a');
select throws_ok($$ select public.get_feed() $$, 'P0001', 'profile_not_active', 'a suspended profile has no feed');
select throws_ok($$ select public.set_my_paused(false) $$, 'P0001', 'profile_not_active', 'and cannot lift the suspension itself');

select * from finish();
rollback;
