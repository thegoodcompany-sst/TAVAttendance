# Teacher prompts in the iOS app

The Foundation-only `PromptRouter` package is now linked into the real
`iOS/TAVAttendance` app and `TAVLayoutLab` through `iOS/project.yml`. The original
`Sketch/` files remain historical examples, outside every app/package source target.
The app adapters live in `Core/TeacherPromptCoordinator.swift` and
`Core/TeacherPromptNotifications.swift`; there is only one router implementation.
No remote database/API, credentials, deployment or real APNs was used for this work.

## Rollout and compatibility

`TEACHER_PROMPTS_V2_ENABLED=NO` is the build-time master, including Release/TestFlight.
When OFF, no teacher RPC, category registration, permission request or teacher UI is
activated. The legacy profile decoder and parent push registration stay in place.
The v2 role `teacher` never falls through to parent `register_device_token`.

With the master ON, `FeatureFlagStore` reads `teacher_prompts` and
`teacher_prompt_push`; missing keys and failed refreshes turn these keys OFF.
`TeacherPromptsGate` requires an explicitly active teacher/admin profile for the
workflow, plus both flags, account-specific opt-in and non-demo mode for APNs.
The list remains usable with push OFF or permission denied. Runtime flag/profile
removal still permits owner-bound installation revocation; a master-OFF binary
never invokes any v2 RPC, including cleanup.

A Debug build can use `TEACHER_PROMPTS_V2_ENABLED=YES` for a separately authorized
v2 backend. This is a **fresh-schema client**, not a dual-write bridge to the current
production schema. The master switches Auth's profile projection to
`id,display_name,role,active`; legacy `tutor` is not silently upgraded to `teacher`.
When the workflow gate is ON, teacher/admin entry presents My lessons instead of
legacy class/kiosk screens, whose RPCs are incompatible with v2. The rest of the
cutover/parity work remains in [cutover.md](../cutover.md).

For an entirely offline review, launch a Debug app with `--teacher-prompts-demo`.
It enables DemoMode before Auth transport starts, opens the gated teacher area with
invented `Demo Student 01` names and injects a memory-only service. Add
`--teacher-prompts-dark` for dark screenshots. Both arguments are ignored in Release;
they do not enable real APNs. The screenshot launch uses ephemeral route storage,
so unsigned simulator runs do not depend on Keychain capabilities or real pending links. Demo workflow is also available when ordinary DemoMode
is entered in a master-enabled build. Its push flag remains OFF.

## Routing, notifications and account boundaries

The package validates canonical `tava://teacher/lesson/<lowercase-uuid>` and
`https://<approved-host>/t/lesson/<lowercase-uuid>`. `tava` is registered in generated
Info.plist. `TEACHER_PROMPTS_APPROVED_HOSTS` is empty until a human approves a host;
fixture `prompts.example.test` is not a real deployment destination. `.onOpenURL`
and browsing-web user activities feed the same router. Associated Domains/AASA and
signed APNs entitlements remain TODOs in `HUMANS.md` §89; none were added here.

The retained AppDelegate notification delegate accepts the exact dispatcher payload:
`aps`, integer `v=1`, `type=teacher_prompt`, `lesson_id`, and `kind`.
`heads_up`, `attendance`, `follow_up`, `final` all use `TAVA_TEACHER_PROMPT`.
`TAKE_ATTENDANCE` and `SNOOZE_10` both require foreground + authentication.
Default tap navigates. Snooze only requests a visible confirmation; a fresh button
tap calls `snooze_prompt(p_lesson_id,p_minutes:10,p_mutation_id:<fresh UUID>)`.
`can_snooze=false`, `TP_SNOOZE_LIMIT` and `TP_NO_PENDING_PROMPT` disable the action.
No background snooze or offline mutation queue exists.

Pending navigation and the bounded response-ID/action dedupe ledger use the package's
persistence protocol with device-only, when-unlocked Keychain storage. They contain
locators/account UUIDs/timestamps only, never rosters, notes, auth or device tokens.
The TTL is 24 hours from receipt, never renewed by retries. A signed-out locator
survives launch/login; authorization and durable consumption must succeed first.
Sign-out/account switch strips snooze intent. An account-bound route cannot resume
under another account without a fresh tap. Auth loading, locks, flag changes and
sign-out clear sensitive presentation/drafts and invalidate stale async completions.
Automatic sheet dismissal on those transitions does not discard pending navigation.

The package's `TeacherPushRegistrationLifecycle` serializes register/revoke/re-opt-in.
A durable installation UUID, original owner and optional device UUID live in a separate
Keychain document; ownership survives sign-out and is never reassigned to evade denial.
Opt-in is per-account UserDefaults metadata. Tokens stay in memory only.
`register_device` and `unregister_device(p_installation_id)` use the existing Supabase
configuration with an immutable PostgREST request client. Same-account refreshed Auth
sessions may supply a fresh snapshot before a request; an in-flight request never
adopts another account. Revocation runs before Auth ends, with at most three attempts
and a ten-second transport bound per attempt, plus one-/two-second delays. A failed
revocation surfaces fallback copy and retains recovery state; it cannot guarantee
server cleanup offline. Foreground recovery retries pending revocation.

`TEACHER_PROMPTS_APNS_ENVIRONMENT` must match the eventual signed `aps-environment`
(`development` → sandbox; `production` → production). It is empty by default, which
prevents permission/APNs registration. Never infer environment from DEBUG. An absent
environment still permits revoking an installation registered by an earlier build.

Foreground teacher notifications use banner + list and never navigate or mutate.
Foreground/list refresh calls `my_lessons_today()` with no date override and sets the
badge from `outstanding_count`, including backlog. A successful submit removes that
lesson's delivered notifications by category/thread/lesson ID, refreshes the badge
and suppresses further local handling for known submitted lessons. The list also
cleans up submissions learned from another device. In-flight APNs deliveries remain
best effort; every newly opened lesson is resolved against server authority.

## Attendance and copy

The real SwiftUI views are in `Views/TeacherPrompts/`; DTOs are in
`Models/TeacherPromptModels.swift`, RPCs behind `TeacherPromptServing` in
`Services/TeacherPromptService.swift`, and demo behavior in
`Demo/DemoTeacherPromptService.swift`. No view queries Supabase.

All present stages an in-memory preview, filling only unmarked students and preserving
late/absent/informed marks. **Confirm and submit** with no adjustments calls
`confirm_all_present_and_submit` once with both observed revisions and one mutation UUID,
matching prototype revision 1.1. It performs no earlier `mark_all_present` write.
If the teacher adjusts the preview, confirmation calls `mark_attendance` for each changed
student in roster order, then `submit_lesson`. Each receipt supplies the next revision;
network retry resumes at the failed step with exactly the same mutation and arguments.
Successful rows are not sent again. A conflict stops the sequence, discards the preview,
and reloads authoritative attendance while retaining notes. Partial adjusted writes can
remain saved after failure; no submission is recorded until the final RPC succeeds.
Outside this preview, individual mark/clear still writes immediately; ordinary Submit
never fills missing rows. Optional lesson-only notes use `save_feedback`.
Revisions remain decimal strings; observed server timestamps preserve microseconds,
and required nullable RPC parameters encode JSON null. Notes are bounded to 1000
Unicode scalars and remain in memory only. Submit is disabled while notes are unsaved.
Network failures keep the screen. Explicit retry reuses the same attendance/feedback/
submit mutation and captured arguments; conflicts reload and retain the notes draft.
Snooze is never queued or automatically retried. Server denials clear sensitive data.
The new screens use blue/teal/indigo/neutral styles, Dynamic Type and labeled controls.
All native copy is centralized in `PromptStrings.swift` and inventoried in
[strings.md](../strings.md), pending Edmund's approval.

**Remaining integration differences:** Keychain replaces the sketch's protected file. The APNs environment is an explicit build value to be
matched to future provisioning. Native integration is real but ships OFF; there is
no fresh-backend cutover or Apple capability change in this work.

## Verification

Run on Linux with the supplied Swift toolchain:

```sh
export LD_LIBRARY_PATH=/workspace/tav-ios-build/compat
export PATH=/workspace/tav-ios-build/swift-6.1.2-RELEASE-ubuntu24.04/usr/bin:$PATH
swift test --package-path docs/teacher-prompts/ios
python3 docs/teacher-prompts/ios/check_fixtures.py
(cd docs/teacher-prompts/ios && bun --no-env-file test Checks)
```

Pass 2: package **42 passed / 0 failed**; Python fixtures **69 / 0**; Bun parity
**47 / 0**. Syntax parsing covers every changed/new Swift file. Twenty app XCTest
methods passed in a temporary Linux domain harness with Apple/Supabase adapters
stubbed, covering both submit branches, exact lost-response replay, partial conflicts,
sign-out between writes, notes/clear gating and demo routing with failed device storage.
This is **not** an iOS build or native runtime verification. The supplied pass-1 macos-15
CI result was 107 passing unit tests (14 teacher-prompt tests); pass-2 native tests and
screenshots require a fresh macOS run. `/tmp/gitleaks dir . --config .gitleaks.toml
--redact=100` passed with no leaks; no global scanner rules were changed.

`TeacherPromptScreenshotTests` launches the real app in Debug demo mode and retains
six attachments per appearance: lessons list, attendance before, after All present,
snooze confirmation, after snooze, and submitted. Light and dark run as independent
cases, with navigation/readiness predicates and bounded list scrolling. The separate optional `ios-screenshots` CI job runs only
those tests with `TAVAttendanceLayout`, exports xcresult attachments and uploads the
result bundle. It uses placeholders, no secrets, and cannot block CI.

CI screenshot diagnosis: the exported hierarchy `280DC39B-C42E-4C34-9C38-9A8F090C643E.txt`
remained on My lessons with `PromptStrings.storageUnavailable` (“Open the lesson link
again.”), proving a route-storage failure before navigation, not an offscreen All present
button. The attachments do not include the underlying Keychain status. The working tree
already contained a late pass-1 launch-time ephemeral-store bypass; pass 2 additionally
selects ephemeral routing on entry into demo state, rebuilds a failed router, and tests
that transition using an explicitly failing device store. Production persistence still
fails closed. A new native screenshot run is required to confirm the CI symptom is gone.

XcodeGen was run with the supplied Linux 2.44.1 binary. Demo file re-IDs are expected.
A pre-existing spec/project Supabase minimum mismatch was aligned to the existing
2.55.2 requirement; generated random Config references were normalized minimally.
`Package.resolved` pins and existing schemes remain unchanged.

Before release: complete `HUMANS.md` §89 for real SDK/XCTest/screenshots, accessibility,
permission allow/deny/settings, token rotation, paid-team provisioning, both APNs
environments, terminated/background/foreground responses, device authentication,
real login/profile delays, locks, links/AASA, account switches, offline revocation,
multiple devices and badge/backlog. None of those are proved by a Linux harness.

## Android handoff

```markdown
You are porting the gated iOS teacher-prompt flow to Android/ in a separate review.

## Feature summary
Master OFF + shared workflow/push flags; authenticated My lessons/backlog; explicit
snooze confirmation; preserve existing marks with All present, adjust, submit;
account-bound navigation/retries and device opt-out. Push is optional.

## iOS files changed
- iOS/TAVAttendance/Core/TeacherPromptCoordinator.swift — route/auth/lock lifecycle.
- iOS/TAVAttendance/Core/TeacherPromptNotifications.swift — device/action boundary.
- iOS/TAVAttendance/Services/TeacherPromptService.swift — exact v2 RPCs.
- iOS/TAVAttendance/Views/TeacherPrompts/ — review model and SwiftUI screens.
- docs/teacher-prompts/ios/Sources/PromptRouter/ — shared policy/copy/fixtures.

## Android targets
- Android/app/src/main/java/com/example/tavattendance/data/service/
- Android/app/src/main/java/com/example/tavattendance/auth/ and push/
- Android/app/src/main/java/com/example/tavattendance/screens/

## New Supabase schema (must be consumed by Android)
No SQL changes in this pass. Consume the separate v2 chain's lesson_for_prompt,
my_lessons_today, confirm_all_present_and_submit, mark_attendance, save_feedback, submit_lesson,
snooze_prompt and unregister_device. APNs register_device is not an FCM contract;
FCM schema/transport remains a separately reviewed decision. Never dual-write v1/v2.

## Sample test to write
allPresent(); submit(); assert(oneAtomicConfirmation && existingLateAndInformedAbsencePreserved)
allPresent(); adjustLate(); submit(); assert(perStudentMarksThenSubmit)
submitNetworkFailure(); retry(); assert(sameMutationAndRevisions)
snoozeTap(A); signOut(); signIn(B); assert(noWrite && requiresFreshRoute)
submitSuccess(); assert(deliveredLessonAlertsRemoved && badgeRefreshed)
gateOff(); openPush(); assert(noV2Calls)

Match Kotlin/Compose patterns. Reuse shared JSON route fixtures. Keep new UI neutral/
blue/teal/indigo; all copy pending Edmund. Do not change shared SQL or deploy.
```

## Web handoff

```markdown
You are porting the gated teacher-prompt flow to web/ in a separate review.
Read web/AGENTS.md first; prototypes/teacher-prompts is a reference, not production auth.

## Feature summary
Shared flags OFF, real authenticated My lessons/backlog, online review with revision
CAS, optional bounded notes, explicit snooze and submit; push is a convenience.

## iOS files changed
- iOS/TAVAttendance/Services/TeacherPromptService.swift — RPC names/parameters.
- iOS/TAVAttendance/Views/TeacherPrompts/TeacherLessonModel.swift — mutation/retry policy.
- docs/teacher-prompts/ios/Tests/PromptRouterTests/Fixtures/ — canonical route/action cases.

## Web targets
- web/lib/queries/ — shaped lessons/backlog/detail reads.
- web/app/actions/ — mark/feedback/submit/snooze writes.
- web/app/ — authenticated review UI and route/error regression tests.

## New Supabase schema (must be consumed by Web)
No new SQL here. Consume the existing separate v2 RPC contract; keep schema-first
cutover gating and Study Space exclusion. Do not wire demo identity selection into real auth.

## Sample test to write
unsignedLessonLink(); authenticate(); assert(authorizedLessonBeforeDashboard)
allPresent(); submit(); assert(oneAtomicConfirmation && stopsPrompts)
allPresent(); adjustLate(); submit(); assert(perStudentMarksThenSubmit && receiptRevisions)
conflict(); assert(freshRegister && notesDraftRetained)
snoozeLimit(); assert(disabledButton)
gateOff(); assert(noV2Calls)

Keep web's explicit-sign-out cookie rule (clears route), unlike native's locator
retention. Use established query/action seams; no SQL changes or deployment.
```
