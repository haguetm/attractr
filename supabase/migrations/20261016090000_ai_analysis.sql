-- AI profile analysis (spec §11, §10).
-- The Edge Function `analyze-profile` is the only caller of the AI provider. It claims a
-- weekly slot here, sends the approved photos and texts, checks the answer with its
-- output guard, then records the result. Photos are never stored by this feature: the
-- function keeps them in memory for the call only.
-- One full analysis is always computed and cached; free users see one tip of it,
-- Premium users the whole result (no second provider call after upgrading).

insert into public.app_config (key, value, description, is_public) values
  ('ai.analysis_interval_days', '7', 'Minimum days between two AI analyses (provisoire).', true),
  ('ai.max_photos', '6', 'Photos sent to the AI provider per analysis (provisoire).', false),
  ('ai.model', '"claude-opus-5-5"', 'AI provider model id; can be changed without redeploying.', false),
  ('ai.effort', '"medium"', 'AI provider effort level: low | medium | high.', false),
  ('providers.mock_ai_outcome', '"ok"', 'Development only: ok | forbidden | error.', false);

create type public.ai_analysis_status as enum ('running', 'completed');

create table private.ai_analyses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  status public.ai_analysis_status not null default 'running',
  model text,
  -- {photos:[{photo_id,strength,improvement}], photo_order:[photo_id], bio:{cliches,rewrite,drink_fit}, top_tip}
  result jsonb,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  check ((status = 'completed') = (result is not null and completed_at is not null))
);

create index ai_analyses_user_idx on private.ai_analyses (user_id, started_at desc);

-- A run that never finished (crash, timeout) stops holding the slot after 15 minutes.
create function private.ai_slot_holder(p_user_id uuid)
returns private.ai_analyses
language sql
stable
security definer
set search_path = ''
as $$
  select a.* from private.ai_analyses a
  where a.user_id = p_user_id
    and (
      (a.status = 'completed' and a.completed_at > now() - make_interval(days => private.config_int('ai.analysis_interval_days')))
      or (a.status = 'running' and a.started_at > now() - interval '15 minutes')
    )
  order by a.started_at desc
  limit 1;
$$;

-- Service: checks consent and the weekly limit, claims a slot and returns what the
-- provider may see. Only approved photos; no name, age, gender or sensitive field.
create function public.service_claim_ai_analysis(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  holder private.ai_analyses;
  new_id uuid;
  photos jsonb;
begin
  perform 1 from public.profiles where id = p_user_id and status = 'active' for update;
  if not found then
    raise exception 'profile_not_active';
  end if;
  if not private.has_consent(p_user_id, 'ai_photo_analysis') then
    raise exception 'ai_consent_required';
  end if;
  holder := private.ai_slot_holder(p_user_id);
  if holder.id is not null then
    raise exception 'ai_analysis_rate_limited';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'storage_path', p.storage_path) order by p.position), '[]')
    into photos
  from (
    select id, storage_path, position from public.photos
    where user_id = p_user_id and moderation_status = 'approved'
    order by position
    limit private.config_int('ai.max_photos')
  ) p;
  if jsonb_array_length(photos) = 0 then
    raise exception 'ai_analysis_no_photo';
  end if;

  insert into private.ai_analyses (user_id) values (p_user_id) returning id into new_id;

  return jsonb_build_object(
    'analysis_id', new_id,
    'photos', photos,
    'bio', (select bio from public.profiles where id = p_user_id),
    'prompts', (select coalesce(jsonb_agg(jsonb_build_object('question', question_code, 'answer', answer) order by position), '[]')
                from public.profile_prompts where user_id = p_user_id),
    'drinks', (select coalesce(jsonb_agg(drink order by d.sort_order), '[]')
               from public.profile_drinks pd join public.drinks d on d.code = pd.drink where pd.user_id = p_user_id)
  );
end;
$$;

-- Service: stores a result that passed the output guard. Photo ids must be the
-- analysed user's. A consent withdrawn during the call discards the result and
-- returns false (no raise: it would roll the deletion back).
create function public.service_record_ai_analysis(p_analysis_id uuid, p_model text, p_result jsonb)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  a private.ai_analyses;
begin
  select * into a from private.ai_analyses where id = p_analysis_id and status = 'running' for update;
  if not found then
    raise exception 'ai_analysis_not_found';
  end if;
  if not private.has_consent(a.user_id, 'ai_photo_analysis') then
    delete from private.ai_analyses where id = a.id;
    return false;
  end if;
  if jsonb_typeof(p_result -> 'photos') <> 'array' or jsonb_typeof(p_result -> 'photo_order') <> 'array'
     or jsonb_typeof(p_result -> 'bio') <> 'object' or jsonb_typeof(p_result -> 'top_tip') <> 'string' then
    raise exception 'ai_result_invalid';
  end if;
  if exists (
    select 1 from (
      select x ->> 'photo_id' as pid from jsonb_array_elements(p_result -> 'photos') x
      union all
      select x #>> '{}' from jsonb_array_elements(p_result -> 'photo_order') x
    ) ids
    where not exists (select 1 from public.photos p where p.id::text = ids.pid and p.user_id = a.user_id)
  ) then
    raise exception 'ai_result_invalid';
  end if;
  update private.ai_analyses
     set status = 'completed', model = p_model, result = p_result, completed_at = now()
   where id = a.id;
  return true;
end;
$$;

-- Service: the provider failed or the guard rejected the answer; the slot is freed.
create function public.service_release_ai_analysis(p_analysis_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from private.ai_analyses where id = p_analysis_id and status = 'running';
$$;

revoke execute on function public.service_claim_ai_analysis(uuid) from public, anon, authenticated;
revoke execute on function public.service_record_ai_analysis(uuid, text, jsonb) from public, anon, authenticated;
revoke execute on function public.service_release_ai_analysis(uuid) from public, anon, authenticated;
grant execute on function public.service_claim_ai_analysis(uuid) to service_role;
grant execute on function public.service_record_ai_analysis(uuid, text, jsonb) to service_role;
grant execute on function public.service_release_ai_analysis(uuid) to service_role;

-- The caller's latest analysis. Free: the top tip only, plus what Premium would unlock.
-- Photos removed since the analysis are left out; next_available_at drives the button.
create function public.get_my_ai_analysis()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  a private.ai_analyses;
  holder private.ai_analyses := private.ai_slot_holder(uid);
  premium boolean := private.is_premium(uid);
  photos jsonb;
  photo_order jsonb;
begin
  select * into a from private.ai_analyses
   where user_id = uid and status = 'completed' order by completed_at desc limit 1;

  if a.id is not null then
    select coalesce(jsonb_agg(x order by o), '[]') into photos
      from jsonb_array_elements(a.result -> 'photos') with ordinality as t (x, o)
     where exists (select 1 from public.photos p where p.id::text = x ->> 'photo_id' and p.user_id = uid);
    select coalesce(jsonb_agg(x order by o), '[]') into photo_order
      from jsonb_array_elements(a.result -> 'photo_order') with ordinality as t (x, o)
     where exists (select 1 from public.photos p where p.id::text = x #>> '{}' and p.user_id = uid);
  end if;

  return jsonb_build_object(
    'consent', private.has_consent(uid, 'ai_photo_analysis'),
    'premium', premium,
    'running', coalesce(holder.status = 'running', false),
    'next_available_at', case
      when holder.status = 'completed' then holder.completed_at + make_interval(days => private.config_int('ai.analysis_interval_days'))
    end,
    'analysis', case
      when a.id is null then null
      when premium then jsonb_build_object(
        'completed_at', a.completed_at,
        'top_tip', a.result -> 'top_tip',
        'photos', photos,
        'photo_order', photo_order,
        'bio', a.result -> 'bio')
      else jsonb_build_object(
        'completed_at', a.completed_at,
        'top_tip', a.result -> 'top_tip',
        'locked', jsonb_build_object(
          'photos', jsonb_array_length(photos),
          'has_bio_rewrite', coalesce(a.result #>> '{bio,rewrite}', '') <> ''))
    end
  );
end;
$$;

-- Accepting the suggested order goes through reorder_my_photos; accepting or editing
-- the suggested bio goes through the usual profile update (the user always validates).

revoke execute on function public.get_my_ai_analysis() from public, anon;
grant execute on function public.get_my_ai_analysis() to authenticated;

-- Withdrawing the consent deletes every analysis at once (spec §11, §12).
create or replace function public.withdraw_consent(p_type public.consent_type)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
begin
  if p_type in ('terms', 'privacy') then
    raise exception 'consent_requires_account_deletion';
  end if;
  update public.consents set withdrawn_at = now()
    where user_id = uid and type = p_type and withdrawn_at is null;
  if p_type = 'sensitive_data' then
    delete from private.profile_sensitive where user_id = uid;
  elsif p_type = 'ai_photo_analysis' then
    delete from private.ai_analyses where user_id = uid;
  end if;
end;
$$;
