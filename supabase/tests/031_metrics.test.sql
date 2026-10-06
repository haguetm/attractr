-- Retention and daily KPIs: pseudonymous activity, D1/D7/D30 computation, survivor
-- bias avoided after deletion, seed exclusion, access rights.
begin;
select plan(21);

-- Activation creates a pseudonymous subject.
select tests.create_onboarded_user('33639983501', 'b4000000-0000-4000-8000-00000000000a', 'woman', '{man}');
select isnt((select activated_at from public.profiles where id = 'b4000000-0000-4000-8000-00000000000a'), null,
  'activation is stamped');
select is((select count(*)::int from private.metrics_links where user_id = 'b4000000-0000-4000-8000-00000000000a'), 1,
  'an activated user gets a metrics id');
select isnt((select metrics_id from private.metrics_links where user_id = 'b4000000-0000-4000-8000-00000000000a'),
  'b4000000-0000-4000-8000-00000000000a'::uuid, 'the metrics id is not the user id');
select is((select main_drink::text from private.metrics_subjects s join private.metrics_links l using (metrics_id)
            where l.user_id = 'b4000000-0000-4000-8000-00000000000a'), 'wine', 'the main drink is kept for segments');
select is((select count(*)::int from private.metrics_activity a join private.metrics_links l using (metrics_id)
            where l.user_id = 'b4000000-0000-4000-8000-00000000000a'), 1, 'the activation day counts as active');
select ok(not exists (select 1 from private.metrics_subjects s
  where to_jsonb(s)::text like '%b4000000-0000-4000-8000-00000000000a%'), 'no user id in the subjects');

-- Onboarding users and seed profiles are not tracked.
select tests.create_onboarded_user('33639983502', 'b4000000-0000-4000-8000-00000000000b', 'man', '{woman}', p_activate => false);
update public.profiles set last_active_at = now() where id = 'b4000000-0000-4000-8000-00000000000b';
select is((select count(*)::int from private.metrics_links where user_id = 'b4000000-0000-4000-8000-00000000000b'), 0,
  'users still in onboarding are not tracked');
select tests.create_onboarded_user('33639983503', 'b4000000-0000-4000-8000-00000000000c', 'man', '{woman}', p_activate => false);
update public.profiles set is_seed = true where id = 'b4000000-0000-4000-8000-00000000000c';
update public.profiles set status = 'active' where id = 'b4000000-0000-4000-8000-00000000000c';
select is((select count(*)::int from private.metrics_links where user_id = 'b4000000-0000-4000-8000-00000000000c'), 0,
  'seed profiles are not tracked');

-- App open: one activity row per day.
select tests.authenticate_as('b4000000-0000-4000-8000-00000000000a');
select lives_ok($$ select public.touch_my_activity() $$, 'the app can report an app open');
select lives_ok($$ select public.touch_my_activity() $$, 'twice the same day is harmless');
select throws_ok($$ select public.service_metrics_dashboard() $$, '42501', null, 'users cannot read the dashboard');
select isnt(public.get_my_analytics_id(), 'b4000000-0000-4000-8000-00000000000a'::uuid, 'the analytics id is not the user id');
reset role;

-- Synthetic cohort on 2026-01-05 (a Monday), 10 users:
--   all active on day 1; 4 active on day 9 (inside the D7 window 7..13), 1 on day 14 (outside);
--   2 active on day 31 (D30 window 30..36). 3 of them later delete their account.
create temp table t_ids as
  select gen_random_uuid() as mid, n from generate_series(1, 10) n;
insert into private.metrics_subjects (metrics_id, activated_on, main_drink)
  select mid, date '2026-01-05', case when n <= 5 then 'wine'::public.drink else 'beer'::public.drink end from t_ids;
insert into private.metrics_activity (metrics_id, day)
  select mid, date '2026-01-05' + 1 from t_ids
  union all select mid, date '2026-01-05' + 9 from t_ids where n <= 4
  union all select mid, date '2026-01-05' + 14 from t_ids where n = 5
  union all select mid, date '2026-01-05' + 31 from t_ids where n in (1, 6);
update private.metrics_subjects set deleted_on = date '2026-01-20' where metrics_id in (select mid from t_ids where n >= 8);

select is((select users from private.metrics_retention('2026-01-01', '2026-01-31', 'week', 5, '2026-06-01') where main_drink = 'all'),
  10, 'deleted accounts stay in their cohort');
select is((select d1 from private.metrics_retention('2026-01-01', '2026-01-31', 'week', 5, '2026-06-01') where main_drink = 'all'),
  1.000, 'D1');
select is((select d7 from private.metrics_retention('2026-01-01', '2026-01-31', 'week', 5, '2026-06-01') where main_drink = 'all'),
  0.400, 'D7 counts activity on days 7 to 13 only');
select is((select d30 from private.metrics_retention('2026-01-01', '2026-01-31', 'week', 5, '2026-06-01') where main_drink = 'all'),
  0.200, 'D30');
select is((select d7 from private.metrics_retention('2026-01-01', '2026-01-31', 'week', 5, '2026-06-01') where main_drink = 'wine'),
  0.800, 'segment by main drink');
select is((select d30 from private.metrics_retention('2026-01-01', '2026-01-31', 'week', 5, '2026-01-20') where main_drink = 'all'),
  null, 'immature cohorts have no D30 yet');
select is((select count(*)::int from private.metrics_retention('2026-01-01', '2026-01-31', 'week', 11, '2026-06-01')), 0,
  'small cohorts are hidden');

-- Account deletion keeps the anonymous subject.
select private.snapshot_daily_metrics(private.metrics_today());
delete from auth.users where id = 'b4000000-0000-4000-8000-00000000000a';
select is((select count(*)::int from private.metrics_subjects where deleted_on = private.metrics_today()
           and activated_on = private.metrics_today()), 1, 'a deleted account leaves an anonymous subject with its deletion day');

-- Daily snapshot.
set local role service_role;
select is((public.service_metrics_dashboard(30) -> 'daily' -> -1 ->> 'activations')::int >= 1, true,
  'the dashboard returns the daily snapshot');
reset role;

select * from finish();
rollback;
