-- Targeted likes, rolling quota, answers outside the quota, matches (spec §5).
begin;
select plan(19);

-- A: woman seeking men. B, C, D, E, F: men seeking women. All wine, monogamous.
select tests.create_onboarded_user('33639982901', 'e0000000-0000-4000-8000-00000000000a', 'woman', '{man}');
select tests.create_onboarded_user('33639982902', 'e0000000-0000-4000-8000-00000000000b', 'man', '{woman}');
select tests.create_onboarded_user('33639982903', 'e0000000-0000-4000-8000-00000000000c', 'man', '{woman}');
select tests.create_onboarded_user('33639982904', 'e0000000-0000-4000-8000-00000000000d', 'man', '{woman}');
select tests.create_onboarded_user('33639982905', 'e0000000-0000-4000-8000-00000000000e', 'man', '{woman}');
select tests.create_onboarded_user('33639982906', 'e0000000-0000-4000-8000-0000000000f0', 'man', '{woman}');
insert into public.profile_prompts (user_id, position, question_code, answer)
select id, 1, 'green_flag', 'La ponctualité' from public.profiles where id::text like 'e0000000-%';
insert into public.photos (id, user_id, storage_path, position) values
  ('e1000000-0000-4000-8000-00000000000b', 'e0000000-0000-4000-8000-00000000000b', 'e0000000-0000-4000-8000-00000000000b/1.jpg', 1);
-- The feed served B, D, E and F to A (C was never shown).
insert into private.feed_impressions (viewer_id, target_id)
select 'e0000000-0000-4000-8000-00000000000a', id from public.profiles
where id in ('e0000000-0000-4000-8000-00000000000b', 'e0000000-0000-4000-8000-00000000000d',
             'e0000000-0000-4000-8000-00000000000e', 'e0000000-0000-4000-8000-0000000000f0');

select tests.authenticate_as('e0000000-0000-4000-8000-00000000000a');
select throws_ok($$ select public.like_profile('e0000000-0000-4000-8000-00000000000c', 'prompt', 'green_flag') $$,
  'P0001', 'profile_unavailable', 'cannot like a profile the feed never showed');
select throws_ok($$ select public.like_profile('e0000000-0000-4000-8000-00000000000b', 'photo', 'e1000000-0000-4000-8000-000000000999') $$,
  'P0001', 'invalid_like_target', 'the liked photo must belong to the profile');
select throws_ok($$ select public.like_profile('e0000000-0000-4000-8000-00000000000b', 'prompt', 'perfect_sunday') $$,
  'P0001', 'invalid_like_target', 'the liked answer must belong to the profile');
select is((public.like_profile('e0000000-0000-4000-8000-00000000000b', 'photo', 'e1000000-0000-4000-8000-00000000000b') ->> 'matched')::boolean,
  false, 'targeted like on a photo, no match yet');
select throws_ok($$ select public.like_profile('e0000000-0000-4000-8000-00000000000b', 'prompt', 'green_flag') $$,
  'P0001', 'already_liked', 'one like per profile');
select is((public.get_like_quota() ->> 'used')::int, 1, 'the like used the quota');

-- B answers: match, without consuming B's quota
select tests.authenticate_as('e0000000-0000-4000-8000-00000000000b');
select is((public.like_profile('e0000000-0000-4000-8000-00000000000a', 'prompt', 'green_flag') ->> 'matched')::boolean,
  true, 'answering a like creates a match (no feed impression needed)');
select is((public.get_like_quota() ->> 'used')::int, 0, 'answering a like is outside the quota');
select throws_ok($$ select public.like_profile(auth.uid(), 'prompt', 'green_flag') $$, 'P0001', 'cannot_swipe_self', 'cannot like oneself');
reset role;

select is((select matched_drinks::text from public.matches
           where user_a = 'e0000000-0000-4000-8000-00000000000a' and user_b = 'e0000000-0000-4000-8000-00000000000b'),
  '{wine}', 'the match records the matching drink');
select ok((select first_message_deadline between now() + interval '23 hours 59 minutes' and now() + interval '24 hours 1 minute'
           from public.matches where user_a = 'e0000000-0000-4000-8000-00000000000a'),
  '24 h to send the first message');
select is((select count(*)::int from public.conversation_members cm
           join public.conversations c on c.id = cm.conversation_id
           join public.matches m on m.id = c.match_id
           where m.user_a = 'e0000000-0000-4000-8000-00000000000a'), 2, 'the match opens a conversation for both');
select is((select count(*)::int from private.notification_outbox where kind = 'new_match'
           and user_id in ('e0000000-0000-4000-8000-00000000000a', 'e0000000-0000-4000-8000-00000000000b')), 2,
  'both are notified of the match');

-- Quota
update public.app_config set value = '2' where key = 'likes.free_quota';
select tests.authenticate_as('e0000000-0000-4000-8000-00000000000a');
select public.like_profile('e0000000-0000-4000-8000-00000000000d', 'prompt', 'green_flag');
select throws_ok($$ select public.like_profile('e0000000-0000-4000-8000-00000000000e', 'prompt', 'green_flag') $$,
  'P0001', 'like_quota_reached', 'free likes are limited per rolling window');
select ok((public.get_like_quota() ->> 'next_reset_at') is not null, 'the app knows when likes come back');
reset role;
insert into private.entitlements (user_id, entitlement, source) values ('e0000000-0000-4000-8000-00000000000a', 'premium', 'test');
select tests.authenticate_as('e0000000-0000-4000-8000-00000000000a');
select lives_ok($$ select public.like_profile('e0000000-0000-4000-8000-00000000000e', 'prompt', 'green_flag') $$, 'Premium likes are unlimited');

-- Blocks, likes received, pass vs like
reset role;
insert into public.blocks (blocker_id, blocked_id) values ('e0000000-0000-4000-8000-0000000000f0', 'e0000000-0000-4000-8000-00000000000a');
select tests.authenticate_as('e0000000-0000-4000-8000-00000000000a');
select throws_ok($$ select public.like_profile('e0000000-0000-4000-8000-0000000000f0', 'prompt', 'green_flag') $$,
  'P0001', 'profile_unavailable', 'cannot like someone who blocked you');
select public.pass_profile('e0000000-0000-4000-8000-00000000000d');
select is((select action::text from public.swipes where target_id = 'e0000000-0000-4000-8000-00000000000d'), 'like',
  'a pass never cancels a like');

select tests.authenticate_as('e0000000-0000-4000-8000-00000000000d');
select is(public.get_likes_received_count(), 1, 'likes waiting for an answer are counted');

select * from finish();
rollback;
