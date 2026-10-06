-- Phase 4 (spec §5): targeted likes with a rolling quota, matches with a 24 h window
-- for the first message, match chat, and the notification outbox.

insert into public.app_config (key, value, description, is_public) values
  ('chat.message_max_length', '2000', 'Max characters per chat message.', true),
  ('chat.your_turn_after_hours', '24', '"À ton tour" reminder after this many hours without a reply (provisoire).', false),
  ('chat.first_message_reminder_hours', '3', 'Reminder when this many hours remain to send the first message (provisoire).', false);

-- Premium entitlements -----------------------------------------------------------
-- Filled by the RevenueCat webhook and referral rewards in phase 7. Needed now
-- because Premium users have unlimited likes.

create table private.entitlements (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  entitlement text not null check (entitlement in ('premium')),
  source text not null check (source in ('revenuecat', 'referral', 'promo', 'test')),
  starts_at timestamptz not null default now(),
  expires_at timestamptz
);

create index entitlements_user_idx on private.entitlements (user_id);

create function private.is_premium(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from private.entitlements e
    where e.user_id = p_user_id and e.entitlement = 'premium'
      and e.starts_at <= now() and (e.expires_at is null or e.expires_at > now())
  );
$$;

-- Likes ----------------------------------------------------------------------------
-- A like targets one photo or one written answer (spec §5). It is stored on the
-- swipe row; quota_counted is false for likes answering someone who liked first.

create type public.like_target as enum ('photo', 'prompt');

alter table public.swipes
  add column target_kind public.like_target,
  add column target_ref text,
  add column quota_counted boolean not null default false,
  add constraint swipes_like_has_target check ((action = 'like') = (target_kind is not null and target_ref is not null));

create index swipes_actor_likes_idx on public.swipes (actor_id, created_at desc) where action = 'like';

-- Activity badge (Q16): a reply in the chat, not just opening the app.
alter table public.profiles add column last_reply_at timestamptz;

-- Matches and conversations ----------------------------------------------------------

create type public.match_status as enum ('active', 'expired', 'unmatched');

create table public.matches (
  id uuid primary key default gen_random_uuid(),
  user_a uuid not null references public.profiles (id) on delete cascade,
  user_b uuid not null references public.profiles (id) on delete cascade,
  matched_drinks public.drink[] not null default '{}',
  created_at timestamptz not null default now(),
  first_message_deadline timestamptz not null,
  extensions_used smallint not null default 0,
  first_message_at timestamptz,
  reminder_sent_at timestamptz,
  status public.match_status not null default 'active',
  ended_at timestamptz,
  ended_by uuid,  -- no FK: kept meaningful after the account is deleted
  check (user_a < user_b),
  unique (user_a, user_b)
);

create index matches_user_b_idx on public.matches (user_b);

alter table public.matches enable row level security;
revoke insert, update, delete, truncate on public.matches from authenticated;
create policy matches_select_own on public.matches
  for select to authenticated using ((select auth.uid()) in (user_a, user_b));

-- Open = can chat: active, and the first message was sent or is still within the window.
create function private.match_is_open(m public.matches)
returns boolean
language sql
stable
set search_path = ''
as $$
  select m.status = 'active' and (m.first_message_at is not null or now() <= m.first_message_deadline);
$$;

create type public.conversation_kind as enum ('match', 'group');

create table public.conversations (
  id uuid primary key default gen_random_uuid(),
  kind public.conversation_kind not null,
  match_id uuid unique references public.matches (id) on delete cascade,
  created_at timestamptz not null default now(),
  last_message_at timestamptz,
  check ((kind = 'match') = (match_id is not null))
);

create table public.conversation_members (
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  joined_at timestamptz not null default now(),
  last_read_at timestamptz,
  your_turn_notified_at timestamptz,
  primary key (conversation_id, user_id)
);

create index conversation_members_user_idx on public.conversation_members (user_id);

create table public.messages (
  id bigint generated always as identity primary key,
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  sender_id uuid not null references public.profiles (id) on delete cascade,
  body text not null check (char_length(body) between 1 and 4000),
  created_at timestamptz not null default now()
);

create index messages_conversation_idx on public.messages (conversation_id, created_at desc);

-- In public so RLS policies (evaluated as the caller) can use it; answers only
-- about the caller's own membership.
create function public.is_conversation_member(p_conversation_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.conversation_members
    where conversation_id = p_conversation_id and user_id = (select auth.uid())
  );
$$;

revoke execute on function public.is_conversation_member(uuid) from public, anon;
grant execute on function public.is_conversation_member(uuid) to authenticated;

-- Chat only exists inside a match or a validated group (spec §5): reads go through
-- membership; writes only through RPCs.
alter table public.conversations enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages enable row level security;
revoke insert, update, delete, truncate on public.conversations, public.conversation_members, public.messages from authenticated;
create policy conversations_select_member on public.conversations
  for select to authenticated using (public.is_conversation_member(id));
create policy conversation_members_select_member on public.conversation_members
  for select to authenticated using (public.is_conversation_member(conversation_id));
create policy messages_select_member on public.messages
  for select to authenticated using (public.is_conversation_member(conversation_id));

-- Realtime for the chat (the publication only exists on Supabase).
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.messages, public.matches;
  end if;
end;
$$;

-- Photos are also readable between active matches.
create or replace function public.can_view_photos_of(p_owner text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_owner = (select auth.uid())::text
      or exists (
        select 1 from private.feed_impressions i
        where i.viewer_id = (select auth.uid())
          and i.target_id::text = p_owner
          and i.served_at > now() - interval '24 hours'
      )
      or exists (
        select 1 from public.matches m
        where m.status = 'active'
          and ((m.user_a = (select auth.uid()) and m.user_b::text = p_owner)
            or (m.user_b = (select auth.uid()) and m.user_a::text = p_owner))
      );
$$;

-- Notifications ------------------------------------------------------------------------
-- Rows are turned into Expo pushes by the send-push Edge Function. Texts are generic and
-- data only carries ids: no names, no drinks, nothing sensitive (spec §12).

create table public.push_tokens (
  token text primary key check (char_length(token) between 10 and 300),
  user_id uuid not null references public.profiles (id) on delete cascade,
  platform text not null check (platform in ('ios', 'android', 'web')),
  updated_at timestamptz not null default now()
);

create index push_tokens_user_idx on public.push_tokens (user_id);

alter table public.push_tokens enable row level security;
revoke insert, update, delete, truncate on public.push_tokens from authenticated;
create policy push_tokens_select_own on public.push_tokens
  for select to authenticated using (user_id = (select auth.uid()));

create type public.notification_kind as enum ('new_match', 'new_message', 'your_turn', 'first_message_reminder');

create table private.notification_outbox (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  kind public.notification_kind not null,
  data jsonb not null default '{}',
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  attempts smallint not null default 0,
  last_error text
);

create index notification_outbox_pending_idx on private.notification_outbox (created_at) where sent_at is null;

create function private.notify(p_user_id uuid, p_kind public.notification_kind, p_data jsonb default '{}')
returns void
language sql
security definer
set search_path = ''
as $$
  insert into private.notification_outbox (user_id, kind, data) values (p_user_id, p_kind, p_data);
$$;

create function public.register_push_token(p_token text, p_platform text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
begin
  insert into public.push_tokens (token, user_id, platform, updated_at)
  values (p_token, uid, p_platform, now())
  on conflict (token) do update set user_id = excluded.user_id, platform = excluded.platform, updated_at = now();
end;
$$;

create function public.unregister_push_token(p_token text)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.push_tokens where token = p_token and user_id = (select auth.uid());
$$;

-- Server-side helpers for the send-push Edge Function (service role only).
create function public.service_pending_notifications(p_limit integer default 500)
returns table (id bigint, user_id uuid, kind public.notification_kind, data jsonb, tokens text[])
language sql
security definer
set search_path = ''
as $$
  select o.id, o.user_id, o.kind, o.data,
         coalesce((select array_agg(t.token) from public.push_tokens t where t.user_id = o.user_id), '{}')
  from private.notification_outbox o
  where o.sent_at is null and o.attempts < 5
  order by o.created_at
  limit p_limit;
$$;

create function public.service_mark_notifications(p_sent bigint[], p_failed bigint[], p_error text default null, p_dead_tokens text[] default '{}')
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update private.notification_outbox set sent_at = now(), attempts = attempts + 1 where id = any (p_sent);
  update private.notification_outbox set attempts = attempts + 1, last_error = left(p_error, 200) where id = any (p_failed);
  delete from public.push_tokens where token = any (p_dead_tokens);
end;
$$;

-- Quota -------------------------------------------------------------------------------

create function private.like_quota(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  quota integer := private.config_int('likes.free_quota');
  window_hours integer := private.config_int('likes.quota_window_hours');
  used integer;
  oldest timestamptz;
begin
  if private.is_premium(p_user_id) then
    return jsonb_build_object('unlimited', true);
  end if;
  select count(*), min(created_at) into used, oldest
  from public.swipes
  where actor_id = p_user_id and action = 'like' and quota_counted
    and created_at > now() - make_interval(hours => window_hours);
  return jsonb_build_object(
    'unlimited', false,
    'limit', quota,
    'used', used,
    'remaining', greatest(quota - used, 0),
    -- When the next like becomes available again (rolling window).
    'next_reset_at', case when used >= quota then oldest + make_interval(hours => window_hours) end
  );
end;
$$;

create function public.get_like_quota()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select private.like_quota(private.require_user());
$$;

-- Like ---------------------------------------------------------------------------------
-- Allowed on profiles the feed served, or on someone who already liked you. A mutual
-- like creates the match, its conversation and a 24 h window for the first message.

create function public.like_profile(p_target_id uuid, p_target_kind public.like_target, p_target_ref text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  actor public.profiles;
  target public.profiles;
  is_answer boolean;
  quota jsonb;
  new_match public.matches;
  v_conversation_id uuid;
begin
  if p_target_id = uid then
    raise exception 'cannot_swipe_self';
  end if;
  select * into actor from public.profiles where id = uid;
  if actor.status <> 'active' then
    raise exception 'profile_not_active';
  end if;
  select * into target from public.profiles where id = p_target_id;
  if target.id is null or target.status <> 'active' then
    raise exception 'profile_unavailable';
  end if;
  if exists (select 1 from public.blocks b
             where (b.blocker_id = uid and b.blocked_id = p_target_id)
                or (b.blocker_id = p_target_id and b.blocked_id = uid)) then
    raise exception 'profile_unavailable';
  end if;

  is_answer := exists (select 1 from public.swipes s
                       where s.actor_id = p_target_id and s.target_id = uid and s.action = 'like');
  if not is_answer and not exists (
    select 1 from private.feed_impressions i where i.viewer_id = uid and i.target_id = p_target_id
  ) then
    raise exception 'profile_unavailable';
  end if;

  if p_target_kind = 'photo' then
    if not exists (select 1 from public.photos ph
                   where ph.user_id = p_target_id and ph.id::text = p_target_ref and ph.moderation_status <> 'rejected') then
      raise exception 'invalid_like_target';
    end if;
  elsif not exists (select 1 from public.profile_prompts q
                    where q.user_id = p_target_id and q.question_code = p_target_ref) then
    raise exception 'invalid_like_target';
  end if;

  if exists (select 1 from public.swipes s where s.actor_id = uid and s.target_id = p_target_id and s.action = 'like') then
    raise exception 'already_liked';
  end if;

  -- Answering a like never consumes the quota (spec §5: "réponses hors quota").
  if not is_answer then
    quota := private.like_quota(uid);
    if not (quota ->> 'unlimited')::boolean and (quota ->> 'remaining')::integer <= 0 then
      raise exception 'like_quota_reached';
    end if;
  end if;

  insert into public.swipes (actor_id, target_id, action, target_kind, target_ref, quota_counted)
  values (uid, p_target_id, 'like', p_target_kind, p_target_ref, not is_answer)
  on conflict (actor_id, target_id) do update
    set action = 'like', target_kind = excluded.target_kind, target_ref = excluded.target_ref,
        quota_counted = excluded.quota_counted, created_at = now();

  if is_answer then
    insert into public.matches (user_a, user_b, matched_drinks, first_message_deadline)
    values (
      least(uid, p_target_id), greatest(uid, p_target_id),
      private.match_drinks(
        actor.gender, (select array_agg(drink order by drink) from public.profile_drinks where user_id = uid), private.read_sensitive(uid),
        target.gender, (select array_agg(drink order by drink) from public.profile_drinks where user_id = p_target_id), private.read_sensitive(p_target_id)),
      now() + make_interval(hours => private.config_int('match.first_message_window_hours'))
    )
    on conflict (user_a, user_b) do nothing
    returning * into new_match;

    if new_match.id is not null then
      insert into public.conversations (kind, match_id) values ('match', new_match.id) returning id into v_conversation_id;
      insert into public.conversation_members (conversation_id, user_id) values (v_conversation_id, uid), (v_conversation_id, p_target_id);
      perform private.notify(uid, 'new_match', jsonb_build_object('match_id', new_match.id));
      perform private.notify(p_target_id, 'new_match', jsonb_build_object('match_id', new_match.id));
    end if;
  end if;

  return jsonb_build_object(
    'matched', new_match.id is not null,
    'match_id', new_match.id,
    'conversation_id', v_conversation_id,
    'quota', private.like_quota(uid)
  );
end;
$$;

-- Number of people waiting for an answer. Free users only see that some exist; the
-- list of who liked you is Premium (phase 7).
create function public.get_likes_received_count()
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::integer
  from public.swipes s
  join public.profiles p on p.id = s.actor_id and p.status = 'active'
  where s.target_id = (select auth.uid()) and s.action = 'like'
    and not exists (select 1 from public.swipes mine where mine.actor_id = s.target_id and mine.target_id = s.actor_id)
    and not exists (select 1 from public.blocks b
                    where (b.blocker_id = s.target_id and b.blocked_id = s.actor_id)
                       or (b.blocker_id = s.actor_id and b.blocked_id = s.target_id));
$$;

-- Match lifecycle ------------------------------------------------------------------------

create function private.require_match_member(p_match_id uuid, p_user_id uuid)
returns public.matches
language plpgsql
security definer
set search_path = ''
as $$
declare
  m public.matches;
begin
  select * into m from public.matches where id = p_match_id and p_user_id in (user_a, user_b) for update;
  if m.id is null then
    raise exception 'match_not_found';
  end if;
  return m;
end;
$$;

-- One more window for the first message (Q14), before the current one ends.
create function public.extend_match(p_match_id uuid)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  m public.matches := private.require_match_member(p_match_id, uid);
begin
  if m.status <> 'active' or m.first_message_at is not null or now() > m.first_message_deadline
     or m.extensions_used >= private.config_int('match.max_extensions') then
    raise exception 'match_extension_unavailable';
  end if;
  update public.matches
     set first_message_deadline = first_message_deadline + make_interval(hours => private.config_int('match.extension_hours')),
         extensions_used = extensions_used + 1,
         reminder_sent_at = null
   where id = p_match_id
  returning first_message_deadline into m.first_message_deadline;
  return m.first_message_deadline;
end;
$$;

create function public.unmatch(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  m public.matches := private.require_match_member(p_match_id, uid);
begin
  if m.status = 'active' then
    update public.matches set status = 'unmatched', ended_at = now(), ended_by = uid where id = p_match_id;
  end if;
end;
$$;

-- Chat -------------------------------------------------------------------------------------

create function public.send_message(p_conversation_id uuid, p_body text)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  c public.conversations;
  m public.matches;
  body text := btrim(p_body);
  new_id bigint;
  recipient uuid;
begin
  select * into c from public.conversations where id = p_conversation_id;
  if c.id is null or not exists (
    select 1 from public.conversation_members where conversation_id = c.id and user_id = uid
  ) then
    raise exception 'conversation_not_found';
  end if;
  if body is null or char_length(body) = 0 or char_length(body) > private.config_int('chat.message_max_length') then
    raise exception 'message_length';
  end if;

  if c.kind = 'match' then
    select * into m from public.matches where id = c.match_id for update;
    -- The status itself is updated by private.expire_matches (scheduled job).
    if m.status = 'active' and m.first_message_at is null and now() > m.first_message_deadline then
      raise exception 'match_expired';
    end if;
    if not private.match_is_open(m) then
      raise exception 'match_closed';
    end if;
    if m.first_message_at is null then
      update public.matches set first_message_at = now() where id = m.id;
    end if;
  end if;

  insert into public.messages (conversation_id, sender_id, body) values (c.id, uid, body) returning id into new_id;
  update public.conversations set last_message_at = now() where id = c.id;
  update public.conversation_members set last_read_at = now() where conversation_id = c.id and user_id = uid;
  update public.profiles set last_reply_at = now(), last_active_at = now() where id = uid;

  for recipient in
    select user_id from public.conversation_members where conversation_id = c.id and user_id <> uid
  loop
    perform private.notify(recipient, 'new_message', jsonb_build_object('conversation_id', c.id));
  end loop;
  return new_id;
end;
$$;

create function public.mark_conversation_read(p_conversation_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.conversation_members set last_read_at = now()
  where conversation_id = p_conversation_id and user_id = (select auth.uid());
$$;

-- The caller's open matches, most recent activity first.
create function public.get_my_matches()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
begin
  return coalesce((
    select jsonb_agg(item order by sort_at desc)
    from (
      select coalesce(c.last_message_at, m.created_at) as sort_at,
        jsonb_build_object(
          'match_id', m.id,
          'conversation_id', c.id,
          'created_at', m.created_at,
          'matched_drinks', to_jsonb(m.matched_drinks),
          'first_message_deadline', case when m.first_message_at is null then m.first_message_deadline end,
          'extensions_left', greatest(private.config_int('match.max_extensions') - m.extensions_used, 0),
          'other', jsonb_build_object(
            'id', o.id,
            'first_name', o.first_name,
            'age', private.age_of(o.birth_date),
            'verified', o.verification_status = 'verified',
            'drinks', coalesce((select jsonb_agg(d.drink order by d.drink) from public.profile_drinks d where d.user_id = o.id), '[]'::jsonb),
            'photo_path', (select ph.storage_path from public.photos ph
                           where ph.user_id = o.id and ph.moderation_status <> 'rejected' order by ph.position limit 1)
          ),
          'last_message', (select jsonb_build_object('body', left(msg.body, 120), 'mine', msg.sender_id = uid, 'created_at', msg.created_at)
                           from public.messages msg where msg.conversation_id = c.id order by msg.created_at desc limit 1),
          'unread_count', (select count(*) from public.messages msg
                           where msg.conversation_id = c.id and msg.sender_id <> uid
                             and msg.created_at > coalesce(me.last_read_at, '-infinity'::timestamptz)),
          'my_turn', coalesce((select msg.sender_id <> uid from public.messages msg
                               where msg.conversation_id = c.id order by msg.created_at desc limit 1), false)
        ) as item
      from public.matches m
      join public.conversations c on c.match_id = m.id
      join public.conversation_members me on me.conversation_id = c.id and me.user_id = uid
      join public.profiles o on o.id = case when m.user_a = uid then m.user_b else m.user_a end
      where uid in (m.user_a, m.user_b) and private.match_is_open(m)
    ) rows
  ), '[]'::jsonb);
end;
$$;

-- Full profile of a match (same public fields as a feed card).
create function public.get_match_profile(p_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  m public.matches;
  other uuid;
begin
  select * into m from public.matches where id = p_match_id and uid in (user_a, user_b);
  if m.id is null or m.status <> 'active' then
    raise exception 'match_not_found';
  end if;
  other := case when m.user_a = uid then m.user_b else m.user_a end;
  return private.profile_card(
    other,
    (select extensions.st_distance(a.location, b.location) from public.profiles a, public.profiles b where a.id = uid and b.id = other),
    m.matched_drinks
  );
end;
$$;

-- Activity badge now means "replied in the chat recently" (Q16).
create or replace function private.profile_card(p_candidate_id uuid, p_distance_m double precision, p_matched public.drink[])
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p.id,
    'first_name', p.first_name,
    'age', private.age_of(p.birth_date),
    'gender', p.gender,
    'gender_detail', p.gender_detail,
    'bio', p.bio,
    'verified', p.verification_status = 'verified',
    'recently_active', coalesce(p.last_reply_at > now() - make_interval(hours => private.config_int('activity.badge_window_hours')), false),
    'distance', private.distance_bucket(coalesce(p_distance_m, 0)),
    'drinks', coalesce((select jsonb_agg(d.drink order by d.drink) from public.profile_drinks d where d.user_id = p.id), '[]'::jsonb),
    'matched_drinks', to_jsonb(p_matched),
    'orientation', case
        when (s ->> 'orientation_visible')::boolean and (private.country_switches(p.country_code)).orientation_enabled
        then s ->> 'orientation' end,
    'prompts', coalesce((select jsonb_agg(jsonb_build_object('question_code', q.question_code, 'answer', q.answer) order by q.position)
                         from public.profile_prompts q where q.user_id = p.id), '[]'::jsonb),
    -- Until photo moderation exists (phase 5), only rejected photos are hidden.
    'photos', coalesce((select jsonb_agg(jsonb_build_object('id', ph.id, 'storage_path', ph.storage_path) order by ph.position)
                        from public.photos ph where ph.user_id = p.id and ph.moderation_status <> 'rejected'), '[]'::jsonb)
  )
  from public.profiles p
  cross join lateral (select private.read_sensitive(p.id) as s) sens
  where p.id = p_candidate_id;
$$;

-- Scheduled jobs (every 5 minutes through pg_cron on Supabase) -------------------------------

create function private.expire_matches()
returns integer
language sql
security definer
set search_path = ''
as $$
  with expired as (
    update public.matches set status = 'expired', ended_at = now()
    where status = 'active' and first_message_at is null and first_message_deadline < now()
    returning 1
  )
  select count(*)::integer from expired;
$$;

create function private.queue_first_message_reminders()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  m record;
  n integer := 0;
begin
  for m in
    update public.matches set reminder_sent_at = now()
    where status = 'active' and first_message_at is null and reminder_sent_at is null
      and first_message_deadline > now()
      and first_message_deadline <= now() + make_interval(hours => private.config_int('chat.first_message_reminder_hours'))
    returning id, user_a, user_b
  loop
    perform private.notify(m.user_a, 'first_message_reminder', jsonb_build_object('match_id', m.id));
    perform private.notify(m.user_b, 'first_message_reminder', jsonb_build_object('match_id', m.id));
    n := n + 2;
  end loop;
  return n;
end;
$$;

-- "À ton tour" (spec §5): the other person wrote last and is waiting for an answer.
create function private.queue_your_turn()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
  n integer := 0;
begin
  for r in
    select cm.conversation_id, cm.user_id, last.created_at
    from public.conversation_members cm
    join public.conversations c on c.id = cm.conversation_id
    cross join lateral (
      select msg.sender_id, msg.created_at from public.messages msg
      where msg.conversation_id = cm.conversation_id order by msg.created_at desc limit 1
    ) last
    left join public.matches m on m.id = c.match_id
    where last.sender_id <> cm.user_id
      and last.created_at < now() - make_interval(hours => private.config_int('chat.your_turn_after_hours'))
      and (cm.your_turn_notified_at is null or cm.your_turn_notified_at < last.created_at)
      and (m.id is null or m.status = 'active')
  loop
    perform private.notify(r.user_id, 'your_turn', jsonb_build_object('conversation_id', r.conversation_id));
    update public.conversation_members set your_turn_notified_at = now()
     where conversation_id = r.conversation_id and user_id = r.user_id;
    n := n + 1;
  end loop;
  return n;
end;
$$;

create function private.run_scheduled_jobs()
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'expired', private.expire_matches(),
    'reminders', private.queue_first_message_reminders(),
    'your_turn', private.queue_your_turn()
  );
$$;

-- pg_cron is only available on the Supabase stack.
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('attractr-scheduled-jobs', '*/5 * * * *', 'select private.run_scheduled_jobs()');
  end if;
end;
$$;

do $$
declare
  f text;
begin
  foreach f in array array[
    'public.get_like_quota()',
    'public.like_profile(uuid, public.like_target, text)',
    'public.get_likes_received_count()',
    'public.extend_match(uuid)',
    'public.unmatch(uuid)',
    'public.send_message(uuid, text)',
    'public.mark_conversation_read(uuid)',
    'public.get_my_matches()',
    'public.get_match_profile(uuid)',
    'public.register_push_token(text, text)',
    'public.unregister_push_token(text)'
  ]
  loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end;
$$;

revoke execute on function public.service_pending_notifications(integer) from public, anon, authenticated;
revoke execute on function public.service_mark_notifications(bigint[], bigint[], text, text[]) from public, anon, authenticated;
grant execute on function public.service_pending_notifications(integer) to service_role;
grant execute on function public.service_mark_notifications(bigint[], bigint[], text, text[]) to service_role;
