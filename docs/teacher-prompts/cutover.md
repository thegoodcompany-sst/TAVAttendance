# Fresh database cutover: January 2027 target

The target is a fresh Convex deployment for the new-year backend. The current Supabase system continues serving existing clients pending an authorized switchover. This plan covers a future production release. The verified dev workflow and client contract are documented in [CONVEX.md](CONVEX.md) and [CONVEX_API.md](CONVEX_API.md).

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

## Gate 1 — rehearse on a separate deployment

Run `npm ci && npm run typecheck && npx vitest run` in `backend/` at the reviewed revision. Rehearse activation, refresh, all lesson RPCs, missing submissions, moved lessons, permission changes, token rotation and dry-run delivery with invented data. Verify export and restoration into an isolated deployment. Review access to backups and the decision for each legacy workflow with the operations lead. The archived PostgreSQL prototype remains available for comparison.

## Gate 2 — install the reviewed production backend

The authorized deployer selects the intended Convex project, production region and plan with the centre, records the expected HTTPS cloud/site hosts, and injects its **production deploy key** as `CONVEX_DEPLOY_KEY` through secret storage. Use a clean checkout of the approved revision. Keep all signing material outside source control and shell history.

Convex Auth 2.1 uses each deployment’s own ES256 signing key. Omit the v1 RSA key bootstrap on first install and subsequent releases. Use a fresh deployment for this cutover. If the target already holds v1 credentials or profiles, stop here and rehearse their migration first.

```sh
cd backend
npm ci
npm run typecheck
npx vitest run
printf '%s' true | npx convex env set APNS_DRY_RUN
npx convex deploy
npx convex run settings:initialize '{}'
```

The platform supplies `CONVEX_CLOUD_URL`. Verify that the expected cloud host serves a public EC key without printing the key material. Using the pilot login, verify the access token works for the intended staff UUID, refresh rotates it, and sign-out revokes both refresh and profile access. The provider accepts issuer `<cloud origin>/components/auth` and audience `convex-auth`. Retire legacy `JWT_PRIVATE_KEY` and `JWKS` settings after a verified v1 cutover. Deployment registers the daily calendar and minute dispatch crons automatically. Verify the actual production function inventory, both crons, issuer/JWKS discovery, OFF flags and `demoEnabled=false` at the destination. Query only the operational settings:

```sh
npx convex run --inline-query 'return {flags:(await ctx.db.query("feature_flags").collect()).map(f=>({key:f.key,enabled:f.enabled})),demo:(await ctx.db.query("runtime_settings").first()).demoEnabled}'
```

Provision the approved staff profiles, classes, dates, rules, exceptions and enrolments. Run `npx convex run calendar:generate_lessons '{}'` and reconcile counts, accountable teachers, actual dates and roster snapshots. Verify staff access with the approved pilot account, including denial for a replaced teacher. Retain only redacted verification evidence.

For a later physical-device pilot, configure `APNS_KEY_P8`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_BUNDLE_ID` and `APNS_ENV` in the deployment's secret settings. For a secret-manager pipe, `npx convex env set APNS_KEY_P8` accepts the value on stdin. Keep `APNS_DRY_RUN=true` until real sending is approved. Real sending requires explicit approval of the master and push flags, the matching APNs environment and the dry-run setting. Keep the master OFF until the agreed pilot or switchover.

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

Dev verification covers real password activation, sign-in, token refresh, the teacher API, registration and an accepted dry-run delivery. Production deployment, approved client migration, real-device receipt, data restoration, archive reconciliation and operational sign-off remain human release gates. The code-gated SQL preview uses invented identities and has a separate [preview guide](preview-deploy.md).
