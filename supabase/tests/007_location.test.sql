-- Positions are snapped to ~1 km before storage; exact coordinates never persist.
begin;
select plan(5);

select tests.create_onboarded_user('33639982401', 'a5000000-0000-4000-8000-000000000001');
select tests.authenticate_as('a5000000-0000-4000-8000-000000000001');
select public.set_my_location(48.856613, 2.352222);
reset role;

select ok(
  (select not extensions.st_equals(location::extensions.geometry,
                                   extensions.st_setsrid(extensions.st_makepoint(2.352222, 48.856613), 4326))
   from public.profiles where id = 'a5000000-0000-4000-8000-000000000001'),
  'the exact position is not stored');

select ok(
  (select abs(extensions.st_y(location::extensions.geometry) / 0.009
              - round(extensions.st_y(location::extensions.geometry) / 0.009)) < 1e-9
   from public.profiles where id = 'a5000000-0000-4000-8000-000000000001'),
  'stored latitude sits on the ~1 km grid');

select cmp_ok(
  (select extensions.st_distance(location,
            extensions.st_setsrid(extensions.st_makepoint(2.352222, 48.856613), 4326)::extensions.geography)
   from public.profiles where id = 'a5000000-0000-4000-8000-000000000001'),
  '<', 710::double precision, 'snapped position stays within ~700 m of the real one');

select ok(
  extensions.st_equals(private.snap_point(48.8566, 2.3522)::extensions.geometry,
                       private.snap_point(48.8569, 2.3525)::extensions.geometry),
  'two nearby positions fall in the same cell');

select throws_ok($$ select private.snap_point(91, 0) $$, 'P0001', 'invalid_coordinates',
  'out-of-range coordinates are rejected');

select * from finish();
rollback;
