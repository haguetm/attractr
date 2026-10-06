-- Local development settings (seeds never run on hosted projects).
-- "Tester en tant que" also requires APP_ENV=development and the local stack.
update public.app_config set value = 'true', updated_at = now() where key = 'dev.impersonation_enabled';
