-- Popularity indicator (P1-P6): relative to the zone and drink, minimum age and views,
-- likes during a boost excluded, never for incognito profiles.
begin;
select plan(7);

-- Six women in the same département and drink, liked 0..5 times by fake likers.
select tests.create_onboarded_user('3363998410' || n, ('e4000000-0000-4000-8000-00000000000' || n)::uuid, 'woman', '{man}')
from generate_series(1, 6) n;
select tests.create_onboarded_user('336399842' || lpad(n::text, 2, '0'), ('e4100000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, 'man', '{woman}')
from generate_series(1, 10) n;
create function pg_temp.w(n int) returns uuid language sql as $$ select ('e4000000-0000-4000-8000-00000000000' || n)::uuid $$;
create function pg_temp.m(n int) returns uuid language sql as $$ select ('e4100000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid $$;
update public.profiles set department_code = '75', created_at = now() - interval '30 days' where id::text like 'e4000000-%';
-- Enough views for everyone, n-1 likes for woman n.
update public.app_config set value = '3' where key = 'popularity.min_views';
insert into private.profile_view_events (target_id, viewer_id)
select pg_temp.w(w), pg_temp.m(m) from generate_series(1, 6) w, generate_series(1, 3) m;
insert into public.swipes (actor_id, target_id, action, target_kind, target_ref, quota_counted)
select pg_temp.m(m), pg_temp.w(w), 'like', 'prompt', 'x', true from generate_series(1, 6) w, generate_series(1, 10) m where m < w;

select ok(private.compute_popularity() >= 6, 'popularity computed for eligible profiles');
select is(private.popularity_level(pg_temp.w(6)), 'high', 'most liked of the zone: "beaucoup de likes"');
select is(private.popularity_level(pg_temp.w(1)), 'low', 'least liked: "peu de likes"');
select is(private.popularity_level(pg_temp.w(3)), null, 'middle of the zone: nothing shown (P1)');

-- Likes received during one's own boost do not count (P4)
insert into public.boosts (user_id, starts_at, ends_at) values (pg_temp.w(6), now() - interval '1 day', now() + interval '1 hour');
select private.compute_popularity();
select isnt(private.popularity_level(pg_temp.w(6)), 'high', 'boosted likes are excluded');
delete from public.boosts;

-- Not enough views: no indicator (P3)
delete from private.profile_view_events where target_id = pg_temp.w(5);
select private.compute_popularity();
select is(private.popularity_level(pg_temp.w(5)), null, 'too few views: no indicator');

-- Incognito Premium profile: no indicator (P6)
insert into private.entitlements (user_id, entitlement, source) values (pg_temp.w(6), 'premium', 'test');
update public.profiles set incognito = true where id = pg_temp.w(6);
select private.compute_popularity();
select is(private.popularity_level(pg_temp.w(6)), null, 'never shown for incognito profiles');

select * from finish();
rollback;
