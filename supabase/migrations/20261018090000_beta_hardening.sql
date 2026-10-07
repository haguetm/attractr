-- Hardening before the first hosted beta (security review of phases 1-11).
--   1. Birth date: can no longer be erased (and changed) by sending null.
--   2. Likes: concurrent likes are serialized (two mutual likes at the same time create
--      the match; parallel calls cannot overrun the free quota).
--   3. Photos in Storage: other people read a photo only if it is approved and they may
--      see that profile (feed, match, or group main photo). Before, a served profile's
--      whole folder was readable, pending and rejected photos included, and opening a
--      group made every member's full profile reachable.
--   4. Selfie results with a missing age, confidence or face reference go to human review
--      instead of being verified.
--   5. "Bloquer mes contacts" no longer reveals whether a phone number uses the app.
--   6. RevenueCat: events from a non-allowed environment (sandbox, test store) never grant
--      anything in production.
--   7. Couple erasure also erases the couple's photos in Storage.
--   8. Written answers are only written through set_my_prompts (its checks apply).
--   9. Scheduled calls to Edge Functions use a dedicated cron secret instead of the
--      service role key stored in Vault.

insert into public.app_config (key, value, description, is_public) values
  ('contacts.block_cooldown_hours', '24', 'Minimum hours between two "bloquer mes contacts" runs (anti-enumeration).', false),
  ('revenuecat.allowed_environments', '["PRODUCTION"]',
   'RevenueCat event environments that change entitlements. Beta only: add "SANDBOX" (test store, sandbox purchases).', false);

-- 1. Birth date ----------------------------------------------------------------------------

create or replace function public.set_my_birth_date(p_birth_date date)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  current_birth date;
begin
  if p_birth_date is null then
    raise exception 'invalid_request';
  end if;
  select birth_date into current_birth from public.profiles where id = uid;
  if current_birth is not null and current_birth <> p_birth_date then
    raise exception 'birth_date_locked';
  end if;
  update public.profiles set birth_date = p_birth_date where id = uid;
end;
$$;

-- 2. Likes ---------------------------------------------------------------------------------

create or replace function private.like_as(p_actor uuid, p_target_id uuid, p_target_kind public.like_target, p_target_ref text)
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
  -- One like at a time per actor (quota), and per pair: when both like each other at the
  -- same moment, the second sees the first like and creates the match.
  select * into actor from public.profiles where id = p_actor for update;
  perform pg_advisory_xact_lock(hashtextextended(least(p_actor, p_target_id)::text || greatest(p_actor, p_target_id)::text, 0));
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

-- 3. Photos in Storage ---------------------------------------------------------------------

-- A profile's first approved photo (group member cards).
create or replace function private.main_photo(p_user_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select storage_path from public.photos
  where user_id = p_user_id and moderation_status = 'approved' and partner_approved
  order by position limit 1;
$$;

-- Group co-members see each other's main photo, and members see a pending invitee's
-- (spec §8). Invitees see first names only.
create function private.shares_group(p_viewer uuid, p_target uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.group_members me
    join public.groups g on g.id = me.group_id and g.status = 'active'
    where me.user_id = p_viewer
      and (exists (select 1 from public.group_members other where other.group_id = g.id and other.user_id = p_target)
           or exists (select 1 from public.group_invitations i
                      where i.group_id = g.id and i.invitee_id = p_target and i.status = 'pending'))
  );
$$;

-- Storage read access to someone else's photo (the owner and the couple partners have
-- their own policies). In public so the storage policy, evaluated as the caller, can use
-- it; it only answers about the caller's own access.
create function public.can_view_photo(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  with me as (select (select auth.uid()) as uid, private.acting_ids((select auth.uid())) as ids),
  ph as (
    select user_id from public.photos
    where storage_path = p_name and moderation_status = 'approved' and partner_approved
  )
  select exists (
    select 1 from ph, me
    where exists (select 1 from private.feed_impressions i
                  where i.viewer_id = any (me.ids) and i.target_id = ph.user_id
                    and i.served_at > now() - interval '24 hours')
       or exists (select 1 from public.matches m
                  where m.status = 'active'
                    and ((m.user_a = any (me.ids) and m.user_b = ph.user_id) or (m.user_b = any (me.ids) and m.user_a = ph.user_id)))
       or (p_name = private.main_photo(ph.user_id) and private.shares_group(me.uid, ph.user_id))
  );
$$;

revoke execute on function public.can_view_photo(text) from public, anon;
grant execute on function public.can_view_photo(text) to authenticated;

drop policy photos_select_served on storage.objects;
drop function public.can_view_photos_of(text);

create policy photos_select_couple on storage.objects for select to authenticated
  using (bucket_id = 'photos' and public.is_my_couple((storage.foldername(name))[1]));
create policy photos_select_shared on storage.objects for select to authenticated
  using (bucket_id = 'photos' and public.can_view_photo(name));

-- Opening a group no longer counts as seeing the members' profiles (no feed impression:
-- no full photo access, no like). Main photos are reachable through can_view_photo.
create or replace function public.get_group(p_group_id uuid)
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
  return jsonb_build_object(
    'id', g.id, 'kind', g.kind, 'name', g.name, 'approval_mode', g.approval_mode,
    'is_admin', g.admin_id = uid,
    'max_members', private.group_max(g.kind),
    'conversation_id', (select id from public.conversations where group_id = g.id),
    'members', (select jsonb_agg(jsonb_build_object('id', p.id, 'first_name', p.first_name, 'photo_path', private.main_photo(p.id),
                                                    'is_admin', p.id = g.admin_id, 'me', p.id = uid) order by gm.joined_at, gm.seq)
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

-- Match list: the photo shown is an approved one (pending photos are not readable).
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
            'photo_path', private.main_photo(o.id)
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

-- 4. Selfie results --------------------------------------------------------------------------

create or replace function private.apply_selfie_result(
  p_submission_id bigint,
  p_live boolean,
  p_estimated_age integer,
  p_confidence numeric,
  p_face_id text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  s private.selfie_submissions;
  p public.profiles;
  declared integer;
  v_outcome text;
  v_reason text;
begin
  select * into s from private.selfie_submissions where id = p_submission_id for update;
  if s.id is null or s.processed_at is not null then
    raise exception 'selfie_not_found';
  end if;
  select * into p from public.profiles where id = s.user_id for update;
  declared := private.age_of(p.birth_date);

  if not coalesce(p_live, false) then
    v_outcome := 'retake';
  elsif p_estimated_age is null or p_confidence is null or p_face_id is null or declared is null then
    -- Never verify on an incomplete answer.
    v_outcome := 'review';
    v_reason := 'incomplete_result';
  elsif p_estimated_age < private.config_int('verification.adult_age') then
    v_outcome := 'review';
    v_reason := 'possible_minor';
  elsif exists (select 1 from private.face_templates f where f.face_id = p_face_id and f.user_id <> s.user_id)
     or exists (select 1 from private.blocked_identities b where b.face_id = p_face_id and b.expires_at > now()) then
    v_outcome := 'review';
    v_reason := 'duplicate_face';
  elsif p_confidence < (private.config('verification.min_confidence'))::numeric
     or abs(declared - p_estimated_age) > private.config_int('verification.age_gap_review_years') then
    v_outcome := 'review';
    v_reason := 'age_mismatch';
  else
    v_outcome := 'verified';
  end if;

  update private.selfie_submissions
     set processed_at = now(), outcome = v_outcome,
         status = case v_outcome when 'verified' then 'verified' when 'retake' then 'rejected' else 'pending' end::public.verification_status,
         result = jsonb_build_object('live', p_live, 'estimated_age', p_estimated_age, 'confidence', p_confidence,
                                     'face_id', p_face_id, 'reason', v_reason)
   where id = s.id;

  if v_outcome = 'verified' then
    update public.profiles set verification_status = 'verified', verified_at = now() where id = p.id;
    insert into private.face_templates (user_id, face_id) values (p.id, p_face_id)
    on conflict (user_id) do update set face_id = excluded.face_id;
    insert into private.storage_cleanup (bucket, path) values ('selfies', s.storage_path);
  elsif v_outcome = 'retake' then
    update public.profiles set verification_status = 'rejected' where id = p.id;
    insert into private.storage_cleanup (bucket, path) values ('selfies', s.storage_path);
  else
    update public.profiles set verification_status = 'pending' where id = p.id;
    if v_reason = 'possible_minor' and p.status in ('active', 'paused', 'onboarding') then
      -- Hidden from everyone until a human decides (spec §12).
      update public.profiles set status = 'suspended' where id = p.id;
    end if;
    perform private.enqueue('selfie_review', p.id, s.id::text, v_reason,
                            case when v_reason = 'possible_minor' then 1 else 2 end::smallint);
  end if;
  return v_outcome;
end;
$$;

-- 5. Contact blocks ----------------------------------------------------------------------------
-- get_my_blocks used to say whether at least one contact was blocked: sending a single
-- digest, then reading that answer, told whether a phone number had an account. It now
-- only says whether the user asked for contact blocking, and runs are rate-limited.

create table private.contact_block_requests (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  requested_at timestamptz not null default now()
);

create or replace function public.block_contacts(p_digests text[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := private.require_user();
  last_run timestamptz;
  target uuid;
begin
  if coalesce(cardinality(p_digests), 0) > 5000 then
    raise exception 'too_many_contacts';
  end if;
  select requested_at into last_run from private.contact_block_requests where user_id = uid for update;
  if last_run > now() - make_interval(hours => private.config_int('contacts.block_cooldown_hours')) then
    raise exception 'contacts_block_cooldown';
  end if;
  insert into private.contact_block_requests (user_id) values (uid)
  on conflict (user_id) do update set requested_at = now();
  for target in
    select d.user_id from private.phone_digests d
    where d.digest = any (p_digests) and d.user_id <> uid
      and exists (select 1 from public.profiles p where p.id = d.user_id)
  loop
    perform private.block(uid, target, 'contacts');
  end loop;
end;
$$;

-- Lifts the contact blocks. The cooldown stays: unblocking does not allow a new run.
create or replace function public.unblock_contacts()
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.blocks where blocker_id = (select auth.uid()) and source = 'contacts';
$$;

create or replace function public.get_my_blocks()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'profiles', coalesce((
      select jsonb_agg(jsonb_build_object('id', p.id, 'first_name', p.first_name, 'blocked_at', b.created_at) order by b.created_at desc)
      from public.blocks b join public.profiles p on p.id = b.blocked_id
      where b.blocker_id = (select auth.uid()) and b.source <> 'contacts'), '[]'::jsonb),
    -- Whether the user ran "bloquer mes contacts", never whether anyone matched.
    'contacts_blocked', exists (select 1 from private.contact_block_requests r where r.user_id = (select auth.uid()))
  );
$$;

-- 6. RevenueCat environments -------------------------------------------------------------------

create or replace function private.apply_revenuecat_event(p_event jsonb)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  ev_id text := p_event ->> 'id';
  ev_type text := p_event ->> 'type';
  ev_env text := coalesce(p_event ->> 'environment', 'PRODUCTION');
  raw_user text := p_event ->> 'app_user_id';
  uid uuid;
  product text := coalesce(p_event ->> 'product_id', '');
  expires timestamptz := case when p_event ? 'expiration_at_ms' and p_event ->> 'expiration_at_ms' is not null
                              then to_timestamp((p_event ->> 'expiration_at_ms')::bigint / 1000.0) end;
  purchased timestamptz := coalesce(case when p_event ->> 'purchased_at_ms' is not null
                                         then to_timestamp((p_event ->> 'purchased_at_ms')::bigint / 1000.0) end, now());
  result text := 'recorded';
  from_id text;
begin
  if ev_id is null or ev_type is null then
    raise exception 'invalid_event';
  end if;
  if exists (select 1 from private.revenuecat_events where id = ev_id) then
    return 'duplicate';
  end if;
  insert into private.revenuecat_events (id, type, app_user_id, payload) values (ev_id, ev_type, raw_user, p_event);

  -- Sandbox and test-store purchases cost nothing: they only count where allowed (beta).
  if not (private.config('revenuecat.allowed_environments') ? ev_env) then
    update private.revenuecat_events set outcome = 'ignored_environment' where id = ev_id;
    return 'ignored_environment';
  end if;

  if raw_user ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    uid := raw_user::uuid;
  end if;
  if ev_type <> 'TRANSFER' and (uid is null or not exists (select 1 from public.profiles where id = uid)) then
    update private.revenuecat_events set outcome = 'unknown_user' where id = ev_id;
    return 'unknown_user';
  end if;

  if ev_type = 'NON_RENEWING_PURCHASE' and product like 'boost%' then
    insert into private.boost_credits (user_id, source) values (uid, 'purchase');
    result := 'boost_credited';
  elsif ev_type in ('INITIAL_PURCHASE', 'RENEWAL', 'PRODUCT_CHANGE', 'UNCANCELLATION', 'SUBSCRIPTION_EXTENDED', 'TEMPORARY_ENTITLEMENT_GRANT') then
    insert into private.entitlements (user_id, entitlement, source, starts_at, expires_at, product_id)
    values (uid, 'premium', 'revenuecat', purchased, expires, product)
    on conflict (user_id, entitlement) where source = 'revenuecat'
    do update set expires_at = excluded.expires_at, product_id = excluded.product_id, updated_at = now(),
                  starts_at = least(private.entitlements.starts_at, excluded.starts_at);
    if ev_type = 'INITIAL_PURCHASE' then
      -- The referral discount (if any) was used on this first payment.
      update private.referral_rewards set status = 'applied', applied_at = now()
       where user_id = uid and kind = 'discount' and status = 'earned';
    end if;
    result := 'premium_active';
  elsif ev_type = 'EXPIRATION' then
    update private.entitlements set expires_at = least(coalesce(expires_at, now()), now()), updated_at = now()
     where user_id = uid and source = 'revenuecat';
    -- Free months not yet applied stop with the referrer's subscription (spec §9).
    update private.referral_rewards set status = 'void'
     where user_id = uid and kind = 'free_month' and status = 'earned';
    result := 'premium_expired';
  elsif ev_type = 'TRANSFER' then
    for from_id in select jsonb_array_elements_text(coalesce(p_event -> 'transferred_from', '[]')) loop
      if from_id ~* '^[0-9a-f-]{36}$' and exists (select 1 from jsonb_array_elements_text(coalesce(p_event -> 'transferred_to', '[]')) t
                                                  where t ~* '^[0-9a-f-]{36}$') then
        update private.entitlements
           set user_id = (select t::uuid from jsonb_array_elements_text(p_event -> 'transferred_to') t
                          where t ~* '^[0-9a-f-]{36}$' limit 1), updated_at = now()
         where user_id = from_id::uuid and source = 'revenuecat';
      end if;
    end loop;
    result := 'transferred';
  end if;

  update private.revenuecat_events set outcome = result where id = ev_id;
  return result;
end;
$$;

-- 7. Couple erasure ------------------------------------------------------------------------------
-- When a partner deletes their account (or is closed), the couple goes too: its Storage
-- folder must not outlive it. leave_couple queues the files itself, because there the
-- photos may already be gone when this trigger runs.

create or replace function private.on_couple_deleted()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into private.storage_cleanup (bucket, path)
  select 'photos', storage_path from public.photos where user_id = old.id;
  delete from auth.users where id = old.id;
  update public.profiles set hidden_by_couple = false where id in (old.partner_a, old.partner_b);
  return old;
end;
$$;

-- 8. Written answers ---------------------------------------------------------------------------

drop policy profile_prompts_insert_own on public.profile_prompts;
drop policy profile_prompts_update_own on public.profile_prompts;
drop policy profile_prompts_delete_own on public.profile_prompts;
revoke insert, update, delete, truncate on public.profile_prompts from authenticated;

-- 9. Scheduled calls -----------------------------------------------------------------------------
-- The jobs read two Vault secrets, set once per project (never in the repository):
--   select vault.create_secret('https://<ref>.supabase.co', 'project_url');
--   select vault.create_secret('<same value as the CRON_SECRET function secret>', 'cron_secret');
-- Without them the jobs run but call nothing. cron.schedule replaces a job of the same name.

do $$
declare
  job record;
begin
  if not (exists (select 1 from pg_extension where extname = 'pg_cron')
          and exists (select 1 from pg_extension where extname = 'pg_net')) then
    return;
  end if;
  for job in
    select * from (values
      ('attractr-send-push', '* * * * *', 'send-push',
       'exists (select 1 from private.notification_outbox where sent_at is null and attempts < 5)'),
      ('attractr-process-deletions', '*/5 * * * *', 'process-deletions', 'true'),
      ('attractr-moderate-photos', '*/5 * * * *', 'moderate-photo',
       'exists (select 1 from public.photos where moderation_status = ''pending'')')
    ) as j (name, schedule, fn, pending)
  loop
    perform cron.schedule(job.name, job.schedule, format($job$
      select net.http_post(
        url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/%s',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'X-Cron-Secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')),
        body := '{}'::jsonb)
      where exists (select 1 from vault.decrypted_secrets where name = 'project_url')
        and exists (select 1 from vault.decrypted_secrets where name = 'cron_secret')
        and %s
    $job$, job.fn, job.pending));
  end loop;
end;
$$;
