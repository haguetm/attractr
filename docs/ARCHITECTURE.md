# Architecture

Validated 2026-10-05. Product rules: [SPEC.md](SPEC.md) + [DECISIONS.md](DECISIONS.md).

## Repository (npm workspaces monorepo)

npm rather than pnpm: Expo/Metro works without extra linker settings, and nothing extra to install on either PC.

```
apps/mobile/            Expo + Expo Router + TypeScript (dev build, required by RevenueCat)
  app/                  routes
  src/features/         onboarding, discovery, matches, chat, friends, outings, groups, couple, premium, ai
  src/lib/              supabase client, i18n, analytics wrapper, sentry, revenuecat
  src/i18n/fr.json      all UI strings
packages/shared/        domain types, generated DB types, zod schemas, pure UI-side rules
supabase/
  migrations/           versioned SQL: schema, RLS, RPCs, triggers, reference data
  functions/            Edge Functions (Deno)
    _shared/providers/  selfie/, moderation/, ai/, geocoding/, rewards/ -> interface.ts, mock.ts, real.ts
  tests/                pgTAP: SQL business rules + RLS
  seed/                 TS generator -> seeds/20_profiles.sql (100 fictional profiles)
  seeds/                SQL applied by `supabase db reset` (local only), incl. test helpers
docs/
```

## Principles

1. **The database is the source of truth for business rules.** Constraints, triggers and `SECURITY DEFINER` RPCs enforce compatibility, quotas, drink combinations, groups and referral. The app never writes sensitive tables directly. TypeScript copies of rules exist only for UX validation.
2. **RLS deny-by-default on every table.** Other users' profiles are read only through RPCs (feed, match, outing card, group preview) returning an explicit list of public columns.
3. **Sensitive fields** (seeking genders, orientation, situation, structure, composition) live in `profile_sensitive`, encrypted with `pgcrypto` (`pgp_sym_encrypt`) using a key stored in Supabase Vault. No client role can read the table; only `SECURITY DEFINER` functions decrypt, and the feed decrypts only after the distance prefilter.
   - Why: the feed must filter in SQL; app-level or Edge-Function encryption would prevent it, and blind indexes on such small value sets leak the values.
   - Protects against: dumps, backups, staff table browsing, read-only leaks. Does not protect against a compromised service role that also has Vault access (to state in the DPIA).
4. **Location**: the client sends a position (or a home city) to the `update-location` Edge Function, which geocodes the country and calls `service_set_location`; the RPC snaps it to a ~1 km grid before storing. Exact coordinates are never persisted, even privately. Distances are returned as buckets.
5. **Like quota** computed on the fly over a rolling 24 h window (indexed count), no counter to resync.
6. **Premium**: RevenueCat webhook (Edge Function) feeds `entitlements`; server-side `is_premium(uid)` is authoritative. Referral rewards isolated behind `RewardsProvider`.
7. **Push**: `notification_outbox` drained by `pg_cron` → Edge Function. Generic texts only, never sensitive data.
8. **Analytics**: PostHog wrapper accepts only an allowlist of typed events/properties; Sentry `beforeSend` scrubs PII.
9. **Environments**: dev = local Supabase + an EU dev project; prod = separate EU project. `APP_ENV` selects real vs mock providers.
10. **Impersonation ("tester en tant que")**: Edge Function `dev-impersonate`, requires `APP_ENV=development` AND the `app_config` flag AND an `is_seed` target account. CI refuses to deploy it to production.

## Provider interfaces

`SelfieVerificationProvider` (liveness, age estimate, duplicate face), `PhotoModerationProvider`, `ProfileAnalysisProvider` + `AiOutputGuard`, `GeocodingProvider`, `RewardsProvider`, `PushSender`, `Analytics`. Scam detection (`ScamRules`) is local and rule-based.

## Tests

pgTAP (SQL rules + RLS, incl. "a user cannot read another user's sensitive fields"), Vitest (`packages/shared`), `deno test` (Edge Functions, AI output guard), Jest + RNTL (critical screens).

## Main tables

| Domain | Tables |
|---|---|
| Config | `app_config`, `country_config`, `drinks`, `drink_compatibility`, `structure_compatibility`, `prompt_questions` |
| Profile | `profiles`, `profile_sensitive`, `profile_drinks`, `drink_change_history`, `profile_prompts`, `photos` |
| Compliance | `consent_texts`, `consents`, `access_log`, `verifications`, `contact_block_hashes` |
| Interactions | `swipes`, `matches`, `conversations`, `conversation_members`, `messages`, `blocks`, `reports`, `moderation_queue` |
| Monetization | `entitlements`, `boosts`, `referral_codes`, `referrals`, `referral_rewards` |
| Social | `friendships`, `outings`, `outing_invitations`, `outing_feedback` |
| Groups | `groups`, `group_members`, `group_join_requests`, `group_votes` |
| Couples | `couples`, `couple_invitations`, `couple_like_approvals`, `couple_photo_approvals` |
| AI / metrics | `ai_analyses`, `push_tokens`, `notification_outbox` |

## Legal checklist before production

DPIA (art. 9 data); DPAs with Supabase, RevenueCat, PostHog, Sentry, selfie/age, moderation, AI and SMS providers; non-EU transfers (RevenueCat, Sentry); Apple 3.1.1 / 3.2.2 and Google Play rules on rewarded referral; biometrics (face template); retention after minor-account deletion; Terms (couples, content, suspensions); age-assurance vs Arcom framework; store-safe wording for Cocktail; popularity indicator disclosed in the privacy policy and DPIA; product analytics opt-out vs CNIL audience-measurement exemption (else consent at signup).
