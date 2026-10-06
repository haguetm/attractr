-- Development grants for testing Premium and boosts without a store purchase.
-- Refused unless dev.impersonation_enabled (local seed only), and service role only.
create function public.service_dev_grant(p_user_id uuid, p_kind text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if private.config('dev.impersonation_enabled') <> 'true'::jsonb then
    raise exception 'dev_tools_disabled';
  end if;
  if p_kind = 'premium' then
    insert into private.entitlements (user_id, entitlement, source, expires_at)
    values (p_user_id, 'premium', 'test', now() + interval '30 days');
  elsif p_kind = 'boost' then
    insert into private.boost_credits (user_id, source) values (p_user_id, 'test');
  else
    raise exception 'invalid_request';
  end if;
end;
$$;

revoke execute on function public.service_dev_grant(uuid, text) from public, anon, authenticated;
grant execute on function public.service_dev_grant(uuid, text) to service_role;

-- Referral free months are applied store-side by apply-rewards every hour (Supabase only).
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron')
     and exists (select 1 from pg_available_extensions where name = 'pg_net') then
    perform cron.schedule(
      'attractr-apply-rewards',
      '17 * * * *',
      $job$
        select net.http_post(
          url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/apply-rewards',
          headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key')),
          body := '{}'::jsonb)
        where exists (select 1 from vault.decrypted_secrets where name = 'project_url')
          and exists (select 1 from vault.decrypted_secrets where name = 'service_role_key')
      $job$
    );
  end if;
end;
$$;
