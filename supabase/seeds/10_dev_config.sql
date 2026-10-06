-- Local development settings (seeds never run on hosted projects).
-- "Tester en tant que" also requires APP_ENV=development and the local stack.
update public.app_config set value = 'true', updated_at = now() where key = 'dev.impersonation_enabled';

-- Fake store offer codes so referral free months can be assigned locally (option B).
insert into private.offer_code_pool (code, store)
select 'DEV-' || s || '-' || lpad(n::text, 4, '0'), s from unnest(array['APP_STORE', 'PLAY_STORE']) s, generate_series(1, 20) n
on conflict (code) do nothing;
