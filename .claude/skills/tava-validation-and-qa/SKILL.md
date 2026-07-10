---
name: tava-validation-and-qa
description: Use before claiming ANY TAVA change is done, tested, or safe — defines what counts as evidence per platform (exact build/test commands), the manual QA checklists (kiosk, admin mode, roster, profile history), the evidence bar for prod claims (query the DB, don't trust files), and how to add automated tests to a suite-less project.
---

# TAVA Validation and QA

What "verified" means here. This project has **no automated test suite** —
the verification bar is a combination of platform build commands, manual
checklists, and direct DB queries. "It compiles" is the floor, not the bar.

**When NOT to use this skill:** the check fails and you need triage (use
`tava-debugging-playbook`); validating a prod migration (the campaign skill
has its own gate queries).

## The evidence bar (non-negotiable discipline)

1. **A claim about prod is verified by querying prod**, never by reading migration files (files ≠ live DB; the project's costliest lesson).
2. **A UI claim is verified by running the flow**, not by reading the code. Blank screens hide swallowed errors on two platforms.
3. **Success must be measurable**: a specific command output, query result, or checklist step — never "looks right".
4. Report failures verbatim. A skipped step is reported as skipped.

## Per-platform verification commands

| Platform | Command (run from) | What it proves |
|---|---|---|
| iOS | `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project TAVAttendance.xcodeproj -scheme TAVAttendance -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO` (from `iOS/`) | Compiles + any XCTests pass. CodeSign bundle failure = local keychain, ignore. Machine-specific flags: see `tava-build-and-env`. |
| Android | `./gradlew clean compileDebugKotlin` (from `Android/`) | Compiles only. `./gradlew test` is blocked on this machine (JDK 26); CI's `assembleDebug` covers R8. Once JDK 17/21 exists: `./gradlew testDebugUnitTest`. |
| Web | `npm run lint && npm run build` (from `web/`) | Lint + production build. CI runs the same. |
| Migrations | `supabase db reset` (repo root) | All 16 migrations apply in order on a clean local DB. For a new migration also run its `down/` reverse script then the forward again. |

Note: this table matches CLAUDE.md §Running tests (the agent-facing source of
truth, machine caveats included); CONTRIBUTING.md §5 defers to it.

## Manual QA checklists (the project's regression suite)

Run the ones your change touches. Full scripts live in CLAUDE.md §Testing
procedures; condensed:

**Kiosk sign-in** (admin login → Sign In tab; needs a class with
`schedule_time` in the past to exercise Late):
tap student → green (on time) / orange (late) → long-press green: "Mark as
Late"/"Mark as Not Here" offered → mark late: turns orange → mark not-here:
grey and tappable again → tap again: re-signs-in.

**Admin mode**: set PIN → lock → unlock with PIN shows ADMIN badge → tap
orange card flips to green → long-press offers "Mark as Absent" (red) →
re-lock hides overrides.

**Teacher roster** (tutor login): Start Today's Class → mark present →
"Marked HH:MM" shows → tap row: Student Profile sheet with history → Wi-Fi
off, mark: orange pending dot → Wi-Fi on: dot clears (sync ran).

**Profile history**: blank list with no error = swallowed PostgREST 400 —
check Supabase logs, suspect the FK join string.

**Study space (flag on, iPad)**: header button → `StudySpaceView` → roster =
all active students → Present/Not Here only → verify NOTHING appears in any
report/parent view (invariant).

**Web smoke**: login → dashboard renders (today's sessions + daily
attendance) → student detail → CSV export. Superadmin: `/feature-flags`
lists 5 flags (incl. test_mode), toggle persists across reload; other admin gets 404.

## DB-level checks (paste-ready)

```sql
-- security posture of the money view
SELECT reloptions FROM pg_class WHERE relname='attendance_summary';  -- {security_invoker=on}
-- flags as expected
SELECT key, enabled FROM feature_flags ORDER BY key;
-- study-space exclusion holds (0 rows expected)
SELECT COUNT(*) FROM attendance_summary a
JOIN classes c ON c.id = a.class_id WHERE c.is_study_space;
-- purge job alive
SELECT jobname, active FROM cron.job WHERE jobname='pdpa-daily-purge';
```

## Adding automated tests (how to raise the bar)

- **iOS**: XCTest target exists via the xcodebuild command above. Add tests under the test target in `project.yml`, `xcodegen generate`, then run. Good first targets: `worstStatus` merge, `classMeetsToday`, schedule-time parsing (pure logic, no network).
- **Android**: mirror iOS tests as JUnit (`DayAwareKioskTest` is the pattern) — runnable in CI today even while blocked locally.
- **Web**: no test runner configured; per project convention decide case-by-case — pure helpers in `web/lib/` (date, csv, status) are the natural first tests if one is added.
- **DB**: the cheapest high-value check is a migration round-trip in CI (`db reset` already lints); assertions like the study-space-exclusion query above can live in a new migration-adjacent SQL check script.
- Convention: don't build frameworks/fixtures for one test; smallest thing that fails when the logic breaks.

## Certified/golden inventory

There are no golden datasets. `supabase/seed.sql` is the canonical local
fixture. Prod data is real children's data — never copy it to local, never
use it as test fixtures (PDPA).

## Provenance and maintenance

Current as of 2026-07-09.
- Test suite still absent? `find . -name '*Tests*' -o -name '*.test.*' | grep -v node_modules`
- Android test: `ls Android/app/src/test/java/com/example/tavattendance/`
- Checklists drift with UI changes — canonical copy is CLAUDE.md §Testing procedures.
