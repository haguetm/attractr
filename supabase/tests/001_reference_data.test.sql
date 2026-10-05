begin;
select plan(9);

-- Drink matrix (spec §1) ----------------------------------------------------
select is((select count(*)::int from public.drink_compatibility), 16, 'drink matrix covers the 16 pairs');

select results_eq(
  $$ select drink_a::text, drink_b::text from public.drink_compatibility where compatible order by 1, 2 $$,
  $$ values ('beer', 'beer'), ('cocktail', 'cocktail'), ('cocktail', 'coffee'), ('coffee', 'cocktail'),
            ('coffee', 'coffee'), ('coffee', 'wine'), ('wine', 'coffee'), ('wine', 'wine') $$,
  'compatible drink pairs are exactly those of the spec'
);

select is_empty(
  $$ select 1 from public.drink_compatibility a
     join public.drink_compatibility b on a.drink_a = b.drink_b and a.drink_b = b.drink_a
     where a.compatible <> b.compatible $$,
  'drink matrix is symmetric'
);

-- Structure matrix (spec §2) ------------------------------------------------
select is((select count(*)::int from public.structure_compatibility), 16, 'structure matrix covers the 16 pairs');

select results_eq(
  $$ select structure_a::text, structure_b::text from public.structure_compatibility where compatible order by 1, 2 $$,
  $$ values ('monogamous', 'monogamous'), ('monogamous', 'open_to_explore'),
            ('open_relationship', 'open_relationship'), ('open_relationship', 'open_to_explore'),
            ('open_to_explore', 'monogamous'), ('open_to_explore', 'open_relationship'),
            ('open_to_explore', 'open_to_explore'), ('open_to_explore', 'polyamorous'),
            ('polyamorous', 'open_to_explore'), ('polyamorous', 'polyamorous') $$,
  'compatible structure pairs are exactly those of the spec'
);

select is_empty(
  $$ select 1 from public.structure_compatibility a
     join public.structure_compatibility b on a.structure_a = b.structure_b and a.structure_b = b.structure_a
     where a.compatible <> b.compatible $$,
  'structure matrix is symmetric'
);

-- Configuration ---------------------------------------------------------------
select is(private.config_int('likes.free_quota'), 25, 'free like quota defaults to 25');
select throws_ok($$ select private.config('nope.missing') $$, 'P0001', 'config_missing: nope.missing',
  'a missing config key fails loudly');
select is((private.country_switches('ZZ')).country_code, '*', 'unknown country falls back to the default row');

select * from finish();
rollback;
