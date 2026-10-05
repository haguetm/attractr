-- private.validate_intent. Same cases as packages/shared/src/intent.test.ts.
begin;
select plan(27);

create function pg_temp.v(
  p_situation public.situation,
  p_drinks text[],
  p_structure public.relationship_structure,
  p_composition jsonb default null,
  p_open boolean default false,
  p_structure_enabled boolean default true,
  p_composition_enabled boolean default true
) returns text language sql as $$
  select private.validate_intent(p_situation, p_drinks::public.drink[], p_structure, p_composition,
                                 p_open, p_structure_enabled, p_composition_enabled)
$$;

-- Drink combinations
select is(pg_temp.v('single', '{wine}', 'monogamous'), null, 'wine alone');
select is(pg_temp.v('single', '{coffee}', 'monogamous'), null, 'coffee alone');
select is(pg_temp.v('single', '{cocktail}', 'monogamous'), null, 'cocktail alone');
select is(pg_temp.v('single', '{beer}', null), null, 'beer alone');
select is(pg_temp.v('single', '{beer,wine}', 'monogamous'), null, 'beer + wine');
select is(pg_temp.v('single', '{beer,coffee}', 'monogamous'), null, 'beer + coffee');
select is(pg_temp.v('single', '{cocktail,beer}', 'monogamous'), null, 'cocktail + beer');
select is(pg_temp.v('single', '{wine,coffee}', 'monogamous'), 'drinks_combination', 'two romantic drinks rejected');
select is(pg_temp.v('single', '{}', null), 'drinks_count', 'no drink rejected');
select is(pg_temp.v('single', '{beer,wine,coffee}', 'monogamous'), 'drinks_count', 'three drinks rejected');
select is(pg_temp.v('single', '{beer,beer}', null), 'drinks_duplicate', 'duplicated drink rejected');

-- Situation
select is(pg_temp.v('closed_couple', '{beer}', null), null, 'closed couple with beer');
select is(pg_temp.v('closed_couple', '{beer,wine}', 'monogamous'), 'closed_couple_beer_only', 'closed couple cannot add wine');
select is(pg_temp.v('consensual_relationship', '{wine}', 'monogamous'), 'structure_incoherent_with_situation', 'Q3: no monogamy when in a consensual relationship');
select is(pg_temp.v('consensual_relationship', '{coffee}', 'polyamorous'), null, 'consensual relationship + polyamory');

-- Structure
select is(pg_temp.v('single', '{wine}', null), 'structure_required', 'structure required with a romantic drink');
select is(pg_temp.v('single', '{beer}', 'monogamous'), 'structure_not_allowed', 'no structure with beer only');
select is(pg_temp.v('single', '{wine}', null, null, false, false, false), null, 'structure skipped when disabled in country');
select is(pg_temp.v('single', '{wine}', 'monogamous', null, false, false, false), 'structure_disabled_in_country', 'structure refused when disabled in country');

-- Composition
select is(pg_temp.v('single', '{wine}', 'polyamorous', '{"kinds":["one_woman","two_men"]}'), null, 'poly composition accepted');
select is(pg_temp.v('single', '{wine}', 'polyamorous', '{"kinds":["three_plus"],"three_plus_genders":["woman"]}'), null, 'three or more with genders');
select is(pg_temp.v('single', '{wine}', 'open_to_explore', '{"kinds":["one_man"]}'), 'composition_requires_polyamory', 'composition needs polyamory');
select is(pg_temp.v('single', '{wine}', 'polyamorous', '{"kinds":[]}'), 'composition_empty', 'empty composition rejected');
select is(pg_temp.v('single', '{wine}', 'polyamorous', '{"kinds":["one_man"],"three_plus_genders":["man"]}'), 'composition_three_plus_genders', 'genders only with three or more');
select is(pg_temp.v('single', '{wine}', 'polyamorous', '{"kinds":["harem"]}'), 'composition_invalid', 'unknown composition rejected');

-- Open to couples
select is(pg_temp.v('single', '{coffee}', 'open_to_explore', null, true), null, 'open to couples with a romantic drink');
select is(pg_temp.v('single', '{beer}', null, null, true), 'open_to_couples_requires_romantic', 'open to couples needs a romantic drink');

select * from finish();
rollback;
