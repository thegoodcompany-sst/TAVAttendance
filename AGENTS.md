# AGENTS.md — How to change TAVA Attendance safely

This file is the portable operating contract for coding agents. It explains how
to make changes, what must remain true, and where detailed procedures live.
Facts that can be discovered from code or change frequently belong in code,
tests, or the matching runbook—not here.

`CLAUDE.md` is intentionally only `@AGENTS.md`. Do not duplicate this file there.

## Start every task here

1. Read this file and check `git status`; preserve unrelated user changes.
2. Classify the work and load the matching `.claude/skills/*/SKILL.md` before
   acting. A runbook is an executable procedure, not background reading.
3. Inspect the nearest implementation, tests, and the equivalent flow on other
   platforms before designing a change.
4. Make the smallest coherent change at the established data or domain seam.
5. Run proportionate verification from `tava-validation-and-qa`.
6. Update the owning documentation and `RELEASE_NOTES.md` in the same change.
7. Unless the user says otherwise, commit verified implementation work and push
   directly to `main`. Do not open a branch or PR by default.

For diagnosis/review/reporting requests, remain read-only unless the user also
asks for a fix. Do not deploy, flip flags, or mutate production merely because
you inspected it.

## Runbook routing

| Work | Read first |
|---|---|
| Any repository change | `tava-change-control` |
| Bug or unexpected behaviour | `tava-debugging-playbook`, then `tava-failure-archaeology` before proposing a fix |
| Feature or architecture work | `tava-architecture-contract` |
| Supabase schema, RLS, RPC, Storage | `tava-supabase-reference` + `tava-change-control` |
| Production schema or suspected drift | `tava-prod-drift-campaign` |
| Local setup or build failure | `tava-build-and-env` |
| Testing or completion claim | `tava-validation-and-qa` |
| Flags, runtime configuration | `tava-config-and-flags` |
| Production operation | `tava-run-and-operate` |
| Docs of record | `tava-docs-and-writing` |
| Privacy or parent/student data | `tava-pdpa-reference` |
| Web deployment | `deploy` |
| Mobile/App Store release | `release` |

If a runbook blocks necessary work, explain the exact restriction. The user may
explicitly authorize a safe exception or ask for the runbook to be changed.

## Repository shape and change seams

TAVA has one Supabase backend and three clients:

| Area | Location | Established seam |
|---|---|---|
| iOS/iPadOS | `iOS/` (SwiftUI) | `AttendanceService` extensions and focused services; never query Supabase from a view |
| Android | `Android/` (Compose) | `data/service` data sources; never query Supabase from a composable |
| Web | `web/` (Next.js, Bun) | `lib/queries/*` and server actions; keep database access out of client components |
| Backend | `supabase/` | Numbered SQL migrations, RLS, shaped RPCs, and private Storage |

There is no custom application server. PostgREST/RPC and Row-Level Security are
the backend interface, so **RLS is the authorization layer**. A client-side role
or hidden control is never authorization.

Prefer deep domain modules: keep policy, validation, and data shaping behind a
small interface. Split files by domain when useful; do not create pass-through
wrappers or force unrelated operations into one large service file.

## Non-negotiable invariants

Violating any item below is a bug even when the UI appears to work.

1. **Study Space is internal only.** Every report, export, report card, award,
   analytics result, attendance summary, and parent-facing query must exclude
   `classes.is_study_space = TRUE` at its source.
2. **Production migrations are append-only.** Never edit an existing migration.
   Add a new numbered forward migration and a matching reverse script under
   `supabase/migrations/down/`; update `supabase/migrations/README.md`.
3. **Schema precedes dependent clients.** Apply and verify a migration in
   production before deploying code that references its objects. Never use
   `supabase db reset` or `supabase db push` against production.
4. **Production state is measured.** Repository files and the historical
   migration ledger are not proof. Query production and run the protected drift
   and security gates before making a production-state claim.
5. **`attendance_summary` is security-invoker.** Every recreation must include
   `WITH (security_invoker = true)` and continue excluding Study Space.
6. **Offline attendance remains safe.** Mutations are actor-bound,
   server-timed, idempotent, and replay-safe. Native queues clear on sign-out
   and must never sync another account's records.
7. **Attendance status stays three-valued.** Stored status is `present`, `late`,
   or `absent`. “Not Here Yet” means no row; `absence_informed` is a nullable
   companion field on absent rows; dismissal is a separate safety event.
8. **Unshipped work is flag-gated and ships OFF.** A flag is shared by all
   clients; flipping one is a separate human-verified operation.
9. **The centre-wide kiosk uses an admin account.** Tutor visibility is scoped
   and cannot supply the full kiosk roster. A configured kiosk PIN controls the
   UI but does not reduce the privilege of the stored Supabase session.
10. **Credentials never enter source or logs.** Use the gitignored platform
    configuration files described in `CONTRIBUTING.md`. Avoid printing tokens,
    database URLs, student names, or parent data.
11. **iOS is XcodeGen-managed.** Edit `iOS/project.yml`, never the generated
    `.xcodeproj`; regenerate when project structure changes.
12. **Parent access uses shaped RPCs.** Extend the safe projection and its role
    tests. Never restore broad parent access to base tables for convenience.

Detailed attendance and kiosk semantics live in `docs/KIOSK_ATTENDANCE.md`.
Rationale and known weak points live in `tava-architecture-contract`.

## How to change each area

### Supabase

- Inspect object dependencies and later replacements before writing SQL.
- Create a new migration; never repair behaviour by changing an old file.
- Add the reverse file outside the forward migration directory.
- Add SQL role/RLS/RPC regressions for authorization changes.
- Replay from a clean local database before any production apply.
- Apply only the exact reviewed migration file through the authorized workflow.
- After function changes, reload the PostgREST schema and run remote drift,
  security, and advisor checks.

### iOS and Android

- Keep equivalent domain behavior aligned, but follow each platform's existing
  language and UI patterns.
- Extract pure policy or transition logic from large views/screens when the
  change would otherwise deepen UI state complexity.
- Preserve offline ownership, feature-flag, role, and error-surfacing behavior.
- If an iOS feature changes, finish with paste-ready Android and Web handoff
  blocks using the template in `Android/PORTING_NOTES.md`. Do not spawn porting
  agents automatically; each port is a separate review cycle.

### Web

- Use Bun and the checked-in lockfile.
- Read `web/AGENTS.md` before changing Next.js code; this repository's pinned
  version may differ from model knowledge.
- Put reads in the domain query layer and writes in server actions.
- Handle thrown query errors through the established boundary/state rather than
  returning an indistinguishable empty result.
- Keep privileged user/flag operations server-side and DB-authorized.

## Verification commands

Use `tava-validation-and-qa` for the full evidence bar and manual checks.

| Platform | Command | Directory |
|---|---|---|
| iOS | `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project TAVAttendance.xcodeproj -scheme TAVAttendance -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO` | `iOS/` |
| Android | `./gradlew testDebugUnitTest lintDebug assembleDebug --no-daemon` | `Android/` |
| Web | `bun install --frozen-lockfile && bun audit --audit-level=high && bun run test && bun run lint && bun run build` | `web/` |
| Supabase | `supabase db reset --local && supabase db lint --local --schema public --level error --fail-on error`, then every `supabase/tests/*.sql` | repository root |

On this Mac, iOS verification must use Xcode-beta and disable signing. A failure
at `CodeSign swift-crypto_Crypto.bundle` is a known local keychain issue; report
it rather than modifying project signing.

## Documentation ownership

Keep one authoritative home for each fact:

| File | Owns |
|---|---|
| `AGENTS.md` | Portable workflow, invariants, change seams, canonical commands |
| `.claude/skills/` | Detailed task runbooks and operational procedures |
| `CONTRIBUTING.md` | Human local setup and contributor workflow |
| `README.md` | Product description, stack, layout, shipped/flagged roadmap |
| `docs/KIOSK_ATTENDANCE.md` | Kiosk and attendance domain semantics |
| `docs/API.md` | Client/backend integration contract |
| `NEXT_BUILD_CHANGES.md` | Agreed or queued work not yet implemented |
| `RELEASE_NOTES.md` | Completed changes under `Unreleased` |
| `HUMANS.md` | Numbered human-only actions and dated verification evidence |
| `Android/PORTING_NOTES.md` | Cross-platform mapping and port handoff template |
| `supabase/migrations/README.md` | Migration index and reverse-migration convention |

Do not copy volatile inventories, current migration numbers, flag state, release
state, or production snapshots into this file. Link to the owning source or
show the query used to measure the live state.

## Definition of done

A requested implementation is done only when:

- the behavior and security invariants hold;
- proportionate automated tests/builds pass;
- touched user flows receive the relevant manual QA;
- schema changes have local replay evidence and, when shipping dependent code,
  verified production evidence in the required order;
- completed work is recorded under `RELEASE_NOTES.md` → `Unreleased`;
- planned work that shipped is removed or marked from `NEXT_BUILD_CHANGES.md`;
- human-only follow-up is added to `HUMANS.md` and clearly handed back;
- iOS feature work includes Android and Web port handoffs; and
- authorized change/build work is committed and pushed to `main` unless the
  user explicitly requests a different delivery path.

Do not treat a passing build as proof of UI behavior, a checked-in migration as
proof of production state, or a feature flag as a substitute for authorization.
