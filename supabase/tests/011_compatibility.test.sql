-- private.match_drinks: same cases as packages/shared/src/compatibility.test.ts.
begin;
select plan(20);

create function pg_temp.m(
  v_gender text, v_drinks text, v_s jsonb,
  c_gender text, c_drinks text, c_s jsonb
) returns text language sql as $$
  select private.match_drinks(v_gender::public.gender, v_drinks::public.drink[], v_s,
                              c_gender::public.gender, c_drinks::public.drink[], c_s)::text
$$;

-- Sensitive documents
create function pg_temp.s(seek text, struct text default 'monogamous', comp jsonb default null, friends text default null)
returns jsonb language sql as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'seeking_genders', to_jsonb(seek::text[]),
    'friend_genders', to_jsonb(friends::text[]),
    'structure', struct,
    'composition', comp))
$$;

-- Drinks and genders
select is(pg_temp.m('woman', '{wine}', pg_temp.s('{man}'), 'man', '{wine}', pg_temp.s('{woman}')), '{wine}', 'wine x wine, genders both ways');
select is(pg_temp.m('woman', '{wine}', pg_temp.s('{man}', 'open_to_explore'), 'man', '{cocktail}', pg_temp.s('{woman}', 'open_to_explore')), '{}', 'wine x cocktail never matches');
select is(pg_temp.m('woman', '{coffee}', pg_temp.s('{man}', 'open_to_explore'), 'man', '{cocktail}', pg_temp.s('{woman}', 'open_to_explore')), '{cocktail}', 'coffee x cocktail matches');
select is(pg_temp.m('woman', '{wine}', pg_temp.s('{man}'), 'man', '{wine}', pg_temp.s('{man}')), '{}', 'sought genders must match both ways');
select is(pg_temp.m('woman', '{wine}', pg_temp.s('{man}'), 'man', '{beer}', pg_temp.s('{woman}', null)), '{}', 'wine x beer never matches');

-- Beer: friend genders, not sought genders (Q2)
select is(pg_temp.m('woman', '{beer}', pg_temp.s('{man}', null), 'woman', '{beer}', pg_temp.s('{man}', null)), '{beer}', 'beer ignores sought genders');
select is(pg_temp.m('woman', '{beer}', pg_temp.s('{man}', null), 'woman', '{beer}', pg_temp.s('{man}', null, null, '{man}')), '{}', 'beer respects friend genders');

-- Structure (spec §2)
select is(pg_temp.m('woman', '{wine}', pg_temp.s('{man}', 'monogamous'), 'man', '{wine}', pg_temp.s('{woman}', 'polyamorous')), '{}', 'monogamous x polyamorous');
select is(pg_temp.m('woman', '{wine}', pg_temp.s('{man}', 'open_relationship'), 'man', '{wine}', pg_temp.s('{woman}', 'polyamorous')), '{}', 'open relationship x polyamorous');
select is(pg_temp.m('woman', '{wine}', pg_temp.s('{man}', 'open_to_explore'), 'man', '{wine}', pg_temp.s('{woman}', 'polyamorous')), '{wine}', 'open to explore goes with everything');
select is(pg_temp.m('woman', '{wine}', pg_temp.s('{man}', null), 'man', '{wine}', pg_temp.s('{woman}', 'polyamorous')), '{wine}', 'missing structure (country switch) sets no constraint');

-- Independent crossings (Q1)
select is(pg_temp.m('woman', '{beer,wine}', pg_temp.s('{man}', 'monogamous'), 'man', '{beer,wine}', pg_temp.s('{woman}', 'polyamorous')), '{beer}', 'beer matches even when the romantic crossing fails');
select is(pg_temp.m('woman', '{beer,coffee}', pg_temp.s('{man}', 'open_to_explore'), 'man', '{beer,cocktail}', pg_temp.s('{woman}', 'open_to_explore')), '{cocktail,beer}', 'every matching drink is reported');

-- Polyamory composition (Q4)
select is(pg_temp.m('woman', '{wine}', pg_temp.s('{man,woman}', 'polyamorous', '{"kinds":["two_women"]}'), 'man', '{wine}', pg_temp.s('{woman}', 'polyamorous')), '{}', 'composition excludes other genders');
select is(pg_temp.m('woman', '{wine}', pg_temp.s('{man,woman}', 'polyamorous', '{"kinds":["two_women"]}'), 'woman', '{wine}', pg_temp.s('{woman}', 'polyamorous')), '{wine}', 'composition accepts a requested gender');
select is(pg_temp.m('man', '{wine}', pg_temp.s('{woman}', 'polyamorous'), 'woman', '{wine}', pg_temp.s('{man}', 'polyamorous', '{"kinds":["one_woman"]}')), '{}', 'composition applies both ways');
select is(private.composition_genders('{"kinds":["three_plus"],"three_plus_genders":null}')::text, '{woman,man,non_binary}', 'three or more, any gender');
select is(private.composition_genders('{"kinds":["woman_and_man","two_men"]}')::text, '{woman,man}', 'genders of several options');

-- The matrix is data: editing it changes matching without a redeploy (spec §1).
update public.drink_compatibility set compatible = true
 where (drink_a, drink_b) in (('wine', 'cocktail'), ('cocktail', 'wine'));
select is(pg_temp.m('woman', '{wine}', pg_temp.s('{man}', 'open_to_explore'), 'man', '{cocktail}', pg_temp.s('{woman}', 'open_to_explore')), '{cocktail}', 'matrix edits apply immediately');

select is(array[private.distance_bucket(4999), private.distance_bucket(5000), private.distance_bucket(120000)],
  array['lt5', 'lt10', 'gte100'], 'distances are shown as ranges');

select * from finish();
rollback;
