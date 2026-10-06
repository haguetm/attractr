-- Phase 6 (spec §7): friends and group outings.
-- Friends: added by single-use link or by pseudo, accepted on both sides, verified
-- accounts only, 10 max, list visible to its owner only. No messages, no activity
-- feed, no friends of friends.
-- Outings: proposed inside a match, each side invites its own friends; friends get a
-- card (day, place, time, the two first names) and answer, without any profile access.

insert into public.app_config (key, value, description, is_public) values
  ('friends.max', '10', 'Max accepted friends per person (spec §7).', true),
  ('friends.invite_link_days', '7', 'Validity of a single-use friend link (provisoire).', false),
  ('outings.min_participants', '3', 'Min participants of an outing, the two matched people included.', true),
  ('outings.max_participants', '8', 'Max participants of an outing, the two matched people included.', true),
  ('outings.feedback_after_hours', '3', 'Feedback is requested this long after the outing starts (provisoire).', false);

alter type public.notification_kind add value if not exists 'friend_request';
alter type public.notification_kind add value if not exists 'outing_invitation';
alter type public.notification_kind add value if not exists 'outing_cancelled';
alter type public.notification_kind add value if not exists 'outing_feedback';

-- Pseudo ------------------------------------------------------------------------------------
-- Only used to add a friend by exact pseudo; never searchable nor listed.

alter table public.profiles add column username text;
create unique index profiles_username_idx on public.profiles (lower(username));
alter table public.profiles add constraint profiles_username_format check (username ~ '^[a-z0-9_.]{3,20}$');

create function public.set_my_username(p_username text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  clean text := lower(btrim(p_username));
begin
  if clean !~ '^[a-z0-9_.]{3,20}$' then
    raise exception 'invalid_username';
  end if;
  if exists (select 1 from public.profiles where lower(username) = clean and id <> uid) then
    raise exception 'username_taken';
  end if;
  update public.profiles set username = clean where id = uid;
end;
$$;

-- Friendships -------------------------------------------------------------------------------

create table public.friendships (
  user_a uuid not null references public.profiles (id) on delete cascade,
  user_b uuid not null references public.profiles (id) on delete cascade,
  requested_by uuid not null references public.profiles (id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at timestamptz not null default now(),
  accepted_at timestamptz,
  primary key (user_a, user_b),
  check (user_a < user_b),
  check (requested_by in (user_a, user_b))
);

create index friendships_user_b_idx on public.friendships (user_b);

-- Visible only to the two people concerned (the list belongs to its owner).
alter table public.friendships enable row level security;
revoke insert, update, delete, truncate on public.friendships from authenticated;
create policy friendships_select_own on public.friendships
  for select to authenticated using ((select auth.uid()) in (user_a, user_b));

create table private.friend_invites (
  code text primary key,
  owner_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  used_at timestamptz,
  used_by uuid references public.profiles (id) on delete cascade
);

create function private.are_friends(p_a uuid, p_b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.friendships
                 where user_a = least(p_a, p_b) and user_b = greatest(p_a, p_b) and status = 'accepted');
$$;

create function private.is_blocked_pair(p_a uuid, p_b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.blocks
                 where (blocker_id = p_a and blocked_id = p_b) or (blocker_id = p_b and blocked_id = p_a));
$$;

create function private.friend_count(p_user_id uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::integer from public.friendships where p_user_id in (user_a, user_b) and status = 'accepted';
$$;

-- Common checks before two people can be friends.
create function private.check_friendable(p_me uuid, p_other uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_me = p_other then
    raise exception 'cannot_befriend_self';
  end if;
  if (select verification_status from public.profiles where id = p_me) <> 'verified' then
    raise exception 'verification_required';
  end if;
  if not exists (select 1 from public.profiles where id = p_other and verification_status = 'verified'
                 and status in ('active', 'paused')) or private.is_blocked_pair(p_me, p_other) then
    raise exception 'friend_unavailable';
  end if;
  if private.friend_count(p_me) >= private.config_int('friends.max') then
    raise exception 'friend_limit_reached';
  end if;
  if private.friend_count(p_other) >= private.config_int('friends.max') then
    raise exception 'friend_unavailable';
  end if;
end;
$$;

create function private.accept_friendship(p_a uuid, p_b uuid, p_requested_by uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.friendships (user_a, user_b, requested_by, status, accepted_at)
  values (least(p_a, p_b), greatest(p_a, p_b), p_requested_by, 'accepted', now())
  on conflict (user_a, user_b) do update set status = 'accepted', accepted_at = now();
$$;

-- By pseudo: a request the other person accepts (or declines).
create function public.request_friend_by_username(p_username text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  other uuid;
  existing public.friendships;
begin
  select id into other from public.profiles where lower(username) = lower(btrim(p_username));
  if other is null then
    raise exception 'friend_unavailable';
  end if;
  perform private.check_friendable(uid, other);
  select * into existing from public.friendships where user_a = least(uid, other) and user_b = greatest(uid, other);
  if existing.status = 'accepted' then
    raise exception 'already_friends';
  elsif existing.status = 'pending' and existing.requested_by = other then
    -- They already asked: asking back accepts.
    perform private.accept_friendship(uid, other, other);
    return;
  elsif existing.status = 'pending' then
    return;
  end if;
  insert into public.friendships (user_a, user_b, requested_by) values (least(uid, other), greatest(uid, other), uid);
  perform private.notify(other, 'friend_request', '{}');
end;
$$;

create function public.respond_friend_request(p_other_id uuid, p_accept boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  f public.friendships;
begin
  select * into f from public.friendships
  where user_a = least(uid, p_other_id) and user_b = greatest(uid, p_other_id) and status = 'pending' and requested_by = p_other_id
  for update;
  if f.user_a is null then
    raise exception 'friend_request_not_found';
  end if;
  if p_accept then
    perform private.check_friendable(uid, p_other_id);
    perform private.accept_friendship(uid, p_other_id, p_other_id);
  else
    delete from public.friendships where user_a = f.user_a and user_b = f.user_b;
  end if;
end;
$$;

-- By link: sharing a single-use link is the owner's acceptance; opening it is the other's.
create function public.create_friend_invite()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  code text := upper(encode(extensions.gen_random_bytes(6), 'hex'));
begin
  if (select verification_status from public.profiles where id = uid) <> 'verified' then
    raise exception 'verification_required';
  end if;
  insert into private.friend_invites (code, owner_id, expires_at)
  values (code, uid, now() + make_interval(days => private.config_int('friends.invite_link_days')));
  return code;
end;
$$;

-- What the link opener sees before confirming: the owner's first name only.
create function public.preview_friend_invite(p_code text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('first_name', p.first_name)
  from private.friend_invites i join public.profiles p on p.id = i.owner_id
  where i.code = upper(btrim(p_code)) and i.used_at is null and i.expires_at > now();
$$;

create function public.accept_friend_invite(p_code text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  inv private.friend_invites;
begin
  select * into inv from private.friend_invites where code = upper(btrim(p_code)) for update;
  if inv.code is null or inv.used_at is not null or inv.expires_at <= now() then
    raise exception 'invite_invalid';
  end if;
  if private.are_friends(uid, inv.owner_id) then
    raise exception 'already_friends';
  end if;
  perform private.check_friendable(uid, inv.owner_id);
  perform private.accept_friendship(uid, inv.owner_id, inv.owner_id);
  update private.friend_invites set used_at = now(), used_by = uid where code = inv.code;
end;
$$;

create function public.remove_friend(p_other_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.friendships
  where user_a = least((select auth.uid()), p_other_id) and user_b = greatest((select auth.uid()), p_other_id);
$$;

-- The owner's list: friends, requests received, requests sent. First name and pseudo only.
create function public.get_my_friends()
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
    with mine as (
      select f.*, case when f.user_a = uid then f.user_b else f.user_a end as other_id
      from public.friendships f where uid in (f.user_a, f.user_b)
    )
    select jsonb_build_object(
      'username', (select username from public.profiles where id = uid),
      'max', private.config_int('friends.max'),
      'friends', coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'first_name', p.first_name, 'username', p.username)
                                    order by p.first_name) filter (where m.status = 'accepted'), '[]'::jsonb),
      'incoming', coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'first_name', p.first_name, 'username', p.username))
                           filter (where m.status = 'pending' and m.requested_by <> uid), '[]'::jsonb),
      'outgoing', coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'first_name', p.first_name, 'username', p.username))
                           filter (where m.status = 'pending' and m.requested_by = uid), '[]'::jsonb)
    )
    from mine m join public.profiles p on p.id = m.other_id
  );
end;
$$;

-- Blocking someone also ends the friendship.
create or replace function private.block(p_blocker uuid, p_blocked uuid, p_source text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_blocker = p_blocked then
    raise exception 'cannot_block_self';
  end if;
  insert into public.blocks (blocker_id, blocked_id, source) values (p_blocker, p_blocked, p_source)
  on conflict (blocker_id, blocked_id) do nothing;
  update public.matches set status = 'unmatched', ended_at = now(), ended_by = p_blocker
   where status = 'active' and user_a = least(p_blocker, p_blocked) and user_b = greatest(p_blocker, p_blocked);
  delete from public.friendships where user_a = least(p_blocker, p_blocked) and user_b = greatest(p_blocker, p_blocked);
end;
$$;

-- Outings ----------------------------------------------------------------------------------------

create table public.outings (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches (id) on delete cascade,
  created_by uuid not null references public.profiles (id) on delete cascade,
  place text not null check (char_length(btrim(place)) between 2 and 120),
  starts_at timestamptz not null,
  status text not null default 'planned' check (status in ('planned', 'cancelled')),
  created_at timestamptz not null default now(),
  feedback_requested_at timestamptz
);

create index outings_match_idx on public.outings (match_id);

create table public.outing_invitations (
  outing_id uuid not null references public.outings (id) on delete cascade,
  friend_id uuid not null references public.profiles (id) on delete cascade,
  invited_by uuid not null references public.profiles (id) on delete cascade,
  response text not null default 'pending' check (response in ('pending', 'going', 'not_going')),
  invited_at timestamptz not null default now(),
  responded_at timestamptz,
  primary key (outing_id, friend_id)
);

create index outing_invitations_friend_idx on public.outing_invitations (friend_id);

create table private.outing_feedback (
  outing_id uuid not null references public.outings (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  rating smallint not null check (rating between 1 and 5),
  comment text check (char_length(comment) <= 500),
  created_at timestamptz not null default now(),
  primary key (outing_id, user_id)
);

-- All reads go through RPCs: invitees must never see more than their card.
alter table public.outings enable row level security;
alter table public.outing_invitations enable row level security;
revoke all on public.outings, public.outing_invitations from authenticated;

create function private.require_outing_pair_member(p_outing_id uuid, p_user_id uuid)
returns public.outings
language plpgsql
security definer
set search_path = ''
as $$
declare
  o public.outings;
begin
  select o2.* into o from public.outings o2
  join public.matches m on m.id = o2.match_id
  where o2.id = p_outing_id and p_user_id in (m.user_a, m.user_b);
  if o.id is null then
    raise exception 'outing_not_found';
  end if;
  return o;
end;
$$;

create function private.outing_participants(p_outing_id uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  -- The two matched people plus every invitation not declined.
  select 2 + count(*)::integer from public.outing_invitations
  where outing_id = p_outing_id and response <> 'not_going';
$$;

create function public.create_outing(p_match_id uuid, p_place text, p_starts_at timestamptz)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  m public.matches;
  new_id uuid;
begin
  select * into m from public.matches where id = p_match_id and uid in (user_a, user_b);
  if m.id is null or not private.match_is_open(m) then
    raise exception 'match_not_found';
  end if;
  if p_starts_at <= now() then
    raise exception 'outing_in_past';
  end if;
  if exists (select 1 from public.outings where match_id = p_match_id and status = 'planned' and starts_at > now()) then
    raise exception 'outing_already_planned';
  end if;
  insert into public.outings (match_id, created_by, place, starts_at)
  values (p_match_id, uid, btrim(p_place), p_starts_at)
  returning id into new_id;
  return new_id;
end;
$$;

-- Each matched person invites their own friends (spec §7).
create function public.invite_to_outing(p_outing_id uuid, p_friend_ids uuid[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  o public.outings := private.require_outing_pair_member(p_outing_id, uid);
  m public.matches;
  friend uuid;
begin
  select * into m from public.matches where id = o.match_id;
  if o.status <> 'planned' or o.starts_at <= now() or not private.match_is_open(m) then
    raise exception 'outing_closed';
  end if;
  foreach friend in array p_friend_ids loop
    if not private.are_friends(uid, friend) then
      raise exception 'not_a_friend';
    end if;
    if friend in (m.user_a, m.user_b)
       or private.is_blocked_pair(friend, m.user_a) or private.is_blocked_pair(friend, m.user_b) then
      raise exception 'friend_unavailable';
    end if;
    if exists (select 1 from public.outing_invitations where outing_id = o.id and friend_id = friend) then
      continue;
    end if;
    if private.outing_participants(o.id) >= private.config_int('outings.max_participants') then
      raise exception 'outing_full';
    end if;
    insert into public.outing_invitations (outing_id, friend_id, invited_by) values (o.id, friend, uid);
    perform private.notify(friend, 'outing_invitation', jsonb_build_object('outing_id', o.id));
  end loop;
end;
$$;

create function public.cancel_outing(p_outing_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  o public.outings := private.require_outing_pair_member(p_outing_id, uid);
  friend uuid;
begin
  if o.status = 'cancelled' then
    return;
  end if;
  update public.outings set status = 'cancelled' where id = o.id;
  for friend in select friend_id from public.outing_invitations where outing_id = o.id and response <> 'not_going' loop
    perform private.notify(friend, 'outing_cancelled', jsonb_build_object('outing_id', o.id));
  end loop;
end;
$$;

-- Effective status: an outing whose match ended is cancelled for everyone.
create function private.outing_status(o public.outings)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when o.status = 'cancelled' or not exists (select 1 from public.matches m where m.id = o.match_id and m.status = 'active')
      then 'cancelled'
    when o.starts_at <= now() then 'past'
    else 'planned'
  end;
$$;

-- What the matched pair sees: details, invitees' first names and answers.
create function public.get_match_outing(p_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  o public.outings;
begin
  if not exists (select 1 from public.matches where id = p_match_id and uid in (user_a, user_b)) then
    raise exception 'match_not_found';
  end if;
  select * into o from public.outings where match_id = p_match_id order by created_at desc limit 1;
  if o.id is null then
    return null;
  end if;
  return jsonb_build_object(
    'id', o.id,
    'place', o.place,
    'starts_at', o.starts_at,
    'status', private.outing_status(o),
    'created_by_me', o.created_by = uid,
    'participants', private.outing_participants(o.id),
    'min_participants', private.config_int('outings.min_participants'),
    'max_participants', private.config_int('outings.max_participants'),
    'invitations', coalesce((
      -- friend_id only for my own invitations: the other side's friends stay first names.
      select jsonb_agg(jsonb_build_object('first_name', p.first_name, 'response', i.response, 'mine', i.invited_by = uid,
                                          'friend_id', case when i.invited_by = uid then i.friend_id end)
                       order by i.invited_at)
      from public.outing_invitations i join public.profiles p on p.id = i.friend_id
      where i.outing_id = o.id), '[]'::jsonb),
    'my_feedback_given', exists (select 1 from private.outing_feedback f where f.outing_id = o.id and f.user_id = uid)
  );
end;
$$;

-- What a friend sees (spec §7): day, place, time, the two first names, nothing else.
create function public.get_my_outing_invitations()
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
    select jsonb_agg(jsonb_build_object(
      'outing_id', o.id,
      'place', o.place,
      'starts_at', o.starts_at,
      'status', private.outing_status(o),
      'matched_first_names', jsonb_build_array(pa.first_name, pb.first_name),
      'invited_by', inviter.first_name,
      'response', i.response,
      'participants', private.outing_participants(o.id),
      'my_feedback_given', exists (select 1 from private.outing_feedback f where f.outing_id = o.id and f.user_id = uid)
    ) order by o.starts_at)
    from public.outing_invitations i
    join public.outings o on o.id = i.outing_id
    join public.matches m on m.id = o.match_id
    join public.profiles pa on pa.id = m.user_a
    join public.profiles pb on pb.id = m.user_b
    join public.profiles inviter on inviter.id = i.invited_by
    where i.friend_id = uid and o.starts_at > now() - interval '7 days'
  ), '[]'::jsonb);
end;
$$;

create function public.respond_to_outing(p_outing_id uuid, p_going boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  o public.outings;
begin
  select o2.* into o from public.outings o2
  join public.outing_invitations i on i.outing_id = o2.id and i.friend_id = uid
  where o2.id = p_outing_id;
  if o.id is null then
    raise exception 'outing_not_found';
  end if;
  if private.outing_status(o) <> 'planned' then
    raise exception 'outing_closed';
  end if;
  if p_going and (select response from public.outing_invitations where outing_id = o.id and friend_id = uid) = 'not_going'
     and private.outing_participants(o.id) >= private.config_int('outings.max_participants') then
    raise exception 'outing_full';
  end if;
  update public.outing_invitations
     set response = case when p_going then 'going' else 'not_going' end, responded_at = now()
   where outing_id = o.id and friend_id = uid;
end;
$$;

-- Private feedback after the outing (spec §7): the two matched people and friends who went.
create function public.give_outing_feedback(p_outing_id uuid, p_rating integer, p_comment text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  o public.outings;
begin
  select o2.* into o from public.outings o2
  join public.matches m on m.id = o2.match_id
  where o2.id = p_outing_id
    and (uid in (m.user_a, m.user_b)
         or exists (select 1 from public.outing_invitations i where i.outing_id = o2.id and i.friend_id = uid and i.response = 'going'));
  if o.id is null then
    raise exception 'outing_not_found';
  end if;
  if o.status = 'cancelled' or o.starts_at > now() then
    raise exception 'outing_not_over';
  end if;
  if p_rating is null or p_rating not between 1 and 5 then
    raise exception 'invalid_rating';
  end if;
  insert into private.outing_feedback (outing_id, user_id, rating, comment)
  values (o.id, uid, p_rating, nullif(btrim(p_comment), ''))
  on conflict (outing_id, user_id) do update set rating = excluded.rating, comment = excluded.comment, created_at = now();
end;
$$;

-- Scheduled: ask for feedback a few hours after the outing started.
create function private.queue_outing_feedback()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  o record;
  person uuid;
  n integer := 0;
begin
  for o in
    update public.outings set feedback_requested_at = now()
    where status = 'planned' and feedback_requested_at is null
      and starts_at < now() - make_interval(hours => private.config_int('outings.feedback_after_hours'))
      and starts_at > now() - interval '3 days'
    returning id, match_id
  loop
    for person in
      select unnest(array[m.user_a, m.user_b]) from public.matches m where m.id = o.match_id and m.status = 'active'
      union
      select friend_id from public.outing_invitations where outing_id = o.id and response = 'going'
    loop
      perform private.notify(person, 'outing_feedback', jsonb_build_object('outing_id', o.id));
      n := n + 1;
    end loop;
  end loop;
  return n;
end;
$$;

create or replace function private.run_scheduled_jobs()
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'expired', private.expire_matches(),
    'reminders', private.queue_first_message_reminders(),
    'your_turn', private.queue_your_turn(),
    'outing_feedback', private.queue_outing_feedback()
  );
$$;

do $$
declare
  f text;
begin
  foreach f in array array[
    'public.set_my_username(text)',
    'public.request_friend_by_username(text)',
    'public.respond_friend_request(uuid, boolean)',
    'public.create_friend_invite()',
    'public.preview_friend_invite(text)',
    'public.accept_friend_invite(text)',
    'public.remove_friend(uuid)',
    'public.get_my_friends()',
    'public.create_outing(uuid, text, timestamptz)',
    'public.invite_to_outing(uuid, uuid[])',
    'public.cancel_outing(uuid)',
    'public.get_match_outing(uuid)',
    'public.get_my_outing_invitations()',
    'public.respond_to_outing(uuid, boolean)',
    'public.give_outing_feedback(uuid, integer, text)'
  ]
  loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end;
$$;
