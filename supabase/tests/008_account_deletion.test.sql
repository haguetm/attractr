-- Deleting the auth user (done by the delete-account Edge Function) erases every row.
begin;
select plan(7);

select tests.create_onboarded_user('33639982501', 'a6000000-0000-4000-8000-000000000001');
insert into public.profile_prompts (user_id, position, question_code, answer)
  values ('a6000000-0000-4000-8000-000000000001', 1, 'perfect_sunday', 'Marché puis sieste');

delete from auth.users where id = 'a6000000-0000-4000-8000-000000000001';

select is_empty($$ select 1 from public.profiles where id = 'a6000000-0000-4000-8000-000000000001' $$, 'profile erased');
select is_empty($$ select 1 from public.profile_drinks where user_id = 'a6000000-0000-4000-8000-000000000001' $$, 'drinks erased');
select is_empty($$ select 1 from public.profile_prompts where user_id = 'a6000000-0000-4000-8000-000000000001' $$, 'answers erased');
select is_empty($$ select 1 from public.consents where user_id = 'a6000000-0000-4000-8000-000000000001' $$, 'consents erased');
select is_empty($$ select 1 from private.profile_sensitive where user_id = 'a6000000-0000-4000-8000-000000000001' $$, 'sensitive fields erased');
select is_empty($$ select 1 from private.drink_change_history where user_id = 'a6000000-0000-4000-8000-000000000001' $$, 'drink history erased');

-- Guard for future migrations: every FK to profiles/auth.users must cascade, or be set to
-- null when a shared row outlives the person (e.g. a group they created).
select is_empty(
  $$ select conrelid::regclass::text from pg_constraint
     where contype = 'f' and confrelid in ('public.profiles'::regclass, 'auth.users'::regclass)
       and confdeltype not in ('c', 'n')
       and connamespace in ('public'::regnamespace, 'private'::regnamespace) $$,
  'every foreign key to a user is erased with the account');

select * from finish();
rollback;
