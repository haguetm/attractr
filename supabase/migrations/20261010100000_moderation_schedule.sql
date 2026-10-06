-- Safety net: photos the app did not send to moderation are processed every 5 minutes
-- by moderate-photo (service mode). Supabase stack only, same Vault secrets as send-push.

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron')
     and exists (select 1 from pg_available_extensions where name = 'pg_net') then
    perform cron.schedule(
      'attractr-moderate-photos',
      '*/5 * * * *',
      $job$
        select net.http_post(
          url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/moderate-photo',
          headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key')),
          body := '{}'::jsonb)
        where exists (select 1 from vault.decrypted_secrets where name = 'project_url')
          and exists (select 1 from vault.decrypted_secrets where name = 'service_role_key')
          and exists (select 1 from public.photos where moderation_status = 'pending')
      $job$
    );
  end if;
end;
$$;
