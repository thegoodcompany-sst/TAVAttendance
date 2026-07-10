---
name: tava-debugging-playbook
description: Use when anything in TAVA Attendance misbehaves — kiosk errors ("Failed to mark dismissal", cards wrong colour), web dashboard "This page couldn't load" / 500s, PostgREST 400/404/409 errors, blank student history, "Bucket not found", iOS build failures (CodeSign, xcconfig), Android gradle/jlink failures, offline sync not clearing. Symptom→cause→fix table plus the diagnostic queries to run before guessing.
---

# TAVA Debugging Playbook

Rule zero: **most bugs in this project are prod schema drift wearing a
costume.** Before debugging app code, check whether the DB object the code
references actually exists in the environment you're hitting (see
"Discriminating experiments" below).

**When NOT to use this skill:** you already know the fix is a schema change
(use `tava-change-control` + `tava-prod-drift-campaign`), or the app won't
even build on a fresh machine (use `tava-build-and-env`).

## Symptom → triage table

| Symptom | Likely cause | Fix / next step |
|---|---|---|
| Web dashboard: "This page couldn't load" after login; Vercel logs show PostgREST `column ... does not exist` | Web code deployed referencing a column whose migration isn't applied to prod (the 2026-06-27 `is_study_space` outage) | Apply the missing migration to prod, or roll back the deploy. Then read `tava-change-control` ordering rule. |
| iOS kiosk: "Failed to mark dismissal" | `recordDismissal` upserts with `onConflict: "session_id,student_id"` but prod lacks the matching UNIQUE constraint (Postgres error 42P10). Happened because migration 010's constraint was never applied. | Verify: `SELECT conname FROM pg_constraint WHERE conname='dismissals_session_student_unique';` — if absent, apply that piece of 010 (dedup DELETE first). Fixed in prod 2026-06-29. |
| PostgREST 404 "Could not find the function public.X" | Function created but PostgREST schema cache stale, OR function genuinely missing in this environment | Run `NOTIFY pgrst, 'reload schema';` first. If still 404, the function is missing — check drift. |
| PostgREST 400 on a nested select (e.g. `session:sessions(...)`) | FK-inference join string mismatched after a rename, or the embedded table/column is missing | The select string in `AttendanceService.fetchStudentAttendanceHistory` depends on FKs `attendance_records.session_id→sessions.id` and `sessions.class_id→classes.id`. Check Supabase logs for the exact 400 body. |
| Student Profile sheet: blank history, no error | Same PostgREST 400 swallowed upstream | Check Supabase logs (Dashboard → Logs → API) for the 400. |
| "Bucket not found" on student photo upload | `student-photos` bucket (migration 014) not applied to this environment | Part of the drift backlog — see `tava-prod-drift-campaign`. |
| Kiosk session upsert FK 409 | Session row creation raced/failed; fixed in commit 8708511 | If it recurs, re-read that commit's diff before inventing a new fix. |
| Kiosk shows "No Classes Today" unexpectedly | `classMeetsToday` filters by `recurrence_rule` BYDAY or `schedule_day`; TAVA tuition runs Mon (Math) + Thu (English). On other days this is CORRECT behaviour. | Not a bug unless it's Mon/Thu. If Mon/Thu: check the class's `schedule_day`/`recurrence_rule` values. |
| Wrong late/on-time marking | `schedule_time` is a Postgres TIME returned as `"HH:mm:ss"`; parser splits on `":"` taking [0],[1] and must keep accepting both `HH:mm` and `HH:mm:ss` | Don't "fix" the parser to assume two components. Check the class's `schedule_time` value and device clock. |
| Offline records never sync / silently vanish | `sync_attendance` uses `ON CONFLICT ... WHERE marked_at <= EXCLUDED.marked_at` — a device with a wrong clock loses to newer server rows. Ended sessions reject writes (`blocked_ended_session` count in the RPC's return). | Inspect the RPC's return `{synced, skipped, blocked_ended_session}`; check device clock; check `sessions.ended_at`. |
| Tutor-logged-in iPad kiosk shows only some classes | By design: RLS filters classes to `tutor_owns_class`. The kiosk iPad must be signed in as **admin**. | Operational fix, not code. |
| iOS build fails at `CodeSign swift-crypto_Crypto.bundle` | Pre-existing local keychain issue on this machine | NOT a code problem. Pass `CODE_SIGNING_ALLOWED=NO` (see `tava-build-and-env`). Do not try to fix. |
| iOS can't reach Supabase after config change | Unescaped `//` in `Config.xcconfig` — xcconfig treats `//` as a comment, truncating `https://...` | Escape as `https:/$()/` in the xcconfig, or verify `Info.plist` resolves the full URL. |
| Android `./gradlew test` fails with a jlink error | JDK 26 on this machine; AGP needs JDK 17/21 | Known environment gap (HUMANS.md §34). Verify with `./gradlew clean compileDebugKotlin` instead; `brew install --cask temurin@21` fixes it properly. |
| Web build errors about unfamiliar Next.js APIs | The repo pins a non-standard Next.js (16.x) | Read `web/AGENTS.md` and `node_modules/next/dist/docs/` before writing code — training-data Next.js knowledge may be wrong. |
| Session counts look inflated / sessions exist with no attendance | Intentional: opening the kiosk calls `getOrCreateSession` for every active class scheduled today | Not a bug. Filter by attendance rows if you need "sessions that happened". |

## Discriminating experiments (measure, don't guess)

Run these against the environment showing the symptom (local via `supabase db
reset` + Studio; prod via Supabase MCP `execute_sql`, read-only):

```sql
-- 1. Does the column the code references exist?
SELECT column_name FROM information_schema.columns
WHERE table_name = 'classes';  -- swap table

-- 2. Does the function exist, with the expected signature?
SELECT proname, pg_get_function_arguments(oid) FROM pg_proc
WHERE proname LIKE '%roster%';

-- 3. Is the security-critical view configured correctly?
SELECT relname, reloptions FROM pg_class WHERE relname = 'attendance_summary';
-- MUST include security_invoker=on. If NULL → critical leak, apply 016.

-- 4. What migrations does prod THINK it has? (sparse — much was applied out-of-band)
SELECT * FROM supabase_migrations.schema_migrations ORDER BY version;

-- 5. Which flags are on?
SELECT key, enabled FROM feature_flags;

-- 6. Is the constraint an upsert relies on present?
SELECT conname, contype FROM pg_constraint
WHERE conrelid = 'dismissals'::regclass;
```

Also: Supabase Dashboard → Advisors (security + performance) after any schema
work — it caught the `security_invoker` regression class before.

## Traps that cost real time (memorise)

1. **Repo migration files ≠ live DB state.** The single most expensive lesson here. Always verify with query #1–#4 above.
2. **PostgREST caches the schema.** A "missing function" right after you created it means you forgot `NOTIFY pgrst, 'reload schema';`.
3. **A single-transaction migration rolls back entirely** if any statement fails — `CREATE OR REPLACE FUNCTION` validates column references at creation, so a function body mentioning a missing column kills the whole migration (this is exactly why 013/014 fail on prod verbatim).
4. **Errors are swallowed in places.** Android inspects few of its `runCatching` results; older web code returned `[]` on failure. A blank screen ≠ no error — check Supabase logs.
5. **macOS Finder duplicates** (`Name 2.swift`, `Dir 2/`) are junk. Delete, never debug them.

## Provenance and maintenance

Current as of 2026-07-09.
- Symptom table sources: git history (`git log --oneline --grep=fix`), HUMANS.md §30–34, migration 016 header comments.
- Re-verify parser claim: `grep -n 'split' iOS/TAVAttendance/Services/AttendanceService.swift | head`
- Re-verify kiosk day filter: `grep -n 'classMeetsToday' -r iOS/`
