---
name: tava-run-and-operate
description: Use when running TAVA clients, deploying the dashboard, operating production Supabase, managing users, inspecting jobs/logs, or configuring a kiosk. Includes the production-touch protocol and current release channels.
---

# TAVA run and operate

## Run locally

| Platform | Command | Notes |
|---|---|---|
| iOS | open `iOS/TAVAttendance.xcodeproj` after `xcodegen generate` | Simulator/device config comes from `iOS/Config.xcconfig` |
| Android | `cd Android && ./gradlew installDebug` | JDK 17/21 and device/emulator |
| Web | `cd web && npm run dev` | `http://localhost:3000` |
| Backend | `supabase start` | Studio `http://127.0.0.1:54323` |

Use `tava-build-and-env` for prerequisites and `tava-validation-and-qa` before
claiming a result.

## Ship clients

- Web: use `.claude/skills/deploy/SKILL.md`; it includes dependency, drift,
  security-header and post-deploy gates.
- Android: Firebase App Distribution through `Android/distribute.sh`.
- iOS: TestFlight/App Store Connect is primary; AltStore is an explicit legacy
  fallback. Use the `release` runbook.

Any migration a client requires must be verified in production before that
client is shipped.

## Production Supabase protocol

Project: `zgikcbsxzjgbigywxbbj`.

- Read-only diagnostics may use an authenticated Supabase connector or `psql`
  with `TAVA_DB_URL`. Select only fields needed for diagnosis; do not dump
  children's records into logs or chat.
- Production SQL writes must come from the exact reviewed, committed migration
  file and follow `tava-prod-drift-campaign`. Do not run ad-hoc SQL whose final
  form is absent from Git/HUMANS.md.
- Never run `supabase db reset` or `supabase db push` against production.
- After function changes: `NOTIFY pgrst, 'reload schema';`.
- After schema work: run `scripts/drift-check.sh`,
  `scripts/prod-security-check.sql`, SQL regressions, and advisor checks.
- Dashboard-only Auth, Vault, log-drain, domain and provider settings require a
  HUMANS.md item and direct verification.
- Keep database URLs/tokens and query results containing PII out of terminal
  arguments, tickets, transcripts and commits.

## Jobs and Edge Functions

- `pdpa-daily-purge` calls `purge_expired_personal_data()` daily.
- `app-events-purge` retains raw app events for the configured 90-day window.
- `student-storage-cleanup` invokes the dedicated cleanup Edge worker every 15
  minutes when its Vault secret and deployed function are active.
- `notify-parent` is inert until dedicated invocation secrets/provider keys are
  installed and `push_notifications` is enabled.

Measure live jobs:

```sql
SELECT jobname, schedule, active
FROM cron.job
ORDER BY jobname;
```

Do not assume a migration-created job or function is deployed/armed. Verify the
queue drains, the Edge Function version is current, and failed attempts are
observable.

## Logs

- Web runtime: Vercel production logs.
- Auth/API/Postgres/Edge: Supabase Dashboard logs.
- Product telemetry: `/health` and `/activity` when the `analytics` flag is on.

Redact access tokens, cookies, email addresses, student names, free text and
full request bodies before sharing. Preserve original restricted logs for a
security incident; do not “clean up” evidence.

## User management

The web `/users` page invites/removes users and links parents to students. The
single DB-managed superadmin can invite/remove admin accounts; ordinary admins
are more restricted. Supabase Dashboard invite remains an emergency path, but
never trust role metadata to mint privileged access. Verify the resulting
`profiles` row and least-privilege role.

Production public signup must remain off. Parent links can be managed in
`/users`; direct SQL is a reviewed fallback only.

## Kiosk setup

1. Use a dedicated production kiosk device with OS passcode, updates and
   physical supervision.
2. Until a least-privilege kiosk role exists, sign in with the designated admin
   account; recognise that this stores a reusable privileged session.
3. Gear → Kiosk Settings → set a non-trivial PIN → Lock Kiosk Now.
4. Enable biometric unlock only for enrolled staff and verify restart,
   backgrounding and app-switcher behaviour.
5. Do not hand the device to students if no PIN is set.
6. Record the account/device owner, deployment version and recovery contact;
   never record its password in this repository.

HUMANS.md §63 tracks replacement of the full-admin kiosk trust model.

## Provenance

Audited 2026-07-26 against current clients, migrations 031/038, production
security workflows, `/users`, mobile release scripts and HUMANS.md §§60–69.
Live configuration remains a measured fact, not a runbook claim.
