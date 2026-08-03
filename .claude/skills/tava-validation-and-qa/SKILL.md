---
name: tava-validation-and-qa
description: Use before claiming ANY TAVA change is done, tested, or safe — defines what counts as evidence per platform (exact build/test commands), the manual QA checklists (kiosk, admin mode, roster, profile history), the evidence bar for prod claims (query the DB, don't trust files), and how to add automated tests to a suite-less project.
---

# TAVA Validation and QA

What "verified" means here. The repo has iOS/Android/web unit tests and SQL
security regressions; the verification bar combines them with builds, manual
flow checks and direct environment evidence. "It compiles" is the floor.

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
| Android | `./gradlew testDebugUnitTest assembleDebug --no-daemon` (from `Android/`, JDK 17/21) | Unit tests + debug app build. Separately exercise a minified release when release/storage/serialization dependencies change. |
| Web | `bun audit --audit-level=high && bun run test && bun run lint && bun run build` (from `web/`, after `bun install --frozen-lockfile`) | Dependency, unit, lint and production build gates. |
| Migrations | `supabase db reset --local && supabase db lint --local --schema public --level error --fail-on error`, then every `supabase/tests/*.sql` | All migrations through 053 replay plus SQL security regressions. |

Note: this table matches CLAUDE.md §Running tests (the agent-facing source of
truth, machine caveats included); CONTRIBUTING.md §5 defers to it.

## Manual QA checklists (the project's regression suite)

Run the ones your change touches. Full scripts live in CLAUDE.md §Testing
procedures; condensed:

**Kiosk sign-in** (admin login → Sign In tab; needs a class with
`schedule_time` in the past to exercise Late):
tap student → green (on time) / orange (late) → long-press green: "Mark as
Late"/"Mark as Not Here Yet" offered → mark late: turns orange → clear to
Not Here Yet: attendance row removed, card grey and tappable again → tap again: re-signs-in.

**Admin mode**: set PIN → lock → unlock with PIN shows ADMIN badge → tap
orange card flips to green → long-press offers "Mark as Absent" (red) →
re-lock hides overrides.

**Teacher roster** (tutor login): Start Today's Class → mark present →
"Marked HH:MM" shows → tap row: Student Profile sheet with history → Wi-Fi
off, mark: orange pending dot → Wi-Fi on: dot clears → verify the server row.
Test sign-out/account transitions with pending data; foreign/mixed queues must
fail closed, not cross-sync.

**Profile history**: blank list with no error = swallowed PostgREST 400 —
check Supabase logs, suspect the FK join string.

**Study space (flag on, iPad)**: header button → `StudySpaceView` → roster =
all active students → Present/Not Here Yet only → verify NOTHING appears in any
report/parent view (invariant).

**Web smoke**: login → dashboard/mobile staff surfaces → student detail →
safe export. Superadmin: `/feature-flags` lists the live rows and toggle
persists; ordinary admin gets 404. Parent/tutor/admin role boundaries are
separate cases.

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

- **iOS**: XCTest target and `TAVAttendanceTests` exist; keep pure security and
  queue logic testable outside UI/network.
- **Android**: JUnit covers kiosk, analytics, parent RPC shape, queue ownership,
  retrospective rules and secure auth key migration.
- **Web**: Vitest is configured; security-sensitive pure helpers and export
  filtering need regressions.
- **DB**: migration self-checks plus `supabase/tests/*.sql` exercise roles,
  grants, RLS/RPC and Storage boundaries.
- Convention: don't build frameworks/fixtures for one test; smallest thing that fails when the logic breaks.

## Certified/golden inventory

There are no golden datasets. `supabase/seed.sql` is the canonical local
fixture. Prod data is real children's data — never copy it to local, never
use it as test fixtures (PDPA).

## Provenance and maintenance

Audited 2026-07-26.
- Test inventory: `find iOS/TAVAttendanceTests Android/app/src/test web supabase/tests -type f | sort`
- Android tests: `ls Android/app/src/test/java/com/example/tavattendance/`
- Checklists drift with UI changes — canonical copy is CLAUDE.md §Testing procedures.
