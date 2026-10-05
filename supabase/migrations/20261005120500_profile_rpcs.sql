-- Profile rules and the RPCs the app uses to write a profile.
-- private.validate_intent is mirrored by packages/shared/src/intent.ts (UI only).

create function private.validate_intent(
  p_situation public.situation,
  p_drinks public.drink[],
  p_structure public.relationship_structure,
  p_composition jsonb,
  p_open_to_couples boolean,
  p_structure_enabled boolean default true,
  p_composition_enabled boolean default true
)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  n integer := coalesce(cardinality(p_drinks), 0);
  romantic boolean := p_drinks && array['wine', 'coffee', 'cocktail']::public.drink[];
  kinds jsonb;
  tpg jsonb;
begin
  if n < 1 or n > 2 then return 'drinks_count'; end if;
  if (select count(distinct d) from unnest(p_drinks) d) <> n then return 'drinks_duplicate'; end if;
  if n = 2 and not ('beer' = any (p_drinks)) then return 'drinks_combination'; end if;
  if p_situation = 'closed_couple' and p_drinks <> array['beer']::public.drink[] then
    return 'closed_couple_beer_only';
  end if;

  if not romantic or not p_structure_enabled then
    if p_structure is not null then
      return case when romantic then 'structure_disabled_in_country' else 'structure_not_allowed' end;
    end if;
  else
    if p_structure is null then return 'structure_required'; end if;
    if p_situation = 'consensual_relationship' and p_structure = 'monogamous' then
      return 'structure_incoherent_with_situation';
    end if;
  end if;

  if p_composition is not null and p_composition <> 'null'::jsonb then
    if not p_composition_enabled then return 'composition_disabled_in_country'; end if;
    if p_structure is distinct from 'polyamorous' then return 'composition_requires_polyamory'; end if;
    kinds := p_composition -> 'kinds';
    tpg := coalesce(p_composition -> 'three_plus_genders', 'null'::jsonb);
    if jsonb_typeof(kinds) is distinct from 'array' then return 'composition_invalid'; end if;
    if jsonb_array_length(kinds) = 0 then return 'composition_empty'; end if;
    if exists (
      select 1 from jsonb_array_elements_text(kinds) k
      where k not in ('one_woman', 'one_man', 'one_any', 'woman_and_man', 'two_women', 'two_men', 'three_plus')
    ) or (select count(*) from jsonb_array_elements_text(kinds))
         <> (select count(distinct k) from jsonb_array_elements_text(kinds) k) then
      return 'composition_invalid';
    end if;
    if tpg <> 'null'::jsonb then
      if not (kinds ? 'three_plus') or jsonb_typeof(tpg) <> 'array' or jsonb_array_length(tpg) = 0 then
        return 'composition_three_plus_genders';
      end if;
      if exists (
        select 1 from jsonb_array_elements_text(tpg) g where g not in ('woman', 'man', 'non_binary')
      ) then
        return 'composition_invalid';
      end if;
    end if;
  end if;

  if p_open_to_couples and not romantic then return 'open_to_couples_requires_romantic'; end if;

  return null;
end;
$$;

create function private.require_sensitive_consent(p_user_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.has_consent(p_user_id, 'sensitive_data') then
    raise exception 'sensitive_consent_required';
  end if;
end;
$$;

-- Onboarding step 2 (identity). The birth date cannot change once set: it is the
-- declared age that the selfie age estimate is checked against.
create function public.set_my_identity(
  p_first_name text,
  p_birth_date date,
  p_gender public.gender,
  p_gender_detail text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  current_birth date;
begin
  select birth_date into current_birth from public.profiles where id = uid;
  if current_birth is not null and current_birth <> p_birth_date then
    raise exception 'birth_date_locked';
  end if;
  update public.profiles
     set first_name = btrim(p_first_name),
         birth_date = p_birth_date,
         gender = p_gender,
         gender_detail = nullif(btrim(p_gender_detail), '')
   where id = uid;
end;
$$;

-- Genders sought: mandatory for romance; friend genders default to everyone (Q2).
create function public.set_my_seeking(
  p_seeking_genders public.gender[],
  p_friend_genders public.gender[] default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  friends public.gender[] := coalesce(p_friend_genders, enum_range(null::public.gender));
begin
  perform private.require_sensitive_consent(uid);
  if coalesce(cardinality(p_seeking_genders), 0) = 0 then
    raise exception 'seeking_genders_required';
  end if;
  if cardinality(friends) = 0 then
    raise exception 'friend_genders_required';
  end if;
  perform private.write_sensitive(uid, jsonb_build_object(
    'seeking_genders', to_jsonb(array(select distinct g from unnest(p_seeking_genders) g order by g)),
    'friend_genders', to_jsonb(array(select distinct g from unnest(friends) g order by g))
  ));
end;
$$;

-- Situation, drinks, structure, composition and "ouvert aux couples", validated
-- together because the rules cross these fields (spec §1-2, DECISIONS Q1-Q4, Q12).
create function public.set_my_intent(
  p_situation public.situation,
  p_drinks public.drink[],
  p_structure public.relationship_structure default null,
  p_composition jsonb default null,
  p_open_to_couples boolean default false
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  prof public.profiles;
  sw public.country_config;
  err text;
  old_drinks public.drink[];
  new_drinks public.drink[] := array(select distinct d from unnest(p_drinks) d order by d);
begin
  perform private.require_sensitive_consent(uid);
  select * into prof from public.profiles where id = uid for update;
  sw := private.country_switches(prof.country_code);

  err := private.validate_intent(p_situation, p_drinks, p_structure, p_composition,
                                 p_open_to_couples, sw.structure_enabled, sw.composition_enabled);
  if err is not null then
    raise exception '%', err;
  end if;

  select array_agg(drink order by drink) into old_drinks
    from public.profile_drinks where user_id = uid;

  if old_drinks is null then
    insert into private.drink_change_history (user_id, old_drinks, new_drinks, reason)
      values (uid, null, new_drinks, 'initial');
  elsif old_drinks <> new_drinks then
    if prof.drinks_changed_at is not null
       and prof.drinks_changed_at > now() - make_interval(days => private.config_int('drinks.change_cooldown_days')) then
      raise exception 'drink_change_cooldown';
    end if;
    insert into private.drink_change_history (user_id, old_drinks, new_drinks, reason)
      values (uid, old_drinks, new_drinks, 'user');
    update public.profiles set drinks_changed_at = now() where id = uid;
  end if;

  if old_drinks is distinct from new_drinks then
    delete from public.profile_drinks where user_id = uid;
    insert into public.profile_drinks (user_id, drink) select uid, unnest(new_drinks);
  end if;

  update public.profiles set open_to_couples = p_open_to_couples where id = uid;

  perform private.write_sensitive(uid, jsonb_build_object(
    'situation', p_situation,
    'structure', p_structure,
    'composition', case when p_composition = 'null'::jsonb then null else p_composition end
  ));
end;
$$;

-- Optional orientation label; never used for matching (spec §2).
create function public.set_my_orientation(p_label text, p_visible boolean default false)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  sw public.country_config;
begin
  perform private.require_sensitive_consent(uid);
  sw := private.country_switches((select country_code from public.profiles where id = uid));
  if p_label is not null then
    if not sw.orientation_enabled then
      raise exception 'orientation_disabled_in_country';
    end if;
    if not exists (select 1 from public.orientation_labels where code = p_label and active) then
      raise exception 'unknown_orientation_label';
    end if;
  end if;
  perform private.write_sensitive(uid, jsonb_build_object(
    'orientation', p_label,
    'orientation_visible', case when p_label is null then null else p_visible end
  ));
end;
$$;

-- Position: snapped before storage, the exact point is never persisted.
-- The country is set server-side by geocoding (phase 2), never by the client.
create function public.set_my_location(
  p_lat double precision,
  p_lon double precision,
  p_source public.location_source default 'device'
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
begin
  update public.profiles
     set location = private.snap_point(p_lat, p_lon),
         location_source = p_source
   where id = uid;
end;
$$;

-- The caller's own full profile, sensitive fields decrypted (settings screens).
create function public.get_my_profile()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
begin
  return (
    select jsonb_build_object(
      'id', p.id,
      'status', p.status,
      'first_name', p.first_name,
      'birth_date', p.birth_date,
      'gender', p.gender,
      'gender_detail', p.gender_detail,
      'bio', p.bio,
      'open_to_couples', p.open_to_couples,
      'alcohol_free_icons', p.alcohol_free_icons,
      'verification_status', p.verification_status,
      'country_code', p.country_code,
      'drinks_changed_at', p.drinks_changed_at,
      'drinks', coalesce((select jsonb_agg(d.drink order by d.drink)
                          from public.profile_drinks d where d.user_id = p.id), '[]'::jsonb),
      'prompts', coalesce((select jsonb_agg(jsonb_build_object(
                             'position', q.position, 'question_code', q.question_code, 'answer', q.answer)
                           order by q.position)
                          from public.profile_prompts q where q.user_id = p.id), '[]'::jsonb),
      'sensitive', private.read_sensitive(p.id)
    )
    from public.profiles p where p.id = uid
  );
end;
$$;

do $$
declare
  f text;
begin
  foreach f in array array[
    'public.set_my_identity(text, date, public.gender, text)',
    'public.set_my_seeking(public.gender[], public.gender[])',
    'public.set_my_intent(public.situation, public.drink[], public.relationship_structure, jsonb, boolean)',
    'public.set_my_orientation(text, boolean)',
    'public.set_my_location(double precision, double precision, public.location_source)',
    'public.get_my_profile()'
  ]
  loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end;
$$;
