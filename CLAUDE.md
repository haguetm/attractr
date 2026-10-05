# Attractr

Adult-only (18+) dating app where each profile shows a drink that signals intent. Full product spec: [docs/SPEC.md](docs/SPEC.md) — read it before any change. Architecture (once validated): `docs/ARCHITECTURE.md`.

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

## Commands
_To be filled in once the repo is scaffolded (Phase 1)._
