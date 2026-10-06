-- Access rules for discovery tables: nobody writes them directly nor reads others' rows.
begin;
select plan(9);

select tests.create_onboarded_user('33639982801', 'd0000000-0000-4000-8000-00000000000a');
select tests.create_onboarded_user('33639982802', 'd0000000-0000-4000-8000-00000000000b', 'man', '{woman}');
insert into public.swipes (actor_id, target_id, action) values ('d0000000-0000-4000-8000-00000000000a', 'd0000000-0000-4000-8000-00000000000b', 'pass');
insert into public.blocks (blocker_id, blocked_id) values ('d0000000-0000-4000-8000-00000000000a', 'd0000000-0000-4000-8000-00000000000b');
insert into public.reports (reporter_id, reported_id, reason) values ('d0000000-0000-4000-8000-00000000000a', 'd0000000-0000-4000-8000-00000000000b', 'test');
insert into public.search_preferences (user_id, radius_km) values ('d0000000-0000-4000-8000-00000000000a', 10);

select tests.authenticate_as('d0000000-0000-4000-8000-00000000000b');
select is_empty($$ select 1 from public.swipes $$, 'B does not see who passed on them');
select is_empty($$ select 1 from public.blocks $$, 'B does not see who blocked them');
select is_empty($$ select 1 from public.reports $$, 'B does not see who reported them');
select is_empty($$ select 1 from public.search_preferences $$, 'B does not see A''s search preferences');
select throws_ok($$ select * from private.feed_impressions $$, '42501', null, 'impressions are server-only');
select throws_ok($$ insert into public.swipes (actor_id, target_id, action) values (auth.uid(), 'd0000000-0000-4000-8000-00000000000a', 'like') $$,
  '42501', null, 'swipes are only written through RPCs');
select throws_ok($$ insert into public.search_preferences (user_id, radius_km) values (auth.uid(), 5) $$,
  '42501', null, 'search preferences are only written through set_my_search_preferences');
select throws_ok($$ select private.feed_candidates(auth.uid(), 25, true, 10) $$, '42501', null,
  'feed internals cannot be called directly');

select tests.authenticate_as('d0000000-0000-4000-8000-00000000000a');
select is((select count(*)::int from public.swipes), 1, 'A sees its own swipes');

select * from finish();
rollback;
