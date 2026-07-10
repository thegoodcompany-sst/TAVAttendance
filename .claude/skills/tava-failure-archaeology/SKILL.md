---
name: tava-failure-archaeology
description: Use before proposing any TAVA fix or approach — to check "has this been tried?", "was this rejected?", or when your hypothesis matches a known incident. The chronicle of every major investigation, dead end, rejected approach, and revert, each as symptom → root cause → evidence → status, so you never re-fight a settled battle. (For design rationale, use tava-architecture-contract instead.)
---

# TAVA Failure Archaeology

The settled battles. If your hypothesis matches an entry here, the
investigation is already done — read the entry, don't redo it.

**When NOT to use this skill:** you need live triage steps (use
`tava-debugging-playbook`); you need the design rationale for something that
never failed (use `tava-architecture-contract`).

## Incidents (chronological)

### 1. Hardcoded Supabase credentials (2026-06, resolved)
- **Symptom**: teacher flagged "obvious vulnerabilities"; anon key + URL sat in `build.gradle.kts` and Swift source.
- **Root cause**: MVP-era hardcoding. Bonus finding: the hardcoded Android version had never actually built (`buildConfig = true` was missing).
- **Fix**: gitignored config per platform (`Config.xcconfig` / `secrets.properties` / `.env.local`), commit aecc9dc; pre-commit secret scanner in `.githooks/`.
- **Status**: CLOSED. Anon key remains in git history — **accepted risk** (anon key is public-by-design, security rests on RLS; HUMANS.md §32 offers optional rotation). Do NOT propose a history rewrite; explicitly rejected as pointless.

### 2. `attendance_summary` ran as owner — global attendance leak (2026-06-10, recurred 2026-07)
- **Symptom**: none visible; found by audit. Any authenticated (even anon) reader could read every student's attendance.
- **Root cause #1**: migration 007 (`security_invoker = on`) existed in the repo but **was never applied to the live DB** (live `reloptions` was NULL).
- **Root cause #2 (recurrence)**: migration 015's `CREATE OR REPLACE VIEW` silently reset the view's options, dropping `security_invoker` again — and also dropped 010's `is_active` filters.
- **Evidence**: `SELECT relname, reloptions FROM pg_class WHERE relname='attendance_summary';`
- **Fix**: 009 applied 2026-06-10; recurrence fixed in 016 (SEC-16a/b), applied to prod 2026-07-09. CLOSED.
- **Lesson (load-bearing)**: repo migrations ≠ live DB; and every touch of this view must re-state `WITH (security_invoker = true)`.

### 3. Prod schema drift (discovered 2026-06-25, RESOLVED 2026-07-09)
- **Symptom**: applying 013 verbatim to prod rolled the whole transaction back.
- **Root cause**: migrations **004 and 005 were never applied to prod** (only fragments applied ad-hoc), so key columns/functions/policies were missing; `supabase_migrations.schema_migrations` records only a sparse subset because much was applied out-of-band.
- **Status**: CLOSED — full reconciliation 2026-07-09 (prod = 001–017); the how-it-was-done record and the prevention protocol live in `tava-prod-drift-campaign`.

### 4. Study-space column outage (2026-06-27, resolved)
- **Symptom**: prod web dashboard "This page couldn't load" for all authed users.
- **Root cause**: web deployed with `queries.ts` filtering `classes.is_study_space = false` before migration 015 was applied → PostgREST "column classes_1.is_study_space does not exist".
- **Fix**: applied 015 (plus its `students.avatar_url` prereq — the first apply attempt rolled back on that missing column; 015 is idempotent so the retry was clean).
- **Lesson**: migration-before-deploy, always. Now a change-control non-negotiable.

### 5. "Failed to mark dismissal" (2026-06-29, resolved)
- **Symptom**: iOS kiosk dismissal marking failed every time.
- **Root cause**: `recordDismissal` upserts `onConflict: "session_id,student_id"`, but prod lacked 010's `dismissals_session_student_unique` UNIQUE constraint → Postgres 42P10.
- **Fix**: applied that constraint to prod (dedup DELETE first). Same drift family as #3, resolved with it on 2026-07-09.

### 6. `get_roster_for_date` missing — login crash (2026-06-25, resolved)
- **Symptom**: PostgREST "Could not find the function public.get_roster_for_date" crashing login.
- **Fix**: applied just that RPC as partial migration `014a`; then `NOTIFY pgrst, 'reload schema';` (without which PostgREST kept 404ing — a trap in its own right).
- **Status**: rest of 014 applied 2026-07-09 (drift campaign). CLOSED.

### 7. xcconfig `//` comment bug (2026-06, resolved)
- **Symptom**: iOS app couldn't reach Supabase; URL truncated to `https:`.
- **Root cause**: xcconfig treats `//` as a comment start, eating the URL after `https:`.
- **Fix**: commit 1ecce4e restored Info.plist wiring + escaped the URL. Fresh-checkout wiring still has a human decision open (HUMANS.md §13).

### 8. Self-signup could mint an admin (2026-07-06 audit, code-fixed)
- **Symptom**: none observed; audit finding SEC-16c.
- **Root cause**: `handle_new_user` trusted `raw_user_meta_data.role` when `auth.uid() IS NULL` — but public self-signup also runs with NULL uid.
- **Fix**: 016 hardens the trigger; `web/app/actions/invite.ts` now sets roles via service role after creation. Prod still needs 016 applied AND public signup disabled in the dashboard (HUMANS.md §30/§31).

### 9. Kiosk phantom sessions on non-tuition days (2026-06, resolved by design change)
- **Symptom**: opening the kiosk on e.g. a Wednesday created session rows for every active class.
- **Root cause**: `fetchKioskEntries` intentionally pre-creates today's sessions, but had no concept of "which classes actually meet today".
- **Fix**: migration 015 + `classMeetsToday` (iOS): match BYDAY in `recurrence_rule`, or `schedule_day`, or neither-set = ad-hoc always shown. TAVA tuition is Mon + Thu.

### 10. Kiosk session-upsert FK 409 (2026-07-02, resolved)
- **Fix**: commit 8708511. Read its diff before touching session-creation code.

## Dead ends and deliberate non-fixes (do not re-propose)

| Idea | Verdict |
|---|---|
| Rewrite git history to purge the anon key | REJECTED — key ships in every client anyway; rotation via dashboard is the real lever (optional, §32). |
| "Fix" the `schedule_time` parser to expect exactly `HH:mm` | REJECTED — Postgres TIME returns `HH:mm:ss`; parser must accept both. |
| "Fix" the CodeSign `swift-crypto_Crypto.bundle` failure | NOT A CODE PROBLEM — local keychain issue; use `CODE_SIGNING_ALLOWED=NO`. |
| Per-class kiosk (`KioskView.swift`) | DELETED as dead code — was never wired to navigation. Recreate from `GlobalKioskView.swift` if ever needed. |
| Delete `PdpaPanel` (web) as dead code | DELIBERATELY KEPT in the 2026-07 refactor — it's the PDPA s16/s21/s25 machinery, built but never imported by `students/[id]/page.tsx`. Decision pending (HUMANS.md §29). Don't delete; don't wire without a decision. |
| Run Android unit tests on this machine | BLOCKED by JDK 26 jlink error until JDK 17/21 installed (§34). `compileDebugKotlin` is the accepted verification meanwhile. |
| Kiosk PIN → Keychain migration | DEFERRED with a `ponytail:` marker in `GlobalKioskView.swift` (~line 1243). Device-verify before/when completing (§33). |
| Unmerged branch `worktree-agent-a0964c91cbe6e7bb4` | Contains a draft result-slip Storage cleanup whose migration is numbered 013 — **clashes with main's 013**. Reference only, or renumber before any merge (§9). |

## Provenance and maintenance

Current as of 2026-07-09. Mined from `git log`, HUMANS.md §§9–34, migration
016's header, and project session notes now embedded above.
- New incidents since? `git log --oneline --since=2026-07-09 --grep='fix\|revert'`
- Still-open items: `grep '^### ☐' HUMANS.md`
