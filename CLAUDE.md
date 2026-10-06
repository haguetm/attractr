# Attractr

Adult-only (18+) dating app where each profile shows a drink that signals intent. Full product spec: [docs/SPEC.md](docs/SPEC.md) — read it before any change. Validated decisions that refine it (take precedence): [docs/DECISIONS.md](docs/DECISIONS.md). Architecture: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Stack
- Mobile: Expo (React Native) + TypeScript
- Backend: Supabase (EU region): Auth, Postgres + PostGIS, Realtime, Storage, RLS on every table, Edge Functions (Deno) for all third-party calls
- Payments: RevenueCat · Push: Expo Notifications · Analytics: PostHog (EU) + Sentry
- Environments: dev and prod

## Working rules
- Build phase by phase (spec §14); stop for approval at the end of each phase with: summary, how to test, passing tests, decisions taken alone.
- Ambiguous rule → ask a short question, don't invent.
- Any value marked "provisoire" lives in `app_config`, never hard-coded.
- Code and comments in English; UI strings in French via i18n files.
- Every external provider (selfie/age, photo moderation, AI analysis, geocoding) = interface + mock; real impl behind a config flag.
- Automated tests for every business rule (compatibility, quotas, referral, groups) and for RLS.
- No secrets in the repo (`.env.example` only). No sensitive data in PostHog, Sentry, logs or push payloads.
- Small commits.

## Layout
- `apps/mobile` — Expo SDK 57 app (Expo Router in `src/app`, UI strings in `src/i18n/fr.json`). See its AGENTS.md: check versioned Expo docs, install with `npx expo install`
- `packages/shared` — domain types + UI-side rule mirrors (e.g. `validateIntent`), Vitest
- `supabase/migrations` — schema, RLS, RPCs (source of truth for business rules)
- `supabase/tests` — pgTAP tests (rules + RLS)
- `supabase/seed` — generator of `supabase/seeds/20_profiles.sql` (100 fictional profiles)
- `supabase/seeds/00_test_helpers.sql` — `tests.*` helpers, local only
- `supabase/functions` — Edge Functions (Deno)

## Commands
Node 22 + npm workspaces. The local stack needs Docker (not available on the work PC: code is written there, run on the personal PC).
- `npm install` — install workspaces
- `npm test` / `npm run typecheck` — Vitest + tsc on all workspaces
- `npm run seed:generate` — regenerate `supabase/seeds/20_profiles.sql` (commit the result)
- `npm run db:start` — start local Supabase (Docker)
- `npm run db:reset` — apply migrations + seeds
- `npm run db:test` — run pgTAP tests (after `db:reset`)
- `npm run functions:serve` — run Edge Functions locally (copy `supabase/functions/.env.example` to `.env` first)
- `npm run functions:deploy -- --project-ref <ref>` — deploy to a hosted project (never deploys `dev-*` functions)
- `npm run functions:test` / `npm run functions:check` — Deno tests / type-check (Deno via npx, nothing to install)
- `npm run mobile` — start Expo (needs `apps/mobile/.env`, see `.env.example` there)

## Dev tools
- "Tester en tant que": Réglages > Outils de développement in the app. Needs local Supabase, `APP_ENV=development` (functions) and `EXPO_PUBLIC_APP_ENV=development` (app); the local seed enables `dev.impersonation_enabled`.

## SQL conventions
- `set search_path = ''` and fully qualified names in every function.
- RPCs in `public` are `security definer`, revoked from `public, anon`, granted to `authenticated`.
- Rule violations: `raise exception '<snake_case_code>'` — the app maps codes to i18n strings.
- When a SQL rule changes, update its TS mirror in `packages/shared` and both test suites.
