-- Test helpers for pgTAP (supabase/tests). Loaded by `supabase db reset` on local
-- databases only: seeds are never applied to hosted projects.

create extension if not exists pgtap with schema extensions;

create schema if not exists tests;
grant usage on schema tests to authenticated, anon;

-- Creates an auth user (and, through the trigger, its profile). Returns its id.
create or replace function tests.create_user(p_phone text, p_id uuid default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := coalesce(p_id, gen_random_uuid());
begin
  insert into auth.users (instance_id, id, aud, role, phone, phone_confirmed_at,
                          raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated',
          p_phone, now(), '{"provider":"phone","providers":["phone"]}', '{}', now(), now());
  return uid;
end;
$$;

-- Creates a user with identity, consents and a valid intent: ready for most tests.
-- Calls the RPCs as the current role (postgres) with the user's JWT claims, so
-- no role switch happens (SET ROLE is forbidden in SECURITY DEFINER functions).
create or replace function tests.create_onboarded_user(
  p_phone text,
  p_id uuid default null,
  p_gender public.gender default 'woman',
  p_seeking public.gender[] default array['man']::public.gender[],
  p_drinks public.drink[] default array['wine']::public.drink[],
  p_structure public.relationship_structure default 'monogamous',
  p_activate boolean default true  -- false: stay in 'onboarding' (onboarding tests)
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  uid uuid := tests.create_user(p_phone, p_id);
  previous_claims text := current_setting('request.jwt.claims', true);
begin
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  perform public.grant_consent('terms', 1);
  perform public.grant_consent('privacy', 1);
  perform public.grant_consent('sensitive_data', 1);
  perform public.set_my_birth_date((current_date - interval '30 years')::date);
  perform public.set_my_identity('Test', p_gender);
  perform public.set_my_seeking(p_seeking);
  perform public.set_my_intent('single', p_drinks, p_structure);
  if p_activate then
    update public.profiles set status = 'active' where id = uid;
  end if;
  perform set_config('request.jwt.claims', coalesce(previous_claims, ''), true);
  return uid;
end;
$$;

-- Impersonates a user for the rest of the transaction (role + JWT claims).
create or replace function tests.authenticate_as(p_user_id uuid)
returns void
language plpgsql
set search_path = ''
as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_user_id, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

-- Back to an unauthenticated context. From `authenticated`, use `reset role;`
-- in the test file to become postgres again.
create or replace function tests.clear_authentication()
returns void
language plpgsql
set search_path = ''
as $$
begin
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'anon', true);
end;
$$;

grant execute on all functions in schema tests to authenticated, anon;
