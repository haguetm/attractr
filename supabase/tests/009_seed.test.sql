-- The generated seed (supabase/seeds/20_profiles.sql) loads and satisfies the database rules.
begin;
select plan(7);

select is((select count(*)::int from public.profiles where is_seed), 100, '100 seed profiles');
select is((select count(*)::int from public.profiles where is_seed and status = 'active' and location is not null), 100,
  'every seed profile is active and located');
select is((select count(*)::int from private.profile_sensitive s join public.profiles p on p.id = s.user_id where p.is_seed), 100,
  'every seed profile has encrypted sensitive fields');

-- Re-validate every seed profile with the SQL rules, from decrypted data.
select is_empty($$
  with d as (
    select p.id, p.open_to_couples, private.read_sensitive(p.id) as s,
           (select array_agg(drink order by drink) from public.profile_drinks where user_id = p.id) as drinks
    from public.profiles p where p.is_seed
  )
  select id from d
  where private.validate_intent((s ->> 'situation')::public.situation, drinks,
                                (s ->> 'structure')::public.relationship_structure,
                                s -> 'composition', open_to_couples) is not null
     or jsonb_array_length(s -> 'seeking_genders') = 0
$$, 'every seed profile passes validate_intent and has sought genders');

select is(
  (select count(distinct combo)::int from (
     select string_agg(drink::text, '+' order by drink) combo from public.profile_drinks d
     join public.profiles p on p.id = d.user_id where p.is_seed group by d.user_id) c),
  7, 'all 7 drink combinations are present');

select ok((select count(*) from public.profiles where is_seed and verification_status = 'verified') > 0
      and (select count(*) from public.profiles where is_seed and verification_status <> 'verified') > 0,
  'verified and unverified profiles are present');

select is((select count(*)::int from public.profile_prompts q join public.profiles p on p.id = q.user_id where p.is_seed), 300,
  'three written answers per seed profile');

select * from finish();
rollback;
