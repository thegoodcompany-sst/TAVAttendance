# Teacher prompt routing sketch

Pass D implements [contract §10](../CONTRACT.md) within this directory only. It is
not linked into the shipping app. No database, credential file, remote API, or APNs
was used. Shared rollout flags remain a future integration concern and default OFF.
The earlier email proposal in the research is superseded by this contract.

## Files and boundaries

- `Package.swift`, `Sources/PromptRouter/PromptRouter.swift`: dependency-free SwiftPM
  library, importing Foundation only. Strict parsing and a synchronous state machine;
  injected persistence, clock values, and request ID generator; no networking or writes
  to attendance. Call from a single executor (MainActor in the sketch).
- `Sources/PromptRouter/PromptStrings.swift`: all native stand-in copy for Edmund.
- `Tests/PromptRouterTests/PromptRouterTests.swift`: 34 XCTest methods, including two
  manifest-driven tests covering 34 URLs and 28 notification payload/action cases.
- `Tests/PromptRouterTests/Fixtures/routes-v1.json`: shared, fake-only wire fixtures.
  `prompts.example.test` is an example allowlist entry, not a deployment destination.
- `check_fixtures.py`: offline Python sanity check of all 62 fixture cases.
- `Checks/shared-fixtures.test.ts`: 40 offline checks against the actual pure web
  `pendingPath` and dispatcher `buildPromptPayload` modules, using that same manifest.
- `Sketch/TeacherPushRegistration.swift`: gated permission/token registration,
  account-bound `register_device`/`revoke_device` service, serialized token rotation,
  and synchronous local cleanup before best-effort sign-out revocation.
- `Sketch/TeacherNotificationDelegate.swift`: notification categories/delegate,
  atomic protected-file persistence, auth/unlock coordinator, explicit snooze
  confirmation seam, and outstanding-count badge refresh. These files are outside
  the SwiftPM target and guarded with `canImport`.
- `Sketch/TeacherPromptDemo.swift`: concrete in-memory registrar/installation doubles
  and a demo factory with system registration disabled; no network transport.

## Routing and persistence

Accepted URLs are exactly `https://<approved-host>/t/lesson/<lowercase-uuid>` and
`tava://teacher/lesson/<lowercase-uuid>`. Configure an exact host allowlist in the app;
there is no default production host. Native routing rejects HTTP (including the local
web demo URL), relative URLs, foreign/suffix hosts, userinfo, ports, queries (even empty),
fragments, encoded characters/separators, extra segments, and noncanonical UUIDs.
Opening a locator makes no external request until auth/profile/flag/unlock gates pass.

The v1 payload accepts only the contract's keys, category, kinds, sound and lesson
thread ID. A Boolean/string version, unknown kind/action, dismiss response, malformed
UUID, extra root/APS/alert key, or wrong category fails closed. Text is not used for
routing or saved. `TAKE_ATTENDANCE` and the OS default tap both navigate;
`SNOOZE_10` can request a visible confirmation after authorized resolution. Neither
receipt nor opening marks attendance, snoozes, or submits a lesson.

| State | Meaning / next step |
|---|---|
| `idle` | No pending navigation; show today's list. |
| `awaitingSignIn` | Finish session restoration, sign-in, and profile loading. |
| `awaitingUnlock` | Finish app biometric/passcode unlock. |
| `resolving(request)` | Call `lesson_for_prompt` with the authenticated, account-bound session. |
| `ready` | The shaped RPC authorized this lesson; present its data for that account. |
| `unavailable(reason)` | Show neutral copy and retry, choose-account, or today's-list controls. |

Role checks are only local gates. The RPC must enforce active profile, flags,
accountability/admin access, and Study Space exclusion every time. A route UUID, a
notification, or a cached role proves no authorization. No student data is persisted
by the router. The host must reject/discard stale fetched projections as well as stale
router completions, and clear its roster and feedback drafts whenever leaving ready.

`PendingRoute` persists lesson UUID, receipt timestamp, action, optional bound account
UUID, and a local route-instance UUID. TTL is exactly 86,400 elapsed seconds from
receipt, never extended by retry or a duplicate response. Dates are absolute instants;
no device-local calendar arithmetic. Negative age (clock rollback/future stored date)
fails closed. Native display dates, if added later, must explicitly use
`TimeZone(identifier: "Asia/Singapore")`; the badge RPC uses Singapore today server-side.

An incoming signed-out navigation locator survives process restart and login. It binds
when received under a known account or first resolved after login. Sign-out preserves
that navigation but strips snooze intent; it clears the sensitive screen, in-flight
resolution, and actor-bound actions immediately. A different account cannot resolve
an already bound pending route: require a fresh external link/action tap (or discard
and open from that account's list). An unbound incoming link can bind to the newly
signed-in account. Relaunch/session expiry also reduces snooze to navigation. The
teacher can explicitly choose snooze again on the authenticated lesson screen.

Resolution consumes pending navigation only on an authorized RPC result and successful
durable persistence. Denial and network failure keep it for explicit retry; expiry
deletes it. A changed gate, account, or new link invalidates an old completion. Once
ready is cleared by lock/sign-out, return to today's list; reopening resolves again.
The package never stores a resolved roster or restorable ready screen.

The latest distinct user-opened link replaces the previous pending link. Repeated
notification responses deduplicate by OS request identifier + normalized action,
including after consumption/restart, for 24 hours. The receipt ledger is bounded to
the newest 32 entries. Entries contain only opaque system identifiers, action and time;
never supply identifiers built from personal data. A new response or explicit URL tap
rechecks RPC authority. This deduplication is convenience, not mutation idempotency.

Use `PromptFilePersistence` in an app-owned Application Support directory protected
and excluded from backups. Keep it separate from `PendingAttendanceStore`; the latter
must continue clearing all attendance mutations on sign-out. Handle load/save errors
with `PromptStrings.storageUnavailable`, never raw errors/data in UI/logs. Corrupt or
unknown-version snapshots are cleared. Do not initialize storage as an empty success
when reading the protected file fails while locked.

## Later XcodeGen integration

Do not apply these changes as part of this sketch. Once the fresh schema and native
integration are separately approved, edit `iOS/project.yml` and regenerate with
XcodeGen; never edit the generated `.xcodeproj`. Add the local package under the
existing `packages` mapping, and its product to the app target's existing dependencies:

```yaml
packages:
  TeacherPromptRouter:
    path: ../docs/teacher-prompts/ios
targets:
  TAVAttendance:
    dependencies:
      - package: TeacherPromptRouter
        product: PromptRouter
```

Move/adapt the sketch files into focused `Core/` and `Services/` files in the real app;
they are deliberately not package sources. Preserve existing parent handling. The
current `PushManager.swift` registers only through the legacy parent path; teacher
callbacks must call the new `register_device` service, never that parent-only RPC.
The app already has an `AppDelegate`; extend it instead of declaring a second one.

1. Create and retain the router/coordinator and notification delegate before auth
   restoration. Merge `TAVA_TEACHER_PROMPT` into existing notification categories at
   launch; both actions use `.foreground` and `.authenticationRequired`. Retain the
   delegate because `UNUserNotificationCenter.delegate` is weak.
2. Forward SwiftUI `.onOpenURL` and browsing-web user activities (including cold-start
   connection options) to `coordinator.open(url:)`. Use one ingress path per OS event
   to avoid starting two resolutions for the same universal-link event.
3. Adapt `AuthManager.listenToAuthChanges`: send `.restoring` initially,
   `.loadingProfile(userID)` during `fetchProfile`, and `.signedIn` only after profile
   and feature flags load. V2 `teacher` is a deliberate migration from legacy `tutor`;
   do not silently grant unknown roles teacher access. Parents/inactive/missing
   profiles are denied. Map sign-in and initial-session events equally.
4. Feed biometric/privacy-lock changes from `TAVAttendanceApp` into `isUnlocked`.
   Keep the existing scene privacy shield. On background, relock and clear sensitive
   presentation; on foreground, refresh expiry and outstanding count. These states
   are part of the coordinator, not inferred from which tab is visible.
5. Implement `TeacherPromptService` in Services. `resolve` calls
   `lesson_for_prompt(p_lesson_id)` and decodes its shaped projection. Keep the result
   tied to the request ID/account; never render a late response for a different route.
   Distinguish denied, network failure, and session expiry. `snooze` calls
   `snooze_prompt(p_lesson_id, p_minutes: 10, p_mutation_id)` only from the visible
   confirmation button, with a fresh UUID and current account. Never queue it offline.
6. Implement a session-bound `TeacherSessionRPC` transport and durable
   `TeacherInstallationStore`. Generate one installation UUID once, persist its
   owner and returned device UUID atomically, and retain ownership across logout.
   Never generate a new installation UUID to bypass foreign-token ownership denial.
   Shared-device ownership transfer is outside the prototype. Recreate an
   account-bound service per session; never mutate its authenticated client identity.
7. Wait for active teacher/admin, `teacher_prompts`, `teacher_prompt_push`, and opt-in
   before requesting permission/registration. Real device integration is OFF by
   default; demo supplies fake services and never calls APNs. Forward APNs success
   and failure from existing AppDelegate methods. Tokens remain in memory and are
   never logged. Read the signed entitlement to select environment; do not use DEBUG.
8. At the synchronous start of sign-out, update the coordinator to signed out, clear
   roster/drafts/actions, and call `beginSignOut()` to clear local tokens/device ID.
   Await its best-effort revocation task before ending authentication; bound network
   calls with timeouts so an outage cannot strand sign-out. Also revoke on opt-out
   while the owner session is available. Retain the existing attendance-queue cleanup.
9. Permission denial and transport failure offer today's lessons. `foreground()`
   calls `my_lessons_today()` without a date override and sets badge from
   `outstanding_count`; receiving a push never provides the count or navigates. Wire
   this refresh after mutations too. Clear any old badge on sign-out. Push is optional;
   today's list/backlog remains the source of truth.

The transport protocols are intentionally unimplemented networking seams. There is
no real session adapter, native lesson screen, or automatic production integration here.
Cancelling a task cannot retract an RPC already in flight; use the original account's
session and server authorization/idempotency, and ignore late UI results.

## Entitlements and device QA (unrun)

The current project intentionally omits APNs entitlements. A later release needs a
paid team/profile with Push Notifications and Associated Domains capabilities. In the
XcodeGen-managed entitlements, set `aps-environment` to the correct signed environment
(`development` maps to sandbox, `production` to production) and
`com.apple.developer.associated-domains` to `applinks:<approved-host>`. Configure
`CFBundleURLTypes` with the `tava` scheme in the generated Info.plist inputs. Custom
schemes are not exclusive to an app and confer no trust/authorization.

The approved HTTPS host must serve an `apple-app-site-association` file naming the
correct team/bundle app identifier and limiting paths to `/t/lesson/*`. Choose the
actual host later; the fixture host and local HTTP demo are not associated domains.
Use the same approved host list in the router. No real host or Apple service was
contacted for this pass.

Real-device release QA remains unrun: provisioning and both APNs environments;
permission allow/deny/settings changes; token refresh/reinstall; category actions and
device authentication; foreground/background/terminated delivery; cold universal and
custom links; associated-domain verification; auth/profile delay and biometric lock;
account switching and sign-out revocation failure; revoked teacher authority; snooze
confirmation and expiry; multiple devices; badge/backlog refresh; offline/error paths.
Simulator payload injection can help exercise routing later but cannot prove APNs
delivery, signed entitlement correctness, or real associated-domain behavior.

## Verification evidence

Run from the repository root unless a directory change is shown:

```sh
swift test --package-path docs/teacher-prompts/ios
python3 docs/teacher-prompts/ios/check_fixtures.py
cd docs/teacher-prompts/ios
bun --no-env-file test ./Checks/shared-fixtures.test.ts
```

This Linux box has no Swift executable (`swift: command not found`). The 34 XCTest
methods are **unrun**, not passed; neither package compilation nor Apple sketch
compilation has been established. Python: **62 passed, 0 failed**. Bun parity check:
**40 passed, 0 failed** against the pure web/dispatcher modules available during this
pass. These checks neither compile Swift nor prove auth/RLS/device behavior. They
read no environment files and use no database or network. The fixture parity check
normalizes only the approved literal native prefixes into web-relative paths; it does
not decode or sanitize malformed input. Web intentionally accepts a relative next
path and clears it on explicit sign-out, unlike native's persisted navigation.

No root release/human-follow-up documents were edited because the task limits
ownership to this directory. The supervisor owns integration and those records.

## Android handoff

```markdown
You are porting the teacher prompt routing sketch to the Android app in `Android/`
after a separately authorized review. Keep the current pass's local-only safety rules.

## Feature summary
Strict lesson links/v1 push actions, auth/profile/unlock-gated resolution, 24h pending
navigation with account binding, stale-response rejection, explicit snooze confirmation.

## iOS files changed
- docs/teacher-prompts/ios/Sources/PromptRouter/PromptRouter.swift — pure policy.
- docs/teacher-prompts/ios/Sources/PromptRouter/PromptStrings.swift — stand-in copy.
- docs/teacher-prompts/ios/Sketch/ — notification and registration integration seams.

## Android targets
- Android/app/src/main/java/com/example/tavattendance/push/ — teacher routing/actions.
- Android/app/src/main/java/com/example/tavattendance/auth/ — auth/account transitions.
- Android/app/src/main/java/com/example/tavattendance/data/service/ — shaped RPC calls.
- Android unit tests — reuse the JSON fixtures; no real FCM sends.

## New Supabase schema (must be consumed by Android)
None added by Pass D. Consume CONTRACT.md v2 lesson_for_prompt, snooze_prompt,
my_lessons_today. Device registration in v2 currently specifies APNs environments;
FCM transport/token schema is a supervisor decision, not implied by this sketch.

## Sample test to write
openSnooze(accountA); signOut(); signIn(accountB)
assert(noSnoozeSent && pending.action == TAKE_ATTENDANCE)
assert(state == unavailableAccountMismatch)
freshTap(); resolveWithAuthorizedRPC(accountB); assert(visibleConfirmationRequired)
Complete an old account-A request; assert(noAccountADataRendered).

Implement only the subsequently assigned scope using Kotlin/Compose patterns.
Do not change shared Supabase migrations or invoke production services.
```

## Web handoff

```markdown
You are aligning the teacher prompt web prototype in `prototypes/teacher-prompts/`.
Keep the current pass's assigned paths/database and local-only safety rules.

## Feature summary
Share strict lesson UUID/path and generic payload fixtures with the iOS sketch.
Keep web's contract-specific cookie lifecycle: 24h TTL, explicit sign-out clears it,
wrong identity/network failure preserves it for retry, consume after authorized RPC.

## iOS files changed
- docs/teacher-prompts/ios/Tests/PromptRouterTests/Fixtures/routes-v1.json — shared cases.
- docs/teacher-prompts/ios/Checks/shared-fixtures.test.ts — pure web/dispatcher parity.
- docs/teacher-prompts/ios/Sources/PromptRouter/PromptRouter.swift — native policy.

## Web targets
- prototypes/teacher-prompts/lib/identity.ts and tests/identity.test.ts — next validation.
- prototypes/teacher-prompts/lib/queries/lessons.ts — shaped authorized reads.
- prototypes/teacher-prompts/app/actions/lessons.ts — explicit snooze confirmation.
- prototypes/teacher-prompts/e2e/authorization.spec.ts — auth return and stale data.

## New Supabase schema (must be consumed by Web)
None added by Pass D. Consume CONTRACT.md v2 lesson_for_prompt, snooze_prompt,
my_lessons_today. The notification payload/category/action IDs remain unchanged.

## Sample test to write
Read the shared manifest; convert only approved literal native origins/scheme to
relative /t/lesson paths. Reject encoded separators, query/fragment, malformed UUIDs.
Open signed-out lesson; choose wrong teacher; assert neutral denial and no roster.
Choose authorized teacher; resolve again; assert route consumed only on success.
No automatic snooze/submit on notification open; confirmation creates a fresh UUID.

Implement only the assigned scope; retain query/server-action seams and DB authority.
Do not change shared Supabase migrations or invoke production services.
```
