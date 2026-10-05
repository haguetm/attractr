-- Foundations: extensions, private schema, default privileges.
--
-- Conventions used by every migration:
--   * Tables exposed to the app live in `public`, always with RLS enabled.
--   * Internal tables and helpers live in `private`, which no API role can reach.
--   * Functions use `set search_path = ''` and fully qualified names.
--   * Business-rule violations raise exceptions whose message is a stable snake_case code
--     (e.g. 'drink_change_cooldown') that the app maps to an i18n string.

create extension if not exists postgis with schema extensions;
create extension if not exists pgcrypto with schema extensions;
create extension if not exists supabase_vault with schema vault;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

-- Functions are executable by PUBLIC by default; never in the private schema.
alter default privileges in schema private revoke execute on functions from public;

-- The app is login-only: the anon role gets nothing in public by default.
alter default privileges for role postgres in schema public revoke all on tables from anon;
alter default privileges for role postgres in schema public revoke all on sequences from anon;
alter default privileges for role postgres in schema public revoke execute on functions from anon, public;
