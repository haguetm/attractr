-- Phase 8 (spec §8): group chats (Premium).
--   romantic groups (6 max): every member has an active match with every other member,
--     checked at each addition; joining is by invitation, accepted by the invitee.
--   friends groups, Bière (8 max): after a Bière match, a member invites the other person;
--     the group approves (strict majority, or the admin, chosen at creation, Q18) and the
--     invitee accepts. Before joining, the invitee sees the group size and first names only
--     (plus the inviter's profile through their match); members see the newcomer's first
--     name and main photo only. This exception never applies to romantic groups.
-- Common: invitation only, no public groups, no group search, no messages between groups;
-- leave, block, report; a block between two members makes the blocker leave (Q17).
-- Only the creator needs Premium (groups.creator_only_premium, provisoire).

insert into public.app_config (key, value, description, is_public) values
  ('groups.romantic_max_members', '6', 'Max members of a romantic / polyamory group (spec §8).', true),
  ('groups.friends_max_members', '8', 'Max members of a friends group (spec §8).', true),
  ('groups.invitation_days', '7', 'Validity of a group invitation for the invitee (provisoire).', false);

alter type public.notification_kind add value if not exists 'group_invitation';
alter type public.notification_kind add value if not exists 'group_vote';

create table public.groups (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('romantic', 'friends')),
  name text not null check (char_length(btrim(name)) between 2 and 40),
  created_by uuid references public.profiles (id) on delete set null,
  admin_id uuid references public.profiles (id) on delete set null,
  approval_mode text not null default 'majority' check (approval_mode in ('majority', 'admin')),
  status text not null default 'active' check (status in ('active', 'closed')),
  created_at timestamptz not null default now()
);

create table public.group_members (
  group_id uuid not null references public.groups (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

create index group_members_user_idx on public.group_members (user_id);

create table public.group_invitations (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  invitee_id uuid not null references public.profiles (id) on delete cascade,
  invited_by uuid not null references public.profiles (id) on delete cascade,
  group_approved boolean not null default false,
  invitee_accepted boolean not null default false,
  status text not null default 'pending' check (status in ('pending', 'joined', 'declined', 'rejected', 'expired', 'cancelled')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  closed_at timestamptz
);

create unique index group_invitations_open_idx on public.group_invitations (group_id, invitee_id) where status = 'pending';
create index group_invitations_invitee_idx on public.group_invitations (invitee_id) where status = 'pending';

create table public.group_votes (
  invitation_id uuid not null references public.group_invitations (id) on delete cascade,
  voter_id uuid not null references public.profiles (id) on delete cascade,
  approve boolean not null,
  voted_at timestamptz not null default now(),
  primary key (invitation_id, voter_id)
);

-- Everything goes through RPCs (members must not read more than allowed).
alter table public.groups enable row level security;
alter table public.group_members enable row level security;
alter table public.group_invitations enable row level security;
alter table public.group_votes enable row level security;
revoke all on public.groups, public.group_members, public.group_invitations, public.group_votes from authenticated;

-- Group conversations.
alter table public.conversations
  add column group_id uuid unique references public.groups (id) on delete cascade,
  drop constraint conversations_check,
  add constraint conversations_kind_ref check (
    (kind = 'match' and match_id is not null and group_id is null)
    or (kind = 'group' and group_id is not null and match_id is null));

-- Helpers ----------------------------------------------------------------------------------------

create function private.is_group_member(p_group_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.group_members where group_id = p_group_id and user_id = p_user_id);
$$;

create function private.has_active_match(p_a uuid, p_b uuid, p_beer_only boolean default false)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.matches m
    where m.user_a = least(p_a, p_b) and m.user_b = greatest(p_a, p_b) and m.status = 'active'
      and (not p_beer_only or 'beer' = any (m.matched_drinks))
  );
$$;

-- Romantic rule (spec §8): the person has an active match with every current member.
create function private.matched_with_all_members(p_group_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select not exists (
    select 1 from public.group_members gm
    where gm.group_id = p_group_id and gm.user_id <> p_user_id
      and not private.has_active_match(gm.user_id, p_user_id)
  );
$$;

create function private.group_max(p_kind text)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select private.config_int(case when p_kind = 'romantic' then 'groups.romantic_max_members' else 'groups.friends_max_members' end);
$$;

create function private.group_premium_ok(g public.groups)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when (private.config('groups.creator_only_premium'))::boolean then g.created_by is not null and private.is_premium(g.created_by)
    else not exists (select 1 from public.group_members gm where gm.group_id = g.id and not private.is_premium(gm.user_id))
  end;
$$;

create function private.require_group_member(p_group_id uuid, p_user_id uuid)
returns public.groups
language plpgsql
security definer
set search_path = ''
as $$
declare
  g public.groups;
begin
  select * into g from public.groups where id = p_group_id;
  if g.id is null or g.status <> 'active' or not private.is_group_member(p_group_id, p_user_id) then
    raise exception 'group_not_found';
  end if;
  return g;
end;
$$;

create function private.add_group_member(p_group_id uuid, p_user_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.group_members (group_id, user_id) values (p_group_id, p_user_id) on conflict do nothing;
  insert into public.conversation_members (conversation_id, user_id)
  select c.id, p_user_id from public.conversations c where c.group_id = p_group_id
  on conflict do nothing;
$$;

-- Creation ---------------------------------------------------------------------------------------

create function public.create_group(p_kind text, p_name text, p_approval_mode text default 'majority')
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  drinks public.drink[];
  new_id uuid;
begin
  if (select status from public.profiles where id = uid) <> 'active' then
    raise exception 'profile_not_active';
  end if;
  if not private.is_premium(uid) then
    raise exception 'premium_required';
  end if;
  if p_kind not in ('romantic', 'friends') or p_approval_mode not in ('majority', 'admin') then
    raise exception 'invalid_request';
  end if;
  select array_agg(drink) into drinks from public.profile_drinks where user_id = uid;
  if p_kind = 'friends' and not ('beer' = any (drinks)) then
    raise exception 'beer_required';
  end if;
  if p_kind = 'romantic' and not (drinks && array['wine', 'coffee', 'cocktail']::public.drink[]) then
    raise exception 'romantic_drink_required';
  end if;
  insert into public.groups (kind, name, created_by, admin_id, approval_mode)
  values (p_kind, btrim(p_name), uid, uid, case when p_kind = 'friends' then p_approval_mode else 'majority' end)
  returning id into new_id;
  insert into public.conversations (kind, group_id) values ('group', new_id);
  perform private.add_group_member(new_id, uid);
  return new_id;
end;
$$;

-- Invitations ------------------------------------------------------------------------------------

-- Joins when both the group and the invitee agreed; rules are checked again at that moment.
create function private.try_join(p_invitation_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  inv public.group_invitations;
  g public.groups;
begin
  select * into inv from public.group_invitations where id = p_invitation_id for update;
  if inv.status <> 'pending' or not (inv.group_approved and inv.invitee_accepted) then
    return false;
  end if;
  select * into g from public.groups where id = inv.group_id for update;
  if g.status <> 'active' or inv.expires_at < now()
     or (select count(*) from public.group_members where group_id = g.id) >= private.group_max(g.kind)
     or (g.kind = 'romantic' and not private.matched_with_all_members(g.id, inv.invitee_id))
     or exists (select 1 from public.group_members gm where gm.group_id = g.id and private.is_blocked_pair(gm.user_id, inv.invitee_id)) then
    update public.group_invitations set status = 'cancelled', closed_at = now() where id = inv.id;
    return false;
  end if;
  perform private.add_group_member(g.id, inv.invitee_id);
  update public.group_invitations set status = 'joined', closed_at = now() where id = inv.id;
  return true;
end;
$$;

-- Friends groups: strict majority of the current members, or the admin alone.
create function private.evaluate_votes(p_invitation_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  inv public.group_invitations;
  g public.groups;
  members integer;
  yes integer;
  no integer;
begin
  select * into inv from public.group_invitations where id = p_invitation_id for update;
  if inv.status <> 'pending' or inv.group_approved then
    return;
  end if;
  select * into g from public.groups where id = inv.group_id;
  select count(*) into members from public.group_members where group_id = g.id;
  select count(*) filter (where v.approve), count(*) filter (where not v.approve) into yes, no
  from public.group_votes v
  join public.group_members gm on gm.group_id = g.id and gm.user_id = v.voter_id
  where v.invitation_id = inv.id and (g.approval_mode = 'majority' or v.voter_id = g.admin_id);

  if (g.approval_mode = 'admin' and yes > 0) or (g.approval_mode = 'majority' and yes * 2 > members) then
    update public.group_invitations set group_approved = true where id = inv.id;
    perform private.try_join(inv.id);
  elsif (g.approval_mode = 'admin' and no > 0) or (g.approval_mode = 'majority' and no * 2 >= members) then
    update public.group_invitations set status = 'rejected', closed_at = now() where id = inv.id;
  end if;
end;
$$;

create function public.invite_to_group(p_group_id uuid, p_invitee_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  g public.groups := private.require_group_member(p_group_id, uid);
  inv_id uuid;
  member uuid;
begin
  if not private.group_premium_ok(g) then
    raise exception 'premium_required';
  end if;
  if private.is_group_member(g.id, p_invitee_id) then
    raise exception 'already_member';
  end if;
  if (select count(*) from public.group_members where group_id = g.id)
     + (select count(*) from public.group_invitations where group_id = g.id and status = 'pending') >= private.group_max(g.kind) then
    raise exception 'group_full';
  end if;
  if not exists (select 1 from public.profiles where id = p_invitee_id and status in ('active', 'paused'))
     or exists (select 1 from public.group_members gm where gm.group_id = g.id and private.is_blocked_pair(gm.user_id, p_invitee_id)) then
    raise exception 'profile_unavailable';
  end if;
  if g.kind = 'romantic' and not private.matched_with_all_members(g.id, p_invitee_id) then
    raise exception 'must_match_all_members';
  end if;
  if g.kind = 'friends' and not private.has_active_match(uid, p_invitee_id, true) then
    raise exception 'beer_match_required';
  end if;

  insert into public.group_invitations (group_id, invitee_id, invited_by, group_approved, expires_at)
  values (g.id, p_invitee_id, uid, g.kind = 'romantic',
          now() + make_interval(days => private.config_int('groups.invitation_days')))
  returning id into inv_id;
  perform private.notify(p_invitee_id, 'group_invitation', jsonb_build_object('group_id', g.id));

  if g.kind = 'friends' then
    -- The inviter approves; the rest of the group (or the admin) decides.
    insert into public.group_votes (invitation_id, voter_id, approve) values (inv_id, uid, true);
    perform private.evaluate_votes(inv_id);
    for member in select user_id from public.group_members where group_id = g.id and user_id <> uid loop
      if g.approval_mode = 'majority' or member = g.admin_id then
        perform private.notify(member, 'group_vote', jsonb_build_object('group_id', g.id));
      end if;
    end loop;
  end if;
  return inv_id;
end;
$$;

create function public.vote_group_invitation(p_invitation_id uuid, p_approve boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  inv public.group_invitations;
  g public.groups;
begin
  select * into inv from public.group_invitations where id = p_invitation_id;
  if inv.id is null then
    raise exception 'invitation_not_found';
  end if;
  g := private.require_group_member(inv.group_id, uid);
  if g.kind <> 'friends' or inv.status <> 'pending' or inv.group_approved then
    raise exception 'vote_closed';
  end if;
  if g.approval_mode = 'admin' and g.admin_id <> uid then
    raise exception 'admin_only';
  end if;
  insert into public.group_votes (invitation_id, voter_id, approve) values (inv.id, uid, p_approve)
  on conflict (invitation_id, voter_id) do update set approve = excluded.approve, voted_at = now();
  perform private.evaluate_votes(inv.id);
end;
$$;

create function public.respond_group_invitation(p_invitation_id uuid, p_accept boolean)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  inv public.group_invitations;
begin
  select * into inv from public.group_invitations where id = p_invitation_id and invitee_id = uid for update;
  if inv.id is null or inv.status <> 'pending' then
    raise exception 'invitation_not_found';
  end if;
  if not p_accept then
    update public.group_invitations set status = 'declined', closed_at = now() where id = inv.id;
    return 'declined';
  end if;
  update public.group_invitations set invitee_accepted = true where id = inv.id;
  if private.try_join(inv.id) then
    return 'joined';
  end if;
  return (select case when status = 'pending' then 'waiting_for_group' else status end from public.group_invitations where id = inv.id);
end;
$$;

-- Leaving and blocking --------------------------------------------------------------------------------

create function private.remove_group_member(p_group_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  g public.groups;
  next_admin uuid;
begin
  delete from public.group_members where group_id = p_group_id and user_id = p_user_id;
  delete from public.conversation_members cm using public.conversations c
   where c.id = cm.conversation_id and c.group_id = p_group_id and cm.user_id = p_user_id;
  select * into g from public.groups where id = p_group_id for update;
  if not exists (select 1 from public.group_members where group_id = p_group_id) then
    update public.groups set status = 'closed' where id = p_group_id;
    update public.group_invitations set status = 'cancelled', closed_at = now() where group_id = p_group_id and status = 'pending';
  elsif g.admin_id = p_user_id or g.admin_id is null then
    select user_id into next_admin from public.group_members where group_id = p_group_id order by joined_at limit 1;
    update public.groups set admin_id = next_admin where id = p_group_id;
  end if;
end;
$$;

create function public.leave_group(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
begin
  perform private.require_group_member(p_group_id, uid);
  perform private.remove_group_member(p_group_id, uid);
end;
$$;

-- Blocking someone also makes the blocker leave every group they share (Q17).
create or replace function private.block(p_blocker uuid, p_blocked uuid, p_source text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  shared uuid;
begin
  if p_blocker = p_blocked then
    raise exception 'cannot_block_self';
  end if;
  insert into public.blocks (blocker_id, blocked_id, source) values (p_blocker, p_blocked, p_source)
  on conflict (blocker_id, blocked_id) do nothing;
  update public.matches set status = 'unmatched', ended_at = now(), ended_by = p_blocker
   where status = 'active' and user_a = least(p_blocker, p_blocked) and user_b = greatest(p_blocker, p_blocked);
  delete from public.friendships where user_a = least(p_blocker, p_blocked) and user_b = greatest(p_blocker, p_blocked);
  for shared in
    select a.group_id from public.group_members a
    join public.group_members b on b.group_id = a.group_id and b.user_id = p_blocked
    where a.user_id = p_blocker
  loop
    perform private.remove_group_member(shared, p_blocker);
  end loop;
  update public.group_invitations set status = 'cancelled', closed_at = now()
   where status = 'pending' and ((invitee_id = p_blocked and invited_by = p_blocker) or (invitee_id = p_blocker and invited_by = p_blocked));
end;
$$;

-- Reads -------------------------------------------------------------------------------------------------

create function private.main_photo(p_user_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select storage_path from public.photos where user_id = p_user_id and moderation_status = 'approved' order by position limit 1;
$$;

create function public.get_my_groups()
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
      'id', g.id, 'kind', g.kind, 'name', g.name, 'is_admin', g.admin_id = uid,
      'conversation_id', c.id,
      'members', (select count(*) from public.group_members x where x.group_id = g.id),
      'last_message', (select jsonb_build_object('body', left(m.body, 120), 'sender', p.first_name, 'mine', m.sender_id = uid, 'created_at', m.created_at)
                       from public.messages m join public.profiles p on p.id = m.sender_id
                       where m.conversation_id = c.id order by m.created_at desc limit 1),
      'unread_count', (select count(*) from public.messages m join public.conversation_members me on me.conversation_id = m.conversation_id and me.user_id = uid
                       where m.conversation_id = c.id and m.sender_id <> uid and m.created_at > coalesce(me.last_read_at, '-infinity'::timestamptz)),
      'pending_votes', (select count(*) from public.group_invitations i
                        where i.group_id = g.id and i.status = 'pending' and not i.group_approved
                          and (g.approval_mode = 'majority' or g.admin_id = uid)
                          and not exists (select 1 from public.group_votes v where v.invitation_id = i.id and v.voter_id = uid))
    ) order by coalesce(c.last_message_at, g.created_at) desc)
    from public.group_members gm
    join public.groups g on g.id = gm.group_id and g.status = 'active'
    join public.conversations c on c.group_id = g.id
    where gm.user_id = uid
  ), '[]'::jsonb);
end;
$$;

-- A member's view: members (first names, main photos), pending invitations to vote on
-- (newcomer's first name and main photo only).
create function public.get_group(p_group_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  g public.groups := private.require_group_member(p_group_id, uid);
  newcomer uuid;
begin
  -- Members may load each other's (and pending newcomers') photos, as for a feed card.
  for newcomer in
    select user_id from public.group_members where group_id = g.id and user_id <> uid
    union
    select invitee_id from public.group_invitations where group_id = g.id and status = 'pending'
  loop
    insert into private.feed_impressions (viewer_id, target_id) values (uid, newcomer)
    on conflict (viewer_id, target_id) do update set served_at = now();
  end loop;

  return jsonb_build_object(
    'id', g.id, 'kind', g.kind, 'name', g.name, 'approval_mode', g.approval_mode,
    'is_admin', g.admin_id = uid,
    'max_members', private.group_max(g.kind),
    'conversation_id', (select id from public.conversations where group_id = g.id),
    'members', (select jsonb_agg(jsonb_build_object('id', p.id, 'first_name', p.first_name, 'photo_path', private.main_photo(p.id),
                                                    'is_admin', p.id = g.admin_id, 'me', p.id = uid) order by gm.joined_at)
                from public.group_members gm join public.profiles p on p.id = gm.user_id where gm.group_id = g.id),
    'invitations', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', i.id, 'first_name', p.first_name, 'photo_path', private.main_photo(p.id),
        'invited_by', inviter.first_name, 'group_approved', i.group_approved, 'invitee_accepted', i.invitee_accepted,
        'my_vote', (select v.approve from public.group_votes v where v.invitation_id = i.id and v.voter_id = uid),
        'can_vote', g.kind = 'friends' and not i.group_approved and (g.approval_mode = 'majority' or g.admin_id = uid)
      ) order by i.created_at)
      from public.group_invitations i
      join public.profiles p on p.id = i.invitee_id
      join public.profiles inviter on inviter.id = i.invited_by
      where i.group_id = g.id and i.status = 'pending'), '[]'::jsonb)
  );
end;
$$;

-- Matches the caller could invite (romantic: matched with every member; friends: Bière match).
create function public.get_group_invite_candidates(p_group_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  g public.groups := private.require_group_member(p_group_id, uid);
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', p.id, 'first_name', p.first_name) order by p.first_name)
    from public.matches m
    join public.profiles p on p.id = case when m.user_a = uid then m.user_b else m.user_a end
    where uid in (m.user_a, m.user_b) and m.status = 'active'
      and p.status in ('active', 'paused')
      and not private.is_group_member(g.id, p.id)
      and not exists (select 1 from public.group_invitations i where i.group_id = g.id and i.invitee_id = p.id and i.status = 'pending')
      and case when g.kind = 'romantic' then private.matched_with_all_members(g.id, p.id)
               else 'beer' = any (m.matched_drinks) end
  ), '[]'::jsonb);
end;
$$;

-- The invitee's view before accepting: group name, kind, size, first names, and who invites.
create function public.get_my_group_invitations()
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
      'id', i.id, 'kind', g.kind, 'name', g.name,
      'size', (select count(*) from public.group_members x where x.group_id = g.id),
      'member_first_names', (select jsonb_agg(p.first_name order by gm.joined_at)
                             from public.group_members gm join public.profiles p on p.id = gm.user_id where gm.group_id = g.id),
      'invited_by', jsonb_build_object('first_name', inviter.first_name,
                                       'match_id', (select m.id from public.matches m
                                                    where m.user_a = least(uid, inviter.id) and m.user_b = greatest(uid, inviter.id))),
      'group_approved', i.group_approved, 'accepted', i.invitee_accepted, 'expires_at', i.expires_at
    ) order by i.created_at desc)
    from public.group_invitations i
    join public.groups g on g.id = i.group_id and g.status = 'active'
    join public.profiles inviter on inviter.id = i.invited_by
    where i.invitee_id = uid and i.status = 'pending' and i.expires_at > now()
  ), '[]'::jsonb);
end;
$$;

-- Sender first names for a group chat (members only).
create function public.get_conversation_people(p_conversation_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(p.id, p.first_name), '{}'::jsonb)
  from public.conversation_members cm
  join public.profiles p on p.id = cm.user_id
  where cm.conversation_id = p_conversation_id and public.is_conversation_member(p_conversation_id);
$$;

-- Scheduled: expire invitations.
create function private.expire_group_invitations()
returns integer
language sql
security definer
set search_path = ''
as $$
  with expired as (
    update public.group_invitations set status = 'expired', closed_at = now()
    where status = 'pending' and expires_at < now()
    returning 1
  )
  select count(*)::integer from expired;
$$;

create or replace function private.run_scheduled_jobs()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  result jsonb := jsonb_build_object(
    'expired', private.expire_matches(),
    'reminders', private.queue_first_message_reminders(),
    'your_turn', private.queue_your_turn(),
    'outing_feedback', private.queue_outing_feedback(),
    'group_invitations', private.expire_group_invitations()
  );
begin
  if private.due('referrals', interval '1 hour') then
    result := result || jsonb_build_object('referrals', private.process_referrals(),
                                           'offer_codes', private.assign_offer_codes());
  end if;
  if private.due('daily', interval '1 day') then
    result := result || jsonb_build_object('popularity', private.compute_popularity(),
                                           'monthly_boosts', private.grant_monthly_boosts());
  end if;
  return result;
end;
$$;

do $$
declare
  f text;
begin
  foreach f in array array[
    'public.create_group(text, text, text)',
    'public.invite_to_group(uuid, uuid)',
    'public.vote_group_invitation(uuid, boolean)',
    'public.respond_group_invitation(uuid, boolean)',
    'public.leave_group(uuid)',
    'public.get_my_groups()',
    'public.get_group(uuid)',
    'public.get_group_invite_candidates(uuid)',
    'public.get_my_group_invitations()',
    'public.get_conversation_people(uuid)'
  ]
  loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end;
$$;
