-- Bans: phone, email and Google / Apple accounts refused at signup (migration 20261020090000).
begin;
select plan(19);

create function pg_temp.u(n int) returns uuid language sql as $$ select ('fc000000-0000-4000-8000-00000000000' || n)::uuid $$;
create function pg_temp.signup(p_id uuid, p_email text, p_phone text default null) returns void language sql as $$
  insert into auth.users (instance_id, id, aud, role, email, phone, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', p_id, 'authenticated', 'authenticated', p_email, p_phone, '{}', '{}', now(), now())
$$;
create function pg_temp.google(p_user uuid, p_sub text) returns void language sql as $$
  insert into auth.identities (provider_id, user_id, identity_data, provider, created_at, updated_at)
  values (p_sub, p_user, jsonb_build_object('sub', p_sub), 'google', now(), now())
$$;

-- Gmail aliases fold to one address
select is(private.normalize_email(' Lea.Martin+dating@GoogleMail.com '), 'leamartin@gmail.com', 'Gmail dots, tags and domains are folded');
select is(private.normalize_email('lea.martin+x@example.fr'), 'lea.martin@example.fr', 'other domains keep their dots, lose the tag');

-- B: onboarded with phone, email and a Google account, matched with A
select tests.create_onboarded_user('33639987001', pg_temp.u(1), 'woman', '{man}');
select tests.create_onboarded_user('33639987002', pg_temp.u(2), 'man', '{woman}');
update auth.users set email = 'hugo.martin@gmail.com' where id = pg_temp.u(2);
select pg_temp.google(pg_temp.u(2), 'google-sub-hugo');
insert into private.face_templates (user_id, face_id) values (pg_temp.u(2), 'face-of-hugo');
insert into public.matches (id, user_a, user_b, matched_drinks, first_message_deadline)
values ('fc100000-0000-4000-8000-000000000001', least(pg_temp.u(1), pg_temp.u(2)), greatest(pg_temp.u(1), pg_temp.u(2)), '{wine}', now() + interval '1 day');

select throws_ok($$ select private.mod_ban_account('moderateur:test', pg_temp.u(2), 'x') $$, 'P0001', 'invalid_request', 'a ban needs a reason');
select lives_ok($$ select private.mod_ban_account('moderateur:test', pg_temp.u(2), 'arnaque confirmée, signalement #12') $$, 'ban');
select is((select status::text from public.profiles where id = pg_temp.u(2)), 'closed', 'the account is closed');
select is((select status::text from public.matches where id = 'fc100000-0000-4000-8000-000000000001'), 'unmatched', 'its matches end');
select ok(exists (select 1 from private.pending_deletions where user_id = pg_temp.u(2) and reason = 'moderation'), 'its data is queued for erasure');
select ok(exists (select 1 from private.access_log where subject_user_id = pg_temp.u(2) and reason like 'banned:%'), 'the ban is logged');
select ok(not exists (select 1 from private.blocked_identities b where concat(b.phone_hash, b.email_hash, b.identity_hash) ~* '(hugo|33639987002|google-sub)'),
  'phone, email and Google account are only kept as HMACs');
delete from auth.users where id = pg_temp.u(2);  -- process-deletions

-- Coming back
select throws_ok($$ select pg_temp.signup(pg_temp.u(3), 'Hugo.Martin+new@googlemail.com') $$, 'P0001', 'identity_blocked',
  'the same email (even as a Gmail alias) is refused');
select throws_ok($$ select pg_temp.signup(pg_temp.u(3), 'autre@example.fr', '33639987002') $$, 'P0001', 'identity_blocked',
  'the same phone is refused');
select lives_ok($$ select pg_temp.signup(pg_temp.u(3), 'autre@example.fr') $$, 'a new email is accepted...');
select throws_ok($$ select pg_temp.google(pg_temp.u(3), 'google-sub-hugo') $$, 'P0001', 'identity_blocked',
  '... but not the banned Google account');
select throws_ok($$ update auth.users set phone = '33639987002' where id = pg_temp.u(3) $$, 'P0001', 'identity_blocked',
  'nor verifying the banned phone later');
update public.app_config set value = 'false' where key = 'auth.phone_verification_required';
select tests.authenticate_as(pg_temp.u(3));
select throws_ok($$ select public.set_my_phone('+33639987002') $$, 'P0001', 'identity_blocked', 'nor declaring it (beta)');
reset role;

-- The face sends a new selfie to review
insert into private.selfie_submissions (user_id, storage_path) values (pg_temp.u(3), pg_temp.u(3) || '/s.jpg');
update public.profiles set birth_date = '1990-01-01' where id = pg_temp.u(3);
select is(private.apply_selfie_result((select id from private.selfie_submissions where user_id = pg_temp.u(3)), true, 36, 0.95, 'face-of-hugo'),
  'review', 'the banned face goes to review');
select is((select reason from private.moderation_queue where subject_user_id = pg_temp.u(3)), 'returning_account', 'as a returning account');

-- An account banned before finishing its onboarding
select pg_temp.signup(pg_temp.u(5), 'spam@example.fr');
select lives_ok($$ select private.mod_ban_account('moderateur:test', pg_temp.u(5), 'spam dès l''inscription') $$,
  'an account can be banned before finishing its onboarding');

-- Bans end after compliance.ban_retention_days
update private.blocked_identities set expires_at = now() - interval '1 second' where reason = 'banned';
select lives_ok($$ select pg_temp.signup(pg_temp.u(4), 'hugo.martin@gmail.com') $$, 'an expired ban no longer refuses');

select * from finish();
rollback;
