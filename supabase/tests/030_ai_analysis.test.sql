-- AI profile analysis: separate consent, weekly limit, guarded result, free vs Premium view,
-- deletion on consent withdrawal.
begin;
select plan(23);

select tests.create_onboarded_user('33639983401', 'b3000000-0000-4000-8000-00000000000a', 'woman', '{man}');
select tests.create_onboarded_user('33639983402', 'b3000000-0000-4000-8000-00000000000b', 'man', '{woman}');
update public.profiles set bio = 'J''aime les voyages et rire.' where id = 'b3000000-0000-4000-8000-00000000000a';
insert into public.photos (id, user_id, storage_path, position, moderation_status) values
  ('b3100000-0000-4000-8000-000000000001', 'b3000000-0000-4000-8000-00000000000a', 'b3000000-0000-4000-8000-00000000000a/1.jpg', 1, 'approved'),
  ('b3100000-0000-4000-8000-000000000002', 'b3000000-0000-4000-8000-00000000000a', 'b3000000-0000-4000-8000-00000000000a/2.jpg', 2, 'approved'),
  ('b3100000-0000-4000-8000-000000000003', 'b3000000-0000-4000-8000-00000000000a', 'b3000000-0000-4000-8000-00000000000a/3.jpg', 3, 'pending'),
  ('b3100000-0000-4000-8000-000000000009', 'b3000000-0000-4000-8000-00000000000b', 'b3000000-0000-4000-8000-00000000000b/1.jpg', 1, 'approved');

create temp table t_result as select jsonb_build_object(
  'photos', jsonb_build_array(
    jsonb_build_object('photo_id', 'b3100000-0000-4000-8000-000000000001', 'strength', 'Lumière naturelle.', 'improvement', 'Recadre plus serré.'),
    jsonb_build_object('photo_id', 'b3100000-0000-4000-8000-000000000002', 'strength', 'Activité visible.', 'improvement', 'Évite le contre-jour.')),
  'photo_order', jsonb_build_array('b3100000-0000-4000-8000-000000000002', 'b3100000-0000-4000-8000-000000000001'),
  'bio', jsonb_build_object('cliches', jsonb_build_array('J''aime les voyages'), 'rewrite', 'Toujours un billet de train en poche.', 'drink_fit', 'Cohérent avec le vin.'),
  'top_tip', 'Commence par la photo où l''on te voit en activité.') as r;
grant select on t_result to service_role;

-- Consent is separate and required.
set local role service_role;
select throws_ok($$ select public.service_claim_ai_analysis('b3000000-0000-4000-8000-00000000000a') $$,
  'P0001', 'ai_consent_required', 'no analysis without the separate AI consent');
reset role;

select tests.authenticate_as('b3000000-0000-4000-8000-00000000000a');
select public.grant_consent('ai_photo_analysis', 1);
select is((public.get_my_ai_analysis() ->> 'consent')::boolean, true, 'the consent shows in the analysis state');
select is(public.get_my_ai_analysis() -> 'analysis', 'null'::jsonb, 'no analysis yet');
select throws_ok($$ select public.service_claim_ai_analysis('b3000000-0000-4000-8000-00000000000a') $$,
  '42501', null, 'the app cannot call the service functions');
reset role;

-- Claim: only approved photos, no identity fields.
set local role service_role;
create temp table t_claim as select public.service_claim_ai_analysis('b3000000-0000-4000-8000-00000000000a') as c;
select is((select jsonb_array_length(c -> 'photos') from t_claim), 2, 'photos not yet approved are not sent');
select is((select c -> 'drinks' from t_claim), '["wine"]'::jsonb, 'drinks are sent for the coherence check');
select ok((select not (c ? 'first_name') and not (c ? 'birth_date') and not (c ? 'gender') from t_claim),
  'no name, age or gender is sent to the provider');
select throws_ok($$ select public.service_claim_ai_analysis('b3000000-0000-4000-8000-00000000000a') $$,
  'P0001', 'ai_analysis_rate_limited', 'a running analysis holds the slot');

-- A failure frees the slot.
select public.service_release_ai_analysis((select (c ->> 'analysis_id')::uuid from t_claim));
delete from t_claim;
insert into t_claim select public.service_claim_ai_analysis('b3000000-0000-4000-8000-00000000000a');
select is((select count(*)::int from t_claim), 1, 'after a provider failure the user can try again');

-- Result validation.
select throws_ok($$ select public.service_record_ai_analysis((select (c ->> 'analysis_id')::uuid from t_claim), 'm',
  jsonb_set((select r from t_result), '{photo_order,0}', '"b3100000-0000-4000-8000-000000000009"')) $$,
  'P0001', 'ai_result_invalid', 'a result naming someone else''s photo is refused');
select throws_ok($$ select public.service_record_ai_analysis((select (c ->> 'analysis_id')::uuid from t_claim), 'm', '{"top_tip": 1}') $$,
  'P0001', 'ai_result_invalid', 'a malformed result is refused');
select lives_ok($$ select public.service_record_ai_analysis((select (c ->> 'analysis_id')::uuid from t_claim), 'claude-test', (select r from t_result)) $$,
  'a valid result is recorded');
select throws_ok($$ select public.service_claim_ai_analysis('b3000000-0000-4000-8000-00000000000a') $$,
  'P0001', 'ai_analysis_rate_limited', 'one analysis per week');
reset role;

-- Free view: one tip, the rest locked.
select tests.authenticate_as('b3000000-0000-4000-8000-00000000000a');
select is(public.get_my_ai_analysis() #>> '{analysis,top_tip}', 'Commence par la photo où l''on te voit en activité.', 'free users get one tip');
select ok(not (public.get_my_ai_analysis() -> 'analysis' ? 'photos') and not (public.get_my_ai_analysis() -> 'analysis' ? 'bio'),
  'free users do not get the full analysis');
select is(public.get_my_ai_analysis() #> '{analysis,locked}', '{"photos": 2, "has_bio_rewrite": true}'::jsonb, 'free users see what Premium unlocks');
select ok((public.get_my_ai_analysis() ->> 'next_available_at')::timestamptz > now() + interval '6 days', 'the next analysis date is shown');
reset role;

-- Premium view: the cached full result, without a new provider call.
insert into private.entitlements (user_id, entitlement, source) values ('b3000000-0000-4000-8000-00000000000a', 'premium', 'test');
delete from public.photos where id = 'b3100000-0000-4000-8000-000000000001';
select tests.authenticate_as('b3000000-0000-4000-8000-00000000000a');
select is(public.get_my_ai_analysis() #>> '{analysis,bio,rewrite}', 'Toujours un billet de train en poche.', 'Premium users get the bio rewrite');
select is(public.get_my_ai_analysis() #> '{analysis,photo_order}', '["b3100000-0000-4000-8000-000000000002"]'::jsonb,
  'deleted photos are left out of the suggested order');
select is(jsonb_array_length(public.get_my_ai_analysis() #> '{analysis,photos}'), 1, 'and out of the per-photo advice');

-- Withdrawal deletes the analyses.
select public.withdraw_consent('ai_photo_analysis');
reset role;
select is((select count(*)::int from private.ai_analyses where user_id = 'b3000000-0000-4000-8000-00000000000a'), 0,
  'withdrawing the consent deletes the analyses');

-- A consent withdrawn during the call discards the result.
select tests.authenticate_as('b3000000-0000-4000-8000-00000000000b');
select public.grant_consent('ai_photo_analysis', 1);
reset role;
set local role service_role;
delete from t_claim;
insert into t_claim select public.service_claim_ai_analysis('b3000000-0000-4000-8000-00000000000b');
reset role;
update public.consents set withdrawn_at = now()
 where user_id = 'b3000000-0000-4000-8000-00000000000b' and type = 'ai_photo_analysis' and withdrawn_at is null;
set local role service_role;
select is(public.service_record_ai_analysis((select (c ->> 'analysis_id')::uuid from t_claim), 'm',
  '{"photos": [], "photo_order": [], "bio": {}, "top_tip": "x"}'), false, 'a result arriving after withdrawal is discarded');
reset role;
select is((select count(*)::int from private.ai_analyses where user_id = 'b3000000-0000-4000-8000-00000000000b'), 0,
  'and nothing is kept');

select * from finish();
rollback;
