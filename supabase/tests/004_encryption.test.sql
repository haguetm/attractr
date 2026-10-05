begin;
select plan(5);

select tests.create_onboarded_user('33639982101', 'a2000000-0000-4000-8000-000000000001',
  'woman', '{man,non_binary}', '{coffee}', 'polyamorous');

select isnt_empty(
  $$ select 1 from vault.secrets where name = 'profile_sensitive_key' $$,
  'encryption key exists in Vault');

select ok(
  (select position('polyamorous' in encode(payload, 'escape')) = 0
      and position('non_binary' in encode(payload, 'escape')) = 0
   from private.profile_sensitive where user_id = 'a2000000-0000-4000-8000-000000000001'),
  'sensitive values are not stored in clear');

select is(
  private.read_sensitive('a2000000-0000-4000-8000-000000000001') ->> 'structure', 'polyamorous',
  'sensitive payload decrypts with the Vault key');

select throws_ok(
  $$ select extensions.pgp_sym_decrypt(payload, 'wrong-key') from private.profile_sensitive
     where user_id = 'a2000000-0000-4000-8000-000000000001' $$,
  '39000', null, 'payload cannot be decrypted without the key');

-- Back-office reads are logged (spec §12, access_log).
select private.admin_read_sensitive('moderator:test', 'a2000000-0000-4000-8000-000000000001', 'report #42 review');
select is(
  (select count(*)::int from private.access_log
   where subject_user_id = 'a2000000-0000-4000-8000-000000000001' and resource = 'profile_sensitive'),
  1, 'admin read of sensitive fields is written to access_log');

select * from finish();
rollback;
