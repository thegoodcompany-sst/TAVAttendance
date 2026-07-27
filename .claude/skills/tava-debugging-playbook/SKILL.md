---
name: tava-debugging-playbook
description: Use when TAVA misbehaves — evidence-first triage for schema/authz errors, kiosk/roster/offline failures, Storage, web, iOS and Android builds.
---

# TAVA debugging playbook

Do not default every failure to schema drift. First identify the failing
environment, actor, request/RPC, source commit, app version, timestamp and
feature-flag state. Production schema drift remains a high-cost possibility,
but migration 038 also intentionally turns formerly accepted writes into
authorization or validation errors.

## Symptom triage

| Symptom | Discriminating check | Next step |
|---|---|---|
| Web load failure with PostgREST missing-column/function error | Compare the named object with live `information_schema`/`pg_proc`; check current remote drift workflow | Apply reviewed migration before client, or roll back client |
| PostgREST RPC 404 immediately after apply | Query `pg_proc` first | If present, `NOTIFY pgrst, 'reload schema'`; otherwise diagnose drift |
| 401/403/42501 after security migration | Confirm user, `profiles.role`, `security_principals`, feature flag and target RPC | Treat as an authz boundary until proven otherwise; do not loosen RLS to hide it |
| Attendance write rejected | Inspect structured error and session date/state; ended sessions and offline replay older than 7 days are blocked | Use retrospective workflow where authorised; never direct-edit around guard |
| Offline dot does not clear | Inspect `sync_attendance` result, queue owner, current auth user, network and session state | Preserve the queue; do not promise it synced until server data confirms |
| Data appears under the wrong account | Stop syncing, sign out, preserve restricted logs, treat as a security incident | Follow breach plan; queue codecs should purge foreign/mixed ownership |
| “Bucket not found” / upload finalisation failure | Verify private bucket, signed intent, canonical path, MIME/size/signature and Edge/storage logs | Do not make a bucket public or bypass finalisation |
| Empty kiosk unexpectedly | Verify admin kiosk account, class schedule/recurrence, `test_mode`, app clock/time zone | Tutor RLS may correctly show only assigned classes |
| Android auth disappears after upgrade/restore | Check for Keystore invalidation/corrupt ciphertext without logging tokens | Fail closed and sign in again; never fall back to retained plaintext prefs |
| Android jlink/build error | Print JDK and Gradle versions | Use JDK 17/21; do not change app code for an unsupported JDK |
| iOS CodeSign bundle error in simulator test | Retry with `CODE_SIGNING_ALLOWED=NO` and correct Xcode path | Separate local signing/keychain from code failures |
| Next.js API/build mismatch | Read `web/AGENTS.md` and installed Next docs | The repo pins Next 16; do not rely on older conventions |

## Read-only database experiments

Run against the failing environment and avoid selecting PII:

```sql
SELECT column_name
FROM information_schema.columns
WHERE table_schema='public' AND table_name='<table>';

SELECT proname, pg_get_function_identity_arguments(oid)
FROM pg_proc
WHERE pronamespace='public'::regnamespace AND proname='<rpc>';

SELECT reloptions
FROM pg_class
WHERE oid='public.attendance_summary'::regclass;

SELECT policyname, cmd, roles, qual, with_check
FROM pg_policies
WHERE schemaname='public' AND tablename='<table>';

SELECT key, enabled FROM feature_flags ORDER BY key;
```

For production, run the full read-only
`scripts/prod-security-check.sql` rather than maintaining a partial hand-copy.
The migration ledger is diagnostic history, not proof of end state.

## Evidence handling

- Capture UTC/Singapore timestamps, route/RPC, error code, request ID, app
  version and actor UUID where necessary.
- Do not paste cookies, JWTs, database URLs, service-role keys, child names,
  messages, notes, photos or full query results into chat/issues.
- Preserve restricted logs and affected device state for suspected compromise.
- A blank UI is not evidence of “no data”; inspect the logged API error.

## Known historical traps

- `attendance_summary` lost `security_invoker` twice; every replacement must
  restate it.
- Web-before-migration caused the 2026-06-27 outage.
- Function return-type changes require drop/recreate.
- PostgREST caches schema.
- Postgres `TIME` arrives as `HH:mm:ss`; parsers must also accept `HH:mm`.
- The kiosk intentionally pre-creates eligible current-day sessions.

## Provenance

Audited 2026-07-26 against migration 038, current native queues/auth storage,
web error boundaries, CI JDK/Xcode commands and executable production checks.
