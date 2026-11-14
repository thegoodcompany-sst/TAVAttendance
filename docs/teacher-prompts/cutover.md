# Fresh database cutover: January 2027 target

This is a plan for a later, explicitly authorized human operation. None of these
live actions are authorized by the prototype task, and none have been performed.
The V2 prototype is not yet a complete replacement for TAVA Attendance. Use the
[contract](CONTRACT.md) for schema/client interfaces and the repository's production
schema, deployment and mobile-release runbooks when that later work is authorized.
Dates below are stages, not a promised release date.

## Gate 0 — agree what must survive

Owner: Edmund, operations lead, maintainer and DPO.

1. Inventory current web, iOS, Android and station RPC/table dependencies. Include
   parent portal, centre kiosk, arrival station, dismissal/safely-home, enrollment,
   exports, storage, access/correction/erasure and retention workflows. Mark each
   as required at launch, explicitly retired, or deferred with an operational plan.
2. Map old `profiles.role=tutor` to V2 `teacher`; old sessions to stable lesson
   occurrences; Auth identities to profiles; class assignments to one accountable
   teacher plus staff; and enrollments to dated membership/roster snapshots.
   Resolve multiple same-day lessons and substitutes explicitly. Never guess leads.
3. Decide whether attendance history remains in an archive or is imported through
   a separate reviewed mapping. There is no automatic personal-data import here.
   Capture provenance, date/time conversions, counts and reconciliation rules.
4. Approve feedback purpose/readers, staff notification notice, APNs processor
   assessment, retention, archive access and disposal obligations. Delivery logs
   and revoked devices have a proposed 30-day retention only; it is not approved
   policy. Do not inherit a draft seven-year rule blindly.
5. Assign named owners for timetable/closures, overdue follow-up, deployment,
   recovery and go/no-go. Define acceptable outages and recovery window in writing.

**Go:** every current capability has an accepted disposition; privacy and archival
obligations have owners and approval. **No-go:** required child-accounting or privacy
capabilities remain missing, or retained records would be silently destroyed.

## Gate 1 — complete and rehearse the replacement

Owner: maintainer, independent reviewer and operations tester.

1. Finish required client/backend parity and tests. Teacher prompts alone do not
   implement parent, station, dismissal or complete PDPA workflows.
2. Replay the separate V2 chain into an empty throwaway Postgres 17 database.
   Locally only: shim, `0001_core`, `0002_calendar`, `0003_attendance_rpc`,
   `0004_prompt_scheduler`, then fake seed. Append later accepted migrations;
   never modify historical production migrations or mix both schema chains.
3. Run SQL role/RLS, calendar, concurrency, submission, scheduler and device tests;
   dispatcher/unit tests; mobile-browser E2E; and native router tests. Verify
   Study Space exclusion, no-row attendance, stale mutation rejection, and
   immutable submissions. Test all roles and revoked/replaced teachers.
4. Rehearse a hosted fresh backend separately with its real Auth schema. Never
   install `local/supabase_shim.sql`, `seed/demo_week.sql`, `demo_shift_to_today`,
   demo identity switching or fake device registrations into the real destination.
5. Verify schema before dependent clients; verify OFF flags and non-demo runtime.
   Rehearse restoration into an isolated environment, endpoint rollback, queue
   clearing and reconciliation of records written after a simulated switchover.
6. Record exact source revision, migration hashes, test counts, browser/device
   evidence, restore evidence and unresolved issues. Local tests do not establish
   live state; later authorized live checks must use the protected repository gates.

**Go:** required automated tests pass, representative workflows pass, independent
review passes and recovery is demonstrated. **No-go:** any authorization/privacy
failure, unreliable record mapping, or untested restoration path.

## Gate 2 — prepare the fresh backend with flags OFF

Owner: authorized backend operator, with the production-schema runbook.

1. Provision an intentionally separate Singapore-region backend/Auth environment;
   confirm its identity independently before any operation. Do not repurpose the
   old database or run `supabase db reset` / `db push` against production.
2. Apply only exact reviewed V2 migrations in order through the approved workflow.
   Use hosted Auth, not the local shim. Reload PostgREST after function changes;
   verify schema, grants, RLS, security-invoker views if any, drift and advisors.
3. Keep `teacher_prompts=false`, `teacher_prompt_push=false`, `demo_enabled=false`.
   Verify values from the destination itself, not repository defaults.
4. Provision approved staff identities and reviewed role mappings. Configure new
   term, timetable, holidays/closures, classes, accountable teachers and enrollment
   under the separately approved data-entry/import plan. Review counts and spot
   checks without putting child names in logs.
5. Generate planned lessons and compare timetable, dates, rosters and leads with
   the operational plan. Confirm cancelled lessons have no active prompts and
   Study Space is absent from reports/prompts.
6. Install a reviewed worker wakeup and dedicated invocation secret; the optional
   planning cron alone does not dispatch. Keep real push disabled. Configure APNs
   credentials only in approved secret storage, never source or shared logs.

**Go:** measured schema/security evidence, counts, calendar review and OFF flags
are signed off. **No-go:** prototype/demo endpoints, authentication shortcuts,
unreviewed import, missing roles or unproven least privilege remain.

## Gate 3 — prepare all clients and a human pilot

Owner: web/native/station maintainers and staff testers.

1. Update all dependent clients and endpoint configuration after schema verification.
   Use a compatibility gate/minimum version so old binaries fail closed. An old
   binary must not silently keep writing the previous schema after switchover.
2. Clear old sessions, persisted roster caches and actor-bound offline queues safely.
   Review pending attendance before discarding it; account for unsynced records
   through a supervised reconciliation step. Require fresh login and device
   registration; do not copy parent/old device tokens into teacher registrations.
3. Verify approved universal-link host and associated domains on real phones:
   cold launch, signed out, auth restoration, wrong account, biometric lock,
   duplicate taps, network failure and expired routes. Confirm foreground snooze
   requires a fresh action, including after an account change.
4. Test permissions denied, offline phones, expired/invalid tokens, multiple devices,
   substitute changes, cancellation, quiet-hour crossing, worker crash, stale lease
   acknowledgements and in-flight pushes after submission. A push failure must
   leave the list and submit flow usable.
5. Obtain explicit pilot authorization and flag scope before enabling real operation.
   Enable the shared workflow flag deliberately; enable push separately only after
   real APNs acceptance, privacy and phone QA gates are approved. A local dry-run
   acceptance is not real-device evidence.

**Go:** staff can account for students and finish/recover the review flow; all
clients are compatible and real-device evidence is accepted. **No-go:** completion
relies on push arrival, route login loses work, or unsupported clients can write.

## Gate 4 — switchover and observation

Owner: named cutover lead; explicit go/no-go recorded by Edmund.

1. Announce the agreed maintenance window and paper/operational fallback. Confirm
   current staff know which system is authoritative during each part of the window.
2. Freeze old writes only at the approved switchover. Capture the final approved
   encrypted archive, integrity checks and minimal reconciliation counts. Retain
   the old environment through the agreed recovery window with restricted access.
3. Apply any separately approved final transfer/reconciliation exactly once. Avoid
   blind dual writes: two writable registers cannot both be authoritative.
4. Point compatible clients to the new backend, enforce old-client lockout, require
   reauthentication, and enable approved flags. Check a staff-controlled lesson
   end to end, missing-submission visibility and device-registration ownership.
5. Observe failed submissions, missing lessons, unauthorized access, worker failures,
   token invalidation and overdue backlog. Use aggregate/event-code evidence;
   don't export names, feedback or tokens into monitoring.

**Go:** no unresolved authorization or student-accounting incident; operational
owners accept the observed flow. **No-go/rollback:** missing/wrong rosters,
unauthorized access, broken submission/replay behavior, incompatible clients or
an unrecoverable backend fault. A push-only outage may justify disabling push and
using the list while the lead assesses whether the workflow itself remains safe.

## Rollback before old-database disposal

1. The cutover lead declares rollback; disable new prompt dispatch and freeze new
   mutations so the reconciliation boundary is explicit. Record the time and
   revision boundary without copying personal data into incident logs.
2. Preserve new records/receipts securely. Compare against the last old-system
   snapshot and capture the minimal authorized difference. Never blindly replay
   attendance mutations or reconcile by names.
3. Restore/re-enable the retained old environment only after its health and access
   checks. Restore compatible clients/endpoints and require login; clear new queues
   so they cannot replay into the old backend.
4. Reconcile post-cutover attendance through a reviewed mapping/manual process
   with staff sign-off. Mark which system is authoritative and use paper fallback
   until every child/lesson is accounted for. Keep evidence for rescheduling cutover.

Rollback is not a reverse V2 migration against the old schema. Local prototype
rollback is simply reset/reseed of the assigned throwaway DB. A live rollback is
possible only while the old environment or a tested restorable archive remains.

## Gate 5 — close the recovery window and dispose deliberately

Only after stable operation, reconciliation, approved retention and explicit final
authorization may the old database be dropped. Decide archive retention, restore
access, device/token disposal and deletion evidence with the DPO. Destroying the
old environment removes the direct rollback option; rebuilding from an archive is
a separately tested recovery operation, not an instant fallback. Do not equate
“new year” with permission to erase children's historical records.

## Evidence still required

No live backend, cutover, archive, real login, APNs, associated-domain or physical
phone verification was performed by Pass E. All live gates above remain open.
The supervisor owns root release notes and human-only follow-ups; this pass edits
only its assigned documentation and local runner.
