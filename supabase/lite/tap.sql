-- Subset of pgTAP used by supabase/tests, for PGlite runs (pgTAP is not bundled).
-- Each assertion returns a TAP line ("ok N - ..." / "not ok N - ...") like pgTAP.
-- Lives in schema `tap`; the runner adds it to the search_path.

create schema tap;
grant usage on schema tap to anon, authenticated, service_role;

create function tap._next() returns integer language sql as $$
  select set_config('tap.n', (coalesce(nullif(current_setting('tap.n', true), ''), '0')::int + 1)::text, false)::int
$$;

create function tap._fail_count(p_add boolean) returns void language sql as $$
  select set_config('tap.failed', (coalesce(nullif(current_setting('tap.failed', true), ''), '0')::int
                                   + case when p_add then 1 else 0 end)::text, false)
$$;

create function tap._result(p_ok boolean, p_desc text, p_diag text default null) returns text language plpgsql as $$
declare
  n integer := tap._next();
begin
  perform tap._fail_count(not coalesce(p_ok, false));
  return case when coalesce(p_ok, false) then 'ok ' else 'not ok ' end || n || ' - ' || coalesce(p_desc, '')
      || case when coalesce(p_ok, false) or p_diag is null then '' else E'\n# ' || p_diag end;
end;
$$;

create function tap.plan(p_count integer) returns text language plpgsql as $$
begin
  perform set_config('tap.n', '0', false), set_config('tap.failed', '0', false),
          set_config('tap.planned', p_count::text, false);
  return '1..' || p_count;
end;
$$;

create function tap.finish() returns setof text language plpgsql as $$
declare
  ran integer := coalesce(nullif(current_setting('tap.n', true), ''), '0')::int;
  planned integer := coalesce(nullif(current_setting('tap.planned', true), ''), '0')::int;
begin
  if ran <> planned then
    return next '# Looks like you planned ' || planned || ' tests but ran ' || ran;
  end if;
end;
$$;

create function tap.ok(p_ok boolean, p_desc text default null) returns text language sql as $$
  select tap._result(p_ok, p_desc)
$$;

create function tap.is(p_have anyelement, p_want anyelement, p_desc text default null) returns text language sql as $$
  select tap._result(p_have is not distinct from p_want, p_desc,
                     'have: ' || coalesce(p_have::text, 'NULL') || ' / want: ' || coalesce(p_want::text, 'NULL'))
$$;

create function tap.cmp_ok(p_have anyelement, p_op text, p_want anyelement, p_desc text default null)
returns text language plpgsql as $$
declare
  res boolean;
begin
  execute format('select $1 %s $2', p_op) into res using p_have, p_want;
  return tap._result(res, p_desc, 'have: ' || coalesce(p_have::text, 'NULL') || ' ' || p_op || ' ' || coalesce(p_want::text, 'NULL'));
end;
$$;

create function tap.is_empty(p_sql text, p_desc text default null) returns text language plpgsql as $$
declare
  found_row boolean;
begin
  execute format('select exists (%s)', p_sql) into found_row;
  return tap._result(not found_row, p_desc, 'query returned rows');
end;
$$;

create function tap.isnt_empty(p_sql text, p_desc text default null) returns text language plpgsql as $$
declare
  found_row boolean;
begin
  execute format('select exists (%s)', p_sql) into found_row;
  return tap._result(found_row, p_desc, 'query returned no rows');
end;
$$;

create function tap.results_eq(p_have text, p_want text, p_desc text default null) returns text language plpgsql as $$
declare
  have text[];
  want text[];
begin
  execute format('select array_agg(t::text) from (%s) t', p_have) into have;
  execute format('select array_agg(t::text) from (%s) t', p_want) into want;
  return tap._result(have is not distinct from want, p_desc, 'have: ' || coalesce(have::text, 'NULL') || ' / want: ' || coalesce(want::text, 'NULL'));
end;
$$;

create function tap.lives_ok(p_sql text, p_desc text default null) returns text language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    return tap._result(false, p_desc, 'died: ' || sqlstate || ' ' || sqlerrm);
  end;
  return tap._result(true, p_desc);
end;
$$;

create function tap.throws_ok(p_sql text, p_code text, p_msg text default null, p_desc text default null)
returns text language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    return tap._result(
      (p_code is null or sqlstate = p_code) and (p_msg is null or sqlerrm = p_msg),
      p_desc, 'caught: ' || sqlstate || ' ' || sqlerrm || ' / wanted: ' || coalesce(p_code, '*') || ' ' || coalesce(p_msg, '*'));
  end;
  return tap._result(false, p_desc, 'no exception thrown');
end;
$$;

grant execute on all functions in schema tap to anon, authenticated, service_role;

create function tap.isnt(p_have anyelement, p_want anyelement, p_desc text default null) returns text language sql as $$
  select tap._result(p_have is distinct from p_want, p_desc, 'have: ' || coalesce(p_have::text, 'NULL') || ' / should differ')
$$;
grant execute on function tap.isnt(anyelement, anyelement, text) to anon, authenticated, service_role;
