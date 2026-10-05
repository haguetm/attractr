begin;
select plan(9);

select tests.create_onboarded_user('33639982201', 'a3000000-0000-4000-8000-000000000001');
select tests.authenticate_as('a3000000-0000-4000-8000-000000000001');

select is((select count(*)::int from public.consents where withdrawn_at is null), 3,
  'onboarding recorded terms, privacy and sensitive-data consents');
select lives_ok($$ select public.grant_consent('terms', 1) $$, 'granting the same version twice is a no-op');
select is((select count(*)::int from public.consents where type = 'terms'), 1, 'no duplicate consent row');
select throws_ok($$ select public.grant_consent('terms', 99) $$, 'P0001', 'unknown_consent_version',
  'only published versions can be accepted');

-- A new version supersedes the previous consent, keeping its history.
reset role;
insert into public.consent_texts (type, version, content_sha256) values ('privacy', 2, 'draft-v2');
select tests.authenticate_as('a3000000-0000-4000-8000-000000000001');
select public.grant_consent('privacy', 2);
select results_eq(
  $$ select version, withdrawn_at is null from public.consents where type = 'privacy' order by version $$,
  $$ values (1, false), (2, true) $$,
  'new version supersedes the old one, history kept');

select throws_ok($$ select public.withdraw_consent('terms') $$, 'P0001', 'consent_requires_account_deletion',
  'terms are withdrawn by deleting the account');

-- One-click withdrawal of the sensitive-data consent erases the sensitive fields.
select public.withdraw_consent('sensitive_data');
reset role;
select is_empty(
  $$ select 1 from private.profile_sensitive where user_id = 'a3000000-0000-4000-8000-000000000001' $$,
  'withdrawing sensitive-data consent deletes the encrypted fields');
select ok(
  (select withdrawn_at is not null from public.consents
   where user_id = 'a3000000-0000-4000-8000-000000000001' and type = 'sensitive_data'),
  'withdrawal is dated');
select tests.authenticate_as('a3000000-0000-4000-8000-000000000001');
select throws_ok($$ select public.set_my_seeking('{man}') $$, 'P0001', 'sensitive_consent_required',
  'no sensitive write after withdrawal');

select * from finish();
rollback;
