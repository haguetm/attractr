-- Phase 9 (spec §6): couple accounts.
--
-- Model: a couple is a technical profile (profiles.is_couple) backed by a login-less auth
-- user, driven by its two partners, who keep their own verified individual accounts. The
-- feed, likes, matches, chat, blocks and erasure reuse the existing machinery; partners act
-- "as the couple" through dedicated RPCs.
--   * Path A: both have an account; one invites the other (pseudo or link), the link exists
--     only once accepted (couple_invitations: pending, accepted, refused, expired).
--   * Path B: created together at signup: the partner opens the link and completes their own
--     signup (age, selfie, consents). Same invitation, accepted after their onboarding.
--   The shared profile is published only once both partners are verified.
-- Rules: shared photos need the other partner's approval; closed couple = Bière only, and
-- both individual profiles switch to Bière only; open couple = drinks by structure, each
-- partner keeps their individual profile visible or hides it, and individual cards show
-- "en relation ouverte". A couple's like needs both partners (couple_like_approvals). Chats
-- of a couple include both partners. One partner can leave in one tap. Neither partner sees
-- the other's personal likes or matches.

insert into public.app_config (key, value, description, is_public) values
  ('couples.invitation_days', '7', 'Validity of a couple invitation (provisoire).', false),
  ('couples.like_approval_days', '3', 'A couple like proposal expires after this many days (provisoire).', false);

alter type public.notification_kind add value if not exists 'couple_request';
alter type public.notification_kind add value if not exists 'couple_approval';

alter table public.profiles
  add column is_couple boolean not null default false,
  add column hidden_by_couple boolean not null default false;

create table public.couples (
  id uuid primary key references public.profiles (id) on delete cascade,
  partner_a uuid not null references public.profiles (id) on delete cascade,
  partner_b uuid not null references public.profiles (id) on delete cascade,
  status text not null default 'setup' check (status in ('setup', 'published')),
  kind text check (kind in ('closed', 'open')),
  seeking_target text[] not null default '{person}' check (seeking_target <@ array['person', 'couple']::text[] and cardinality(seeking_target) > 0),
  created_at timestamptz not null default now(),
  published_at timestamptz,
  check (partner_a <> partner_b)
);

create unique index couples_partner_a_idx on public.couples (partner_a);
create unique index couples_partner_b_idx on public.couples (partner_b);

create table public.couple_invitations (
  id uuid primary key default gen_random_uuid(),
  code text unique,
  from_user uuid not null references public.profiles (id) on delete cascade,
  to_user uuid references public.profiles (id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'refused', 'expired')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  responded_at timestamptz
);

create table public.couple_like_approvals (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null references public.couples (id) on delete cascade,
  target_id uuid not null references public.profiles (id) on delete cascade,
  target_kind public.like_target not null,
  target_ref text not null,
  proposed_by uuid not null references public.profiles (id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'expired')),
  created_at timestamptz not null default now(),
  decided_at timestamptz
);

create unique index couple_like_approvals_open_idx on public.couple_like_approvals (couple_id, target_id) where status = 'pending';

alter table public.photos
  add column partner_approved boolean not null default true,
  add column uploaded_by uuid references public.profiles (id) on delete set null;

alter table public.couples enable row level security;
alter table public.couple_invitations enable row level security;
alter table public.couple_like_approvals enable row level security;
revoke all on public.couples, public.couple_invitations, public.couple_like_approvals from authenticated;

-- Helpers -------------------------------------------------------------------------------------

create function private.couple_of(p_user_id uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select id from public.couples where p_user_id in (partner_a, partner_b);
$$;

create function private.partner_of(p_user_id uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select case when partner_a = p_user_id then partner_b else partner_a end
  from public.couples where p_user_id in (partner_a, partner_b);
$$;

-- Identities a user acts as: themself, and their couple once published.
create function private.acting_ids(p_user_id uuid)
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $$
  select array[p_user_id] || coalesce((select array[c.id] from public.couples c
                                       where p_user_id in (c.partner_a, c.partner_b) and c.status = 'published'), '{}');
$$;

-- For storage policies (evaluated as the caller): is this folder my couple's?
create function public.is_my_couple(p_id text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.couples c
                 where c.id::text = p_id and (select auth.uid()) in (c.partner_a, c.partner_b));
$$;

revoke execute on function public.is_my_couple(text) from public, anon;
grant execute on function public.is_my_couple(text) to authenticated;

create policy photos_insert_couple on storage.objects for insert to authenticated
  with check (bucket_id = 'photos' and public.is_my_couple((storage.foldername(name))[1]));
create policy photos_delete_couple on storage.objects for delete to authenticated
  using (bucket_id = 'photos' and public.is_my_couple((storage.foldername(name))[1]));

-- Matching context of a participant (individual or couple), for private.match_ctx.
create function private.participant_ctx(p_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'is_couple', p.is_couple,
    'open_to_couples', p.open_to_couples,
    'genders', case when p.is_couple
                    then (select to_jsonb(array[a.gender, b.gender]) from public.couples c
                          join public.profiles a on a.id = c.partner_a join public.profiles b on b.id = c.partner_b where c.id = p.id)
                    else to_jsonb(array[p.gender]) end,
    'drinks', to_jsonb(array(select d.drink from public.profile_drinks d where d.user_id = p.id order by d.drink)),
    'target', coalesce((select to_jsonb(c.seeking_target) from public.couples c where c.id = p.id), '[]'::jsonb),
    's', private.read_sensitive(p.id)
  )
  from public.profiles p where p.id = p_id;
$$;

-- Compatibility for any pair of participants. Individual pairs follow private.match_drinks
-- exactly; with a couple (DECISIONS phase 9):
--   romantic crossing: an individual must be "ouvert aux couples", a couple must look for
--     a person / a couple; sought genders overlap both ways (a couple = its two genders);
--     structures compatible; polyamory compositions are not matched for couples (out of
--     scope V1: groups handle compositions).
--   Bière crossing: friend genders overlap both ways (no "ouvert aux couples" needed, Q8).
create function private.match_ctx(p_v jsonb, p_c jsonb)
returns public.drink[]
language plpgsql
stable
set search_path = ''
as $$
declare
  all_genders constant public.gender[] := enum_range(null::public.gender);
  v_g public.gender[] := private.jsonb_genders(p_v -> 'genders');
  c_g public.gender[] := private.jsonb_genders(p_c -> 'genders');
  v_s jsonb := p_v -> 's';
  c_s jsonb := p_c -> 's';
  v_couple boolean := coalesce((p_v ->> 'is_couple')::boolean, false);
  c_couple boolean := coalesce((p_c ->> 'is_couple')::boolean, false);
  v_seek public.gender[] := private.jsonb_genders(v_s -> 'seeking_genders');
  c_seek public.gender[] := private.jsonb_genders(c_s -> 'seeking_genders');
  v_friends public.gender[] := coalesce(nullif(private.jsonb_genders(v_s -> 'friend_genders'), '{}'), all_genders);
  c_friends public.gender[] := coalesce(nullif(private.jsonb_genders(c_s -> 'friend_genders'), '{}'), all_genders);
  v_struct public.relationship_structure := (v_s ->> 'structure')::public.relationship_structure;
  c_struct public.relationship_structure := (c_s ->> 'structure')::public.relationship_structure;
  v_comp public.gender[] := case when v_couple then null else private.composition_genders(v_s -> 'composition') end;
  c_comp public.gender[] := case when c_couple then null else private.composition_genders(c_s -> 'composition') end;
  v_accepts boolean := case when c_couple then (case when v_couple then (p_v -> 'target') ? 'couple' else coalesce((p_v ->> 'open_to_couples')::boolean, false) end)
                            else (not v_couple or (p_v -> 'target') ? 'person') end;
  c_accepts boolean := case when v_couple then (case when c_couple then (p_c -> 'target') ? 'couple' else coalesce((p_c ->> 'open_to_couples')::boolean, false) end)
                            else (not c_couple or (p_c -> 'target') ? 'person') end;
  result public.drink[];
begin
  select coalesce(array_agg(distinct dc order by dc), '{}') into result
  from jsonb_array_elements_text(p_v -> 'drinks') dvt
  cross join jsonb_array_elements_text(p_c -> 'drinks') dct
  cross join lateral (select dvt::public.drink as dv, dct::public.drink as dc) d
  join public.drink_compatibility m on m.drink_a = d.dv and m.drink_b = d.dc and m.compatible
  where case
    when d.dv = 'beer' and d.dc = 'beer' then c_g && v_friends and v_g && c_friends
    else v_accepts and c_accepts
      and c_g && v_seek and v_g && c_seek
      and (v_struct is null or c_struct is null or exists (
            select 1 from public.structure_compatibility sc
            where sc.structure_a = v_struct and sc.structure_b = c_struct and sc.compatible))
      and (v_comp is null or c_g && v_comp)
      and (c_comp is null or v_g && c_comp)
  end;
  return result;
end;
$$;

-- Closed couple: each individual profile switches to Bière only (no cooldown, Q12).
create function private.force_beer_only(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  old_drinks public.drink[];
begin
  select array_agg(drink order by drink) into old_drinks from public.profile_drinks where user_id = p_user_id;
  if old_drinks is distinct from array['beer']::public.drink[] then
    delete from public.profile_drinks where user_id = p_user_id;
    insert into public.profile_drinks (user_id, drink) values (p_user_id, 'beer');
    insert into private.drink_change_history (user_id, old_drinks, new_drinks, reason)
    values (p_user_id, old_drinks, array['beer']::public.drink[], 'couple_closed');
  end if;
  update public.profiles set open_to_couples = false where id = p_user_id;
  perform private.write_sensitive(p_user_id, jsonb_build_object('situation', 'closed_couple', 'structure', null, 'composition', null));
end;
$$;

-- Invitations --------------------------------------------------------------------------------------

create function private.check_can_couple(p_user_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if exists (select 1 from public.profiles where id = p_user_id and is_couple) then
    raise exception 'invalid_request';
  end if;
  if private.couple_of(p_user_id) is not null then
    raise exception 'already_in_couple';
  end if;
end;
$$;

create function public.create_couple_invitation()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  code text := upper(encode(extensions.gen_random_bytes(6), 'hex'));
begin
  perform private.check_can_couple(uid);
  insert into public.couple_invitations (code, from_user, expires_at)
  values (code, uid, now() + make_interval(days => private.config_int('couples.invitation_days')));
  return code;
end;
$$;

create function public.request_couple_by_username(p_username text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  other uuid;
begin
  perform private.check_can_couple(uid);
  select id into other from public.profiles where lower(username) = lower(btrim(p_username)) and not is_couple;
  if other is null or other = uid or private.is_blocked_pair(uid, other) then
    raise exception 'profile_unavailable';
  end if;
  insert into public.couple_invitations (from_user, to_user, expires_at)
  values (uid, other, now() + make_interval(days => private.config_int('couples.invitation_days')));
  perform private.notify(other, 'couple_request', '{}');
end;
$$;

-- Creates the technical profile and the couple row (status 'setup').
create function private.create_couple(p_a uuid, p_b uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  couple_id uuid := gen_random_uuid();
  a public.profiles;
  b public.profiles;
begin
  select * into a from public.profiles where id = p_a;
  select * into b from public.profiles where id = p_b;
  -- Login-less auth user: the profile row (and every cascade) hangs on it.
  insert into auth.users (instance_id, id, aud, role, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, banned_until)
  values ('00000000-0000-0000-0000-000000000000', couple_id, 'authenticated', 'authenticated',
          '{"provider":"couple","kind":"couple"}', '{}', now(), now(), 'infinity');
  update public.profiles
     set is_couple = true,
         first_name = left(a.first_name || ' & ' || b.first_name, 40),
         birth_date = greatest(a.birth_date, b.birth_date),
         gender = a.gender,
         location = a.location, location_source = a.location_source,
         country_code = a.country_code, department_code = a.department_code, region_code = a.region_code
   where id = couple_id;
  insert into public.couples (id, partner_a, partner_b) values (couple_id, p_a, p_b);
  return couple_id;
end;
$$;

create function public.preview_couple_invitation(p_code text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('first_name', p.first_name)
  from public.couple_invitations i join public.profiles p on p.id = i.from_user
  where i.code = upper(btrim(p_code)) and i.status = 'pending' and i.expires_at > now();
$$;

-- Path B ends here too: the partner opens the link once their own signup is complete.
create function public.accept_couple_invitation(p_code text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  inv public.couple_invitations;
  couple_id uuid;
begin
  select * into inv from public.couple_invitations where code = upper(btrim(p_code)) for update;
  if inv.id is null or inv.status <> 'pending' or inv.expires_at <= now() or inv.from_user = uid then
    raise exception 'invite_invalid';
  end if;
  if (select status from public.profiles where id = uid) = 'onboarding' then
    raise exception 'onboarding_required';
  end if;
  perform private.check_can_couple(uid);
  perform private.check_can_couple(inv.from_user);
  update public.couple_invitations set status = 'accepted', to_user = uid, responded_at = now() where id = inv.id;
  couple_id := private.create_couple(inv.from_user, uid);
  perform private.notify(inv.from_user, 'couple_request', '{}');
  return couple_id;
end;
$$;

create function public.respond_couple_request(p_invitation_id uuid, p_accept boolean)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  inv public.couple_invitations;
begin
  select * into inv from public.couple_invitations where id = p_invitation_id and to_user = uid for update;
  if inv.id is null or inv.status <> 'pending' or inv.expires_at <= now() then
    raise exception 'invite_invalid';
  end if;
  if not p_accept then
    update public.couple_invitations set status = 'refused', responded_at = now() where id = inv.id;
    return null;
  end if;
  perform private.check_can_couple(uid);
  perform private.check_can_couple(inv.from_user);
  update public.couple_invitations set status = 'accepted', responded_at = now() where id = inv.id;
  return private.create_couple(inv.from_user, uid);
end;
$$;

-- Setup and publication ---------------------------------------------------------------------------

-- Published once: profile set (kind, drinks), a shared photo approved by both and by
-- moderation, and both partners verified (spec §6, path B).
create function private.refresh_couple(p_couple_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.couples;
  ready boolean;
begin
  select * into c from public.couples where id = p_couple_id for update;
  if c.id is null then
    return null;
  end if;
  ready := c.kind is not null
    and exists (select 1 from public.profile_drinks where user_id = c.id)
    and exists (select 1 from public.photos where user_id = c.id and partner_approved and moderation_status = 'approved')
    and (select bool_and(verification_status = 'verified' and status in ('active', 'paused'))
         from public.profiles where id in (c.partner_a, c.partner_b));
  if ready and c.status = 'setup' then
    update public.couples set status = 'published', published_at = now() where id = c.id;
    update public.profiles set status = 'active', verification_status = 'verified', verified_at = now() where id = c.id;
    return 'published';
  elsif not ready and c.status = 'published' then
    update public.couples set status = 'setup' where id = c.id;
    update public.profiles set status = 'onboarding' where id = c.id;
    return 'setup';
  end if;
  return c.status;
end;
$$;

create function private.require_my_couple(p_user_id uuid)
returns public.couples
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.couples;
begin
  select * into c from public.couples where p_user_id in (partner_a, partner_b);
  if c.id is null then
    raise exception 'couple_not_found';
  end if;
  return c;
end;
$$;

-- kind: 'closed' (Bière only) or 'open'; target: what the couple looks for (person, couple).
create function public.set_couple_profile(
  p_kind text,
  p_drinks public.drink[],
  p_structure public.relationship_structure default null,
  p_composition jsonb default null,
  p_seeking_target text[] default '{person}',
  p_seeking_genders public.gender[] default null,
  p_bio text default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  c public.couples := private.require_my_couple(uid);
  err text;
  drinks public.drink[] := case when p_kind = 'closed' then array['beer']::public.drink[] else p_drinks end;
begin
  if p_kind not in ('closed', 'open') or coalesce(cardinality(p_seeking_target), 0) = 0
     or not (p_seeking_target <@ array['person', 'couple']::text[]) then
    raise exception 'invalid_request';
  end if;
  err := private.validate_intent(case when p_kind = 'closed' then 'closed_couple' else 'consensual_relationship' end::public.situation,
                                 drinks, case when p_kind = 'closed' then null else p_structure end,
                                 case when p_kind = 'closed' then null else p_composition end, false);
  if err is not null then
    raise exception '%', err;
  end if;
  if drinks && array['wine', 'coffee', 'cocktail']::public.drink[] and coalesce(cardinality(p_seeking_genders), 0) = 0 then
    raise exception 'seeking_genders_required';
  end if;

  update public.couples set kind = p_kind, seeking_target = p_seeking_target where id = c.id;
  update public.profiles set bio = nullif(btrim(p_bio), ''), open_to_couples = 'couple' = any (p_seeking_target) where id = c.id;
  delete from public.profile_drinks where user_id = c.id;
  insert into public.profile_drinks (user_id, drink) select c.id, unnest(drinks);
  perform private.write_sensitive(c.id, jsonb_build_object(
    'situation', case when p_kind = 'closed' then 'closed_couple' else 'consensual_relationship' end,
    'structure', case when p_kind = 'closed' then null else p_structure end,
    'composition', case when p_kind = 'closed' then null else p_composition end,
    'seeking_genders', to_jsonb(coalesce(p_seeking_genders, enum_range(null::public.gender))),
    'friend_genders', to_jsonb(enum_range(null::public.gender))));

  if p_kind = 'closed' then
    perform private.force_beer_only(c.partner_a);
    perform private.force_beer_only(c.partner_b);
    update public.profiles set hidden_by_couple = false where id in (c.partner_a, c.partner_b);
  end if;
  return private.refresh_couple(c.id);
end;
$$;

-- Open couples only: each partner keeps their individual profile visible or hides it.
create function public.set_my_couple_visibility(p_hidden boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  c public.couples := private.require_my_couple(uid);
begin
  if c.kind is distinct from 'open' then
    raise exception 'invalid_request';
  end if;
  update public.profiles set hidden_by_couple = p_hidden where id = uid;
end;
$$;

-- Shared photos (folder = couple id) need the other partner's approval (spec §6).
create function public.add_couple_photo(p_storage_path text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  c public.couples := private.require_my_couple(uid);
  n integer;
  new_id uuid;
begin
  perform private.require_own_object('photos', p_storage_path, c.id);
  select count(*) into n from public.photos where user_id = c.id;
  if n >= private.config_int('photos.max_count') then
    raise exception 'photos_max_reached';
  end if;
  insert into public.photos (user_id, storage_path, position, partner_approved, uploaded_by)
  values (c.id, p_storage_path, n + 1, false, uid)
  returning id into new_id;
  perform private.notify(case when c.partner_a = uid then c.partner_b else c.partner_a end, 'couple_approval', '{}');
  return new_id;
end;
$$;

create function public.approve_couple_photo(p_photo_id uuid, p_approve boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  c public.couples := private.require_my_couple(uid);
  ph public.photos;
begin
  select * into ph from public.photos where id = p_photo_id and user_id = c.id;
  if ph.id is null or ph.uploaded_by = uid then
    raise exception 'photo_not_found';
  end if;
  if p_approve then
    update public.photos set partner_approved = true where id = ph.id;
  else
    delete from public.photos where id = ph.id;
    insert into private.storage_cleanup (bucket, path) values ('photos', ph.storage_path);
  end if;
  perform private.refresh_couple(c.id);
end;
$$;

-- Likes as a couple: proposed by one partner, sent once the other approves ----------------------------

-- like_profile body, for any actor (individual or couple). Match creation adds both
-- partners of a couple to the conversation.
create function private.like_as(p_actor uuid, p_target_id uuid, p_target_kind public.like_target, p_target_ref text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor public.profiles;
  target public.profiles;
  is_answer boolean;
  quota jsonb;
  new_match public.matches;
  v_conversation_id uuid;
  side uuid;
  person uuid;
begin
  if p_target_id = p_actor then
    raise exception 'cannot_swipe_self';
  end if;
  select * into actor from public.profiles where id = p_actor;
  if actor.status <> 'active' then
    raise exception 'profile_not_active';
  end if;
  select * into target from public.profiles where id = p_target_id;
  if target.id is null or target.status <> 'active'
     or exists (select 1 from public.blocks b
                where (b.blocker_id = p_actor and b.blocked_id = p_target_id) or (b.blocker_id = p_target_id and b.blocked_id = p_actor)) then
    raise exception 'profile_unavailable';
  end if;

  is_answer := exists (select 1 from public.swipes s where s.actor_id = p_target_id and s.target_id = p_actor and s.action = 'like');
  if not is_answer and not exists (select 1 from private.feed_impressions i where i.viewer_id = p_actor and i.target_id = p_target_id) then
    raise exception 'profile_unavailable';
  end if;
  if p_target_kind = 'photo' then
    if not exists (select 1 from public.photos ph where ph.user_id = p_target_id and ph.id::text = p_target_ref
                   and ph.moderation_status <> 'rejected' and ph.partner_approved) then
      raise exception 'invalid_like_target';
    end if;
  elsif not exists (select 1 from public.profile_prompts q where q.user_id = p_target_id and q.question_code = p_target_ref) then
    raise exception 'invalid_like_target';
  end if;
  if exists (select 1 from public.swipes s where s.actor_id = p_actor and s.target_id = p_target_id and s.action = 'like') then
    raise exception 'already_liked';
  end if;
  if not is_answer then
    quota := private.like_quota(p_actor);
    if not (quota ->> 'unlimited')::boolean and (quota ->> 'remaining')::integer <= 0 then
      raise exception 'like_quota_reached';
    end if;
  end if;

  insert into public.swipes (actor_id, target_id, action, target_kind, target_ref, quota_counted)
  values (p_actor, p_target_id, 'like', p_target_kind, p_target_ref, not is_answer)
  on conflict (actor_id, target_id) do update
    set action = 'like', target_kind = excluded.target_kind, target_ref = excluded.target_ref,
        quota_counted = excluded.quota_counted, created_at = now();

  if is_answer then
    insert into public.matches (user_a, user_b, matched_drinks, first_message_deadline)
    values (least(p_actor, p_target_id), greatest(p_actor, p_target_id),
            private.match_ctx(private.participant_ctx(p_actor), private.participant_ctx(p_target_id)),
            now() + make_interval(hours => private.config_int('match.first_message_window_hours')))
    on conflict (user_a, user_b) do nothing
    returning * into new_match;

    if new_match.id is not null then
      insert into public.conversations (kind, match_id) values ('match', new_match.id) returning id into v_conversation_id;
      foreach side in array array[p_actor, p_target_id] loop
        for person in
          select side where not exists (select 1 from public.couples c where c.id = side)
          union all
          select unnest(array[c.partner_a, c.partner_b]) from public.couples c where c.id = side
        loop
          insert into public.conversation_members (conversation_id, user_id) values (v_conversation_id, person) on conflict do nothing;
          perform private.notify(person, 'new_match', jsonb_build_object('match_id', new_match.id));
        end loop;
      end loop;
    end if;
  end if;

  return jsonb_build_object('matched', new_match.id is not null, 'match_id', new_match.id,
                            'conversation_id', v_conversation_id, 'quota', private.like_quota(p_actor));
end;
$$;

create or replace function public.like_profile(p_target_id uuid, p_target_kind public.like_target, p_target_ref text)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select private.like_as(private.require_user(), p_target_id, p_target_kind, p_target_ref);
$$;

create function public.propose_couple_like(p_target_id uuid, p_target_kind public.like_target, p_target_ref text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  c public.couples := private.require_my_couple(uid);
  new_id uuid;
begin
  if c.status <> 'published' then
    raise exception 'couple_not_published';
  end if;
  if exists (select 1 from public.swipes where actor_id = c.id and target_id = p_target_id and action = 'like') then
    raise exception 'already_liked';
  end if;
  insert into public.couple_like_approvals (couple_id, target_id, target_kind, target_ref, proposed_by)
  values (c.id, p_target_id, p_target_kind, p_target_ref, uid)
  on conflict (couple_id, target_id) where status = 'pending' do nothing
  returning id into new_id;
  if new_id is not null then
    perform private.notify(case when c.partner_a = uid then c.partner_b else c.partner_a end, 'couple_approval', '{}');
  end if;
  return new_id;
end;
$$;

create function public.decide_couple_like(p_approval_id uuid, p_approve boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  c public.couples := private.require_my_couple(uid);
  a public.couple_like_approvals;
begin
  select * into a from public.couple_like_approvals where id = p_approval_id and couple_id = c.id for update;
  if a.id is null or a.status <> 'pending' then
    raise exception 'approval_not_found';
  end if;
  if a.proposed_by = uid then
    raise exception 'partner_must_approve';
  end if;
  if a.created_at < now() - make_interval(days => private.config_int('couples.like_approval_days')) then
    update public.couple_like_approvals set status = 'expired', decided_at = now() where id = a.id;
    raise exception 'approval_expired';
  end if;
  update public.couple_like_approvals set status = case when p_approve then 'approved' else 'rejected' end, decided_at = now()
   where id = a.id;
  if not p_approve then
    return jsonb_build_object('matched', false);
  end if;
  return private.like_as(c.id, a.target_id, a.target_kind, a.target_ref);
end;
$$;

-- Passing as a couple needs no approval.
drop function public.pass_profile(uuid);

create function public.pass_profile(p_target_id uuid, p_as_couple boolean default false)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  actor uuid := case when p_as_couple then private.couple_of(uid) else uid end;
begin
  if actor is null then
    raise exception 'couple_not_found';
  end if;
  if p_target_id = actor then
    raise exception 'cannot_swipe_self';
  end if;
  insert into public.swipes (actor_id, target_id, action) values (actor, p_target_id, 'pass')
  on conflict (actor_id, target_id) do update set created_at = now() where public.swipes.action = 'pass';
end;
$$;

-- Leaving: one partner, one tap, no consent needed. The couple profile is erased.
create function public.leave_couple()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  c public.couples := private.require_my_couple(uid);
begin
  update public.profiles set hidden_by_couple = false where id in (c.partner_a, c.partner_b);
  insert into private.storage_cleanup (bucket, path) select 'photos', storage_path from public.photos where user_id = c.id;
  delete from auth.users where id = c.id;  -- cascades: profile, couple, its likes, matches, chats
end;
$$;

-- The caller's couple, from their own point of view.
create function public.get_my_couple()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  c public.couples;
  partner public.profiles;
begin
  select * into c from public.couples where uid in (partner_a, partner_b);
  if c.id is null then
    return jsonb_build_object('couple', null,
      'invitations', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'from', p.first_name, 'expires_at', i.expires_at))
                               from public.couple_invitations i join public.profiles p on p.id = i.from_user
                               where i.to_user = uid and i.status = 'pending' and i.expires_at > now()), '[]'::jsonb));
  end if;
  perform private.refresh_couple(c.id);
  select * into c from public.couples where id = c.id;
  select * into partner from public.profiles where id = case when c.partner_a = uid then c.partner_b else c.partner_a end;
  -- The partner may see the couple's photos (folder = couple id) through can_view_photos_of.
  return jsonb_build_object(
    'couple', jsonb_build_object(
      'id', c.id, 'status', c.status, 'kind', c.kind, 'seeking_target', to_jsonb(c.seeking_target),
      'name', (select first_name from public.profiles where id = c.id),
      'bio', (select bio from public.profiles where id = c.id),
      'drinks', coalesce((select jsonb_agg(drink order by drink) from public.profile_drinks where user_id = c.id), '[]'::jsonb),
      'sensitive', private.read_sensitive(c.id),
      'partner', jsonb_build_object('first_name', partner.first_name, 'verified', partner.verification_status = 'verified'),
      'me_verified', (select verification_status = 'verified' from public.profiles where id = uid),
      'my_individual_hidden', (select hidden_by_couple from public.profiles where id = uid),
      'photos', coalesce((select jsonb_agg(jsonb_build_object('id', ph.id, 'storage_path', ph.storage_path,
                             'partner_approved', ph.partner_approved, 'moderation_status', ph.moderation_status,
                             'needs_my_approval', not ph.partner_approved and ph.uploaded_by is distinct from uid) order by ph.position)
                          from public.photos ph where ph.user_id = c.id), '[]'::jsonb),
      'pending_likes', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'target_first_name', t.first_name,
                                   'mine', a.proposed_by = uid, 'created_at', a.created_at) order by a.created_at desc)
                                 from public.couple_like_approvals a join public.profiles t on t.id = a.target_id
                                 where a.couple_id = c.id and a.status = 'pending'), '[]'::jsonb)
    ),
    'invitations', '[]'::jsonb
  );
end;
$$;

-- Reads and actions reused by couples ----------------------------------------------------------------

-- Photos: also the user's couple folder, and profiles served to or matched with the couple.
create or replace function public.can_view_photos_of(p_owner text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  with me as (select private.acting_ids((select auth.uid())) as ids)
  select p_owner = (select auth.uid())::text
      or public.is_my_couple(p_owner)
      or exists (
        select 1 from private.feed_impressions i, me
        where i.viewer_id = any (me.ids) and i.target_id::text = p_owner and i.served_at > now() - interval '24 hours')
      or exists (
        select 1 from public.matches m, me
        where m.status = 'active'
          and ((m.user_a = any (me.ids) and m.user_b::text = p_owner) or (m.user_b = any (me.ids) and m.user_a::text = p_owner)));
$$;

create or replace function private.require_match_member(p_match_id uuid, p_user_id uuid)
returns public.matches
language plpgsql
security definer
set search_path = ''
as $$
declare
  m public.matches;
  ids uuid[] := private.acting_ids(p_user_id);
begin
  select * into m from public.matches where id = p_match_id and (user_a = any (ids) or user_b = any (ids)) for update;
  if m.id is null then
    raise exception 'match_not_found';
  end if;
  return m;
end;
$$;

-- Cards: couple badge and both first names / ages; "en relation ouverte" on the individual
-- cards of an open couple's partners. Approved and partner-approved photos only.
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
        when not p.is_couple and (s ->> 'orientation_visible')::boolean and (private.country_switches(p.country_code)).orientation_enabled
        then s ->> 'orientation' end,
    'prompts', coalesce((select jsonb_agg(jsonb_build_object('question_code', q.question_code, 'answer', q.answer) order by q.position)
                         from public.profile_prompts q where q.user_id = p.id), '[]'::jsonb),
    'photos', coalesce((select jsonb_agg(jsonb_build_object('id', ph.id, 'storage_path', ph.storage_path) order by ph.position)
                        from public.photos ph where ph.user_id = p.id and ph.moderation_status = 'approved' and ph.partner_approved), '[]'::jsonb),
    'is_couple', p.is_couple,
    'couple', case when p.is_couple then (
        select jsonb_build_object('first_names', jsonb_build_array(a.first_name, b.first_name),
                                  'ages', jsonb_build_array(private.age_of(a.birth_date), private.age_of(b.birth_date)),
                                  'kind', c.kind)
        from public.couples c join public.profiles a on a.id = c.partner_a join public.profiles b on b.id = c.partner_b
        where c.id = p.id) end,
    'in_open_couple', exists (select 1 from public.couples c where p.id in (c.partner_a, c.partner_b) and c.kind = 'open' and c.status = 'published')
  )
  from public.profiles p
  cross join lateral (select private.read_sensitive(p.id) as s) sens
  where p.id = p_candidate_id;
$$;

-- Feed: couples as candidates and as viewers -----------------------------------------------------------

create or replace function private.feed_candidates(
  p_viewer_id uuid,
  p_radius_km integer,
  p_reciprocal boolean,
  p_limit integer
)
returns table (candidate_id uuid, distance_m double precision, matched_drinks public.drink[])
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v public.profiles;
  v_ctx jsonb := private.participant_ctx(p_viewer_id);
  v_age integer;
  prefs public.search_preferences := private.search_prefs(p_viewer_id);
  premium boolean := private.is_premium(p_viewer_id);
  origin extensions.geography;
  excluded uuid[];
  default_radius integer := private.config_int('feed.default_radius_km');
  recycle_days integer := private.config_int('feed.pass_recycle_days');
  active_hours integer := private.config_int('activity.badge_window_hours');
  recent_days integer := private.config_int('premium.recently_active_days');
begin
  select * into v from public.profiles where id = p_viewer_id;
  v_age := private.age_of(v.birth_date);
  origin := case when premium and prefs.passport_location is not null then prefs.passport_location else v.location end;
  -- Never yourself, your partner, or your own couple (and, for a couple, its partners).
  excluded := array[p_viewer_id]
    || coalesce((select array[c.id, c.partner_a, c.partner_b] from public.couples c
                 where p_viewer_id in (c.id, c.partner_a, c.partner_b)), '{}');

  return query
  with base as materialized (
    select p.id, p.last_active_at, p.is_couple,
           extensions.st_distance(p.location, origin) as dist
    from public.profiles p
    left join public.search_preferences sp on sp.user_id = p.id
    where not (p.id = any (excluded))
      and p.status = 'active'
      and not p.hidden_by_couple
      and p.location is not null
      and p.verification_status <> 'rejected'
      and case prefs.mode
            when 'radius' then extensions.st_dwithin(p.location, origin, p_radius_km * 1000.0)
            when 'department' then p.department_code = v.department_code
            else p.region_code = v.region_code
          end
      and private.age_of(p.birth_date) between prefs.age_min and prefs.age_max
      and (not p_reciprocal or (
            case coalesce(sp.mode, 'radius')
              when 'radius' then extensions.st_dwithin(p.location, origin, coalesce(sp.radius_km, default_radius) * 1000.0)
              when 'department' then p.department_code = v.department_code
              else p.region_code = v.region_code
            end
            and v_age between coalesce(sp.age_min, 18) and coalesce(sp.age_max, 99)))
      and (not p.incognito or not private.is_premium(p.id) or exists (
            select 1 from public.swipes s where s.actor_id = p.id and s.target_id = p_viewer_id and s.action = 'like'))
      and (not premium or (
            (not prefs.verified_only or p.verification_status = 'verified')
            and (not prefs.recently_active or p.last_active_at > now() - make_interval(days => recent_days))
            and (prefs.education_levels is null or p.education_level = any (prefs.education_levels))
            and (prefs.height_min is null or p.height_cm >= prefs.height_min)
            and (prefs.height_max is null or p.height_cm <= prefs.height_max)
            and (prefs.interests is null or exists (
                  select 1 from public.profile_interests pi where pi.user_id = p.id and pi.interest_code = any (prefs.interests)))))
      and not exists (
            select 1 from public.swipes s
            where s.actor_id = p_viewer_id and s.target_id = p.id
              and (s.action = 'like' or s.created_at > now() - make_interval(days => recycle_days)))
      and not exists (
            select 1 from public.blocks b
            where (b.blocker_id = p_viewer_id and b.blocked_id = p.id)
               or (b.blocker_id = p.id and b.blocked_id = p_viewer_id))
      and not exists (
            select 1 from public.reports r where r.reporter_id = p_viewer_id and r.reported_id = p.id)
      and exists (select 1 from private.profile_sensitive ps where ps.user_id = p.id)
  ),
  scored as (
    select b.id, b.dist, b.last_active_at, ctx.c,
           private.match_ctx(v_ctx, ctx.c) as matched,
           private.is_boosted(b.id) as boosted
    from base b
    cross join lateral (select private.participant_ctx(b.id) as c) ctx
  )
  select sc.id, sc.dist, sc.matched
  from scored sc
  where cardinality(sc.matched) > 0
    and (prefs.drinks is null or sc.matched && prefs.drinks)
    and (not premium or prefs.compositions is null or coalesce(sc.c -> 's' -> 'composition' -> 'kinds', '[]'::jsonb) ?| prefs.compositions)
  order by sc.boosted desc,
           (sc.last_active_at > now() - make_interval(hours => active_hours)) desc,
           sc.dist, sc.id
  limit p_limit;
end;
$$;

-- get_feed: p_as_couple browses the couple's feed (published couples only).
drop function public.get_feed(integer);

create function public.get_feed(p_limit integer default null, p_as_couple boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  viewer uuid := uid;
  v public.profiles;
  prefs public.search_preferences;
  premium boolean;
  page integer := least(coalesce(p_limit, private.config_int('feed.page_size')), 50);
  min_results integer := private.config_int('feed.min_results');
  max_radius integer := private.config_int('feed.max_radius_km');
  radius integer;
  widened boolean := false;
  found_count integer;
  cards jsonb;
begin
  if p_as_couple then
    select c.id into viewer from public.couples c where uid in (c.partner_a, c.partner_b) and c.status = 'published';
    if viewer is null then
      raise exception 'couple_not_published';
    end if;
  end if;
  select * into v from public.profiles where id = viewer;
  if v.status <> 'active' then
    raise exception 'profile_not_active';
  end if;
  if v.location is null then
    raise exception 'location_required';
  end if;
  perform private.require_sensitive_consent(uid);
  update public.profiles set last_active_at = now() where id in (uid, viewer);

  prefs := private.search_prefs(viewer);
  premium := private.is_premium(viewer);
  radius := prefs.radius_km;

  if prefs.mode = 'radius' then
    loop
      select count(*) into found_count from private.feed_candidates(viewer, radius, not widened, min_results);
      exit when found_count >= min_results or radius >= max_radius;
      radius := least(radius * 2, max_radius);
      widened := true;
    end loop;
  end if;

  select coalesce(jsonb_agg(
           private.profile_card(c.candidate_id, c.distance_m, c.matched_drinks)
           || case when premium then jsonb_build_object('popularity', private.popularity_level(c.candidate_id)) else '{}'::jsonb end
           order by c.ord), '[]'::jsonb)
    into cards
  from private.feed_candidates(viewer, radius, not widened, page)
       with ordinality as c (candidate_id, distance_m, matched_drinks, ord);

  insert into private.feed_impressions (viewer_id, target_id, served_at)
  select viewer, (c ->> 'id')::uuid, now() from jsonb_array_elements(cards) c
  on conflict (viewer_id, target_id) do update set served_at = excluded.served_at;

  insert into private.profile_view_events (target_id, viewer_id)
  select (c ->> 'id')::uuid, viewer from jsonb_array_elements(cards) c
  on conflict (target_id, viewer_id, view_day) do nothing;

  return jsonb_build_object(
    'cards', cards,
    'mode', prefs.mode,
    'radius_km', case when prefs.mode = 'radius' then radius end,
    'widened', widened,
    'passport', case when premium and prefs.passport_location is not null then prefs.passport_label end,
    'as_couple', p_as_couple
  );
end;
$$;

-- Matches: a partner sees their own matches and their couple's, never the other partner's.
create or replace function public.get_my_matches()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  ids uuid[] := private.acting_ids(uid);
begin
  return coalesce((
    select jsonb_agg(item order by sort_at desc)
    from (
      select coalesce(c.last_message_at, m.created_at) as sort_at,
        jsonb_build_object(
          'match_id', m.id,
          'conversation_id', c.id,
          'created_at', m.created_at,
          'as_couple', mine <> uid,
          'with_couple', o.is_couple or mine <> uid,
          'matched_drinks', to_jsonb(m.matched_drinks),
          'first_message_deadline', case when m.first_message_at is null then m.first_message_deadline end,
          'extensions_left', greatest(private.config_int('match.max_extensions') - m.extensions_used, 0),
          'other', jsonb_build_object(
            'id', o.id,
            'first_name', o.first_name,
            'age', private.age_of(o.birth_date),
            'verified', o.verification_status = 'verified',
            'is_couple', o.is_couple,
            'drinks', coalesce((select jsonb_agg(d.drink order by d.drink) from public.profile_drinks d where d.user_id = o.id), '[]'::jsonb),
            'photo_path', (select ph.storage_path from public.photos ph
                           where ph.user_id = o.id and ph.moderation_status <> 'rejected' and ph.partner_approved order by ph.position limit 1)
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
      cross join lateral (select case when m.user_a = any (ids) then m.user_a else m.user_b end as mine) side
      join public.conversations c on c.match_id = m.id
      join public.conversation_members me on me.conversation_id = c.id and me.user_id = uid
      join public.profiles o on o.id = case when m.user_a = side.mine then m.user_b else m.user_a end
      where (m.user_a = any (ids) or m.user_b = any (ids)) and private.match_is_open(m)
    ) rows
  ), '[]'::jsonb);
end;
$$;

create or replace function public.get_match_profile(p_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  ids uuid[] := private.acting_ids(uid);
  m public.matches;
  mine uuid;
  other uuid;
begin
  select * into m from public.matches where id = p_match_id and (user_a = any (ids) or user_b = any (ids));
  if m.id is null or m.status <> 'active' then
    raise exception 'match_not_found';
  end if;
  mine := case when m.user_a = any (ids) then m.user_a else m.user_b end;
  other := case when m.user_a = mine then m.user_b else m.user_a end;
  return private.profile_card(other,
    (select extensions.st_distance(a.location, b.location) from public.profiles a, public.profiles b where a.id = mine and b.id = other),
    m.matched_drinks);
end;
$$;

do $$
declare
  f text;
begin
  foreach f in array array[
    'public.create_couple_invitation()',
    'public.request_couple_by_username(text)',
    'public.preview_couple_invitation(text)',
    'public.accept_couple_invitation(text)',
    'public.respond_couple_request(uuid, boolean)',
    'public.set_couple_profile(text, public.drink[], public.relationship_structure, jsonb, text[], public.gender[], text)',
    'public.set_my_couple_visibility(boolean)',
    'public.add_couple_photo(text)',
    'public.approve_couple_photo(uuid, boolean)',
    'public.propose_couple_like(uuid, public.like_target, text)',
    'public.decide_couple_like(uuid, boolean)',
    'public.pass_profile(uuid, boolean)',
    'public.leave_couple()',
    'public.get_my_couple()',
    'public.get_feed(integer, boolean)'
  ]
  loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end;
$$;

-- A partner's account deletion (or a closed account) erases the couple profile too.
create function private.on_couple_deleted()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from auth.users where id = old.id;
  update public.profiles set hidden_by_couple = false where id in (old.partner_a, old.partner_b);
  return old;
end;
$$;

create trigger couples_after_delete
  after delete on public.couples
  for each row execute function private.on_couple_deleted();

-- Publication follows asynchronous checks (photo moderation, partners' selfies).
create function private.refresh_all_couples()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  c uuid;
  n integer := 0;
begin
  for c in select id from public.couples loop
    perform private.refresh_couple(c);
    n := n + 1;
  end loop;
  return n;
end;
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
    'group_invitations', private.expire_group_invitations(),
    'couples', private.refresh_all_couples()
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
