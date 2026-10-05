-- Domain enums and reference tables. Codes match packages/shared/src/domain.ts.

create type public.drink as enum ('wine', 'coffee', 'cocktail', 'beer');
create type public.gender as enum ('woman', 'man', 'non_binary');
create type public.situation as enum ('single', 'consensual_relationship', 'closed_couple');
create type public.relationship_structure as enum (
  'monogamous', 'open_to_explore', 'open_relationship', 'polyamorous'
);
create type public.profile_status as enum ('onboarding', 'active', 'paused', 'suspended', 'closed');
create type public.verification_status as enum ('unverified', 'pending', 'verified', 'rejected');
create type public.location_source as enum ('device', 'home');
create type public.consent_type as enum ('terms', 'privacy', 'sensitive_data', 'ai_photo_analysis');

-- Drinks -------------------------------------------------------------------

create table public.drinks (
  code public.drink primary key,
  is_romantic boolean not null,
  sort_order smallint not null unique
);

insert into public.drinks (code, is_romantic, sort_order) values
  ('wine', true, 1),
  ('coffee', true, 2),
  ('cocktail', true, 3),
  ('beer', false, 4);

-- Spec §1. Editable without redeploying; must stay symmetric (checked by tests).
create table public.drink_compatibility (
  drink_a public.drink not null references public.drinks (code),
  drink_b public.drink not null references public.drinks (code),
  compatible boolean not null,
  primary key (drink_a, drink_b)
);

insert into public.drink_compatibility (drink_a, drink_b, compatible) values
  ('wine', 'wine', true),      ('wine', 'coffee', true),      ('wine', 'cocktail', false),     ('wine', 'beer', false),
  ('coffee', 'wine', true),    ('coffee', 'coffee', true),    ('coffee', 'cocktail', true),    ('coffee', 'beer', false),
  ('cocktail', 'wine', false), ('cocktail', 'coffee', true),  ('cocktail', 'cocktail', true),  ('cocktail', 'beer', false),
  ('beer', 'wine', false),     ('beer', 'coffee', false),     ('beer', 'cocktail', false),     ('beer', 'beer', true);

-- Spec §2. "Ouvert à voir" goes with everything; the others only with themselves.
create table public.structure_compatibility (
  structure_a public.relationship_structure not null,
  structure_b public.relationship_structure not null,
  compatible boolean not null,
  primary key (structure_a, structure_b)
);

insert into public.structure_compatibility (structure_a, structure_b, compatible)
select a, b, (a = b or a = 'open_to_explore' or b = 'open_to_explore')
from unnest(enum_range(null::public.relationship_structure)) a
cross join unnest(enum_range(null::public.relationship_structure)) b;

-- Written questions (labels live in the app i18n files, keyed by code).
create table public.prompt_questions (
  code text primary key check (code ~ '^[a-z_]+$'),
  sort_order smallint not null,
  active boolean not null default true
);

insert into public.prompt_questions (code, sort_order) values
  ('perfect_sunday', 1),
  ('green_flag', 2),
  ('unpopular_opinion', 3),
  ('ideal_first_date', 4),
  ('currently_learning', 5),
  ('never_without', 6),
  ('best_travel_memory', 7),
  ('makes_me_laugh', 8),
  ('simple_pleasure', 9),
  ('looking_for_someone_who', 10);

-- Orientation labels (optional, never used for matching). Labels in i18n.
create table public.orientation_labels (
  code text primary key check (code ~ '^[a-z_]+$'),
  sort_order smallint not null,
  active boolean not null default true
);

insert into public.orientation_labels (code, sort_order) values
  ('heterosexual', 1), ('gay', 2), ('lesbian', 3), ('bisexual', 4), ('pansexual', 5),
  ('asexual', 6), ('queer', 7), ('questioning', 8), ('other', 9);

-- Reference data is readable by any signed-in user, writable by nobody through the API.
do $$
declare
  t text;
begin
  foreach t in array array['drinks', 'drink_compatibility', 'structure_compatibility',
                           'prompt_questions', 'orientation_labels']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke insert, update, delete, truncate on public.%I from authenticated', t);
    execute format('create policy %I on public.%I for select to authenticated using (true)', t || '_read', t);
  end loop;
end;
$$;
