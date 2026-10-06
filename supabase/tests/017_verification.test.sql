-- Selfie verification and age check (spec §12, §9 anti-abuse).
begin;
select plan(16);

-- Five users aged 30, each with a pending selfie submission.
select tests.create_onboarded_user('3363998320' || n, ('a8000000-0000-4000-8000-00000000000' || n)::uuid)
from generate_series(1, 5) n;
insert into private.selfie_submissions (user_id, storage_path)
select ('a8000000-0000-4000-8000-00000000000' || n)::uuid, 'a8000000-0000-4000-8000-00000000000' || n || '/selfie.jpg'
from generate_series(1, 5) n;

create function pg_temp.sub(n int) returns bigint language sql as $$
  select id from private.selfie_submissions where user_id = ('a8000000-0000-4000-8000-00000000000' || n)::uuid
$$;
create function pg_temp.profile(n int) returns public.profiles language sql as $$
  select * from public.profiles where id = ('a8000000-0000-4000-8000-00000000000' || n)::uuid
$$;

-- 1: passes
select is(private.apply_selfie_result(pg_temp.sub(1), true, 31, 0.95, 'face-1'), 'verified', 'live, adult, consistent age: verified');
select is((pg_temp.profile(1)).verification_status::text, 'verified', 'the badge is granted');
select ok(exists (select 1 from private.storage_cleanup where path like 'a8000000-0000-4000-8000-000000000001/%'),
  'the selfie is scheduled for deletion once verified');
select throws_ok(format('select private.apply_selfie_result(%s, true, 31, 0.95, %L)', pg_temp.sub(1), 'face-1'),
  'P0001', 'selfie_not_found', 'a submission is processed once');

-- 2: no live face
select is(private.apply_selfie_result(pg_temp.sub(2), false, null, null, null), 'retake', 'no live face: retake');
select is((pg_temp.profile(2)).verification_status::text, 'rejected', 'the user must take a new selfie');

-- 3: possible minor
select is(private.apply_selfie_result(pg_temp.sub(3), true, 16, 0.9, 'face-3'), 'review', 'estimated minor: human review');
select is((pg_temp.profile(3)).status::text, 'suspended', 'possible minor hidden from everyone meanwhile');
select is((select priority::int from private.moderation_queue where subject_user_id = (pg_temp.profile(3)).id), 1,
  'possible minors are reviewed first');

-- 4: same face as user 1 (one face = one account)
select is(private.apply_selfie_result(pg_temp.sub(4), true, 30, 0.95, 'face-1'), 'review', 'a face already used goes to review');
select is((select reason from private.moderation_queue where subject_user_id = (pg_temp.profile(4)).id), 'duplicate_face',
  'reason recorded for the moderator');

-- 5: declared 30, estimated 45
select is(private.apply_selfie_result(pg_temp.sub(5), true, 45, 0.9, 'face-5'), 'review', 'large age gap goes to review');

-- Moderator confirms a minor: closure, erasure queued, identity blocked (Q22)
select private.mod_resolve_selfie('moderator:test', (select id from private.moderation_queue where subject_user_id = (pg_temp.profile(3)).id), 'minor');
select is((pg_temp.profile(3)).status::text, 'closed', 'the account is closed');
select ok(exists (select 1 from private.pending_deletions where user_id = 'a8000000-0000-4000-8000-000000000003' and reason = 'minor'),
  'data erasure is queued');
select throws_ok($$ select tests.create_user('33639983203') $$, 'P0001', 'identity_blocked',
  'the same phone number cannot sign up again');

-- Moderator clears the age-gap case
select private.mod_resolve_selfie('moderator:test', (select id from private.moderation_queue where subject_user_id = (pg_temp.profile(5)).id), 'verified');
select is((pg_temp.profile(5)).verification_status::text, 'verified', 'human review can verify');

select * from finish();
rollback;
