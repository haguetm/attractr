-- Calls the send-push Edge Function every minute (Supabase stack only).
-- Needs two Vault secrets, set once per project (never in the repository):
--   select vault.create_secret('https://<ref>.supabase.co', 'project_url');
--   select vault.create_secret('<service role key>', 'service_role_key');
-- Without them the job runs but does nothing.

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron')
     and exists (select 1 from pg_available_extensions where name = 'pg_net') then
    create extension if not exists pg_cron;
    create extension if not exists pg_net;
    perform cron.schedule(
      'attractr-send-push',
      '* * * * *',
      $job$
        select net.http_post(
          url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/send-push',
          headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key')),
          body := '{}'::jsonb)
        where exists (select 1 from vault.decrypted_secrets where name = 'project_url')
          and exists (select 1 from vault.decrypted_secrets where name = 'service_role_key')
          and exists (select 1 from private.notification_outbox where sent_at is null and attempts < 5)
      $job$
    );
  end if;
end;
$$;
