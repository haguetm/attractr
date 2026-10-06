-- Automatic photo moderation, human review, and visibility of approved photos only.
begin;
select plan(9);

select tests.create_onboarded_user('33639983301', 'a9000000-0000-4000-8000-00000000000a', 'woman', '{man}');
select tests.create_onboarded_user('33639983302', 'a9000000-0000-4000-8000-00000000000b', 'man', '{woman}');
insert into public.photos (id, user_id, storage_path, position) values
  ('a9100000-0000-4000-8000-000000000001', 'a9000000-0000-4000-8000-00000000000b', 'a9000000-0000-4000-8000-00000000000b/1.jpg', 1),
  ('a9100000-0000-4000-8000-000000000002', 'a9000000-0000-4000-8000-00000000000b', 'a9000000-0000-4000-8000-00000000000b/2.jpg', 2),
  ('a9100000-0000-4000-8000-000000000003', 'a9000000-0000-4000-8000-00000000000b', 'a9000000-0000-4000-8000-00000000000b/3.jpg', 3);

set local role service_role;
select is(array(select id::text from public.service_pending_photos() where user_id = 'a9000000-0000-4000-8000-00000000000b' order by id),
  array['a9100000-0000-4000-8000-000000000001', 'a9100000-0000-4000-8000-000000000002', 'a9100000-0000-4000-8000-000000000003'],
  'new photos wait for moderation');
select is(public.service_record_photo_result('a9100000-0000-4000-8000-000000000001', 0.02, 0.01), 'approved', 'clean photo approved');
select is(public.service_record_photo_result('a9100000-0000-4000-8000-000000000002', 0.97, 0.0), 'rejected', 'clear nudity rejected');
select is(public.service_record_photo_result('a9100000-0000-4000-8000-000000000003', 0.6, 0.1), 'review', 'uncertain photo sent to humans');
select is((select count(*)::int from public.service_pending_photos() where user_id = 'a9000000-0000-4000-8000-00000000000b'), 0,
  'photos in review are not sent to the provider again');
reset role;

select tests.authenticate_as('a9000000-0000-4000-8000-00000000000b');
select throws_ok($$ select public.service_record_photo_result('a9100000-0000-4000-8000-000000000001', 0, 0) $$, '42501', null,
  'users cannot moderate their own photos');

reset role;
insert into private.feed_impressions (viewer_id, target_id) values ('a9000000-0000-4000-8000-00000000000a', 'a9000000-0000-4000-8000-00000000000b');
select is((select jsonb_agg(p ->> 'id') from jsonb_array_elements(private.profile_card('a9000000-0000-4000-8000-00000000000b', 1000, '{wine}') -> 'photos') p),
  '["a9100000-0000-4000-8000-000000000001"]'::jsonb, 'others only see approved photos');

select private.mod_resolve_photo('moderator:test',
  (select id from private.moderation_queue where kind = 'photo_review' and ref_id = 'a9100000-0000-4000-8000-000000000003'), 'approved');
select is((select moderation_status::text from public.photos where id = 'a9100000-0000-4000-8000-000000000003'), 'approved',
  'a moderator can approve after review');
select ok(exists (select 1 from private.access_log where actor = 'moderator:test' and resource = 'moderation:photo_review'),
  'moderator actions are logged');

select * from finish();
rollback;
