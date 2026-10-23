# Android porting notes

The Android app mirrors the iOS feature set. When an iOS feature lands, port it
here. Do **not** change Supabase migrations — they are shared across platforms.

## iOS → Android file mapping

| iOS file | Android equivalent |
|---|---|
| `Models/Models.swift` | `data/models/Models.kt` |
| `Services/AttendanceService*.swift` | `data/service/AttendanceService.kt` + domain data sources |
| `Services/FeatureFlags.swift` | `data/service/FeatureFlags.kt` |
| `Services/Analytics.swift` | `core/Analytics.kt` |
| `Views/Kiosk/GlobalKioskView.swift` | `screens/kiosk/GlobalKioskScreen.kt` |
| `Views/Parent/ParentDashboardView.swift` | `screens/ParentDashboardScreen.kt` |
| `Views/Kiosk/QRScannerView.swift` | `screens/kiosk/QrScannerSheet.kt` |
| `Views/Session/StudentProfileView.swift` | `screens/StudentProfileSheet.kt` |
| `Views/Session/RosterView.swift` | `screens/RosterScreen.kt` |
| `Views/Session/SessionListView.swift` | `screens/SessionListScreen.kt` |
| `Views/Session/RetrospectiveSessionView.swift` | `screens/RetrospectiveSessionScreen.kt` |
| `Views/Admin/ClassFormView.swift` | `screens/ClassFormDialog.kt` |
| `Views/Admin/StudentManagementView.swift` | `screens/StudentManagementScreen.kt` |
| `Views/Admin/StudentFormView.swift` | `screens/StudentFormDialog.kt` |
| `Views/Admin/TutorAssignmentView.swift` | `screens/TutorAssignmentScreen.kt` |

Base package: `app/src/main/java/com/example/tavattendance/`.

## Paste-ready port handoff template

After an iOS feature changes, agents must emit separate Android and Web handoff
blocks. The user pastes each block into a fresh agent session; do not spawn the
porting agents automatically.

```markdown
You are porting iOS feature changes to the Android app at
/Users/limboenedmund/Documents/apps/TAVA/TAVAttendance/Android/

## Feature summary
[What was built and why.]

## iOS files changed
- `iOS/TAVAttendance/[path]` — [purpose]

## Android targets
- `Android/app/src/main/java/com/example/tavattendance/[path]` — [purpose]

## New Supabase schema (must be consumed by Android)
- [Columns, RPCs, or Storage buckets; write "None" when unchanged.]

## Sample test to write
[Equivalent iOS XCTest expressed as pseudo-Kotlin.]

Implement all changes. Match existing Kotlin/Compose patterns in the repo.
Do not change Supabase migration files; they are shared.
```

For the Web block, replace the destination and targets with the corresponding
`web/` query, action, component, and test files. Preserve the same feature,
schema, and test sections.

## Conventions

- Models are `@Serializable` with `@SerialName` for snake_case DB columns.
- Supabase access stays in `data/service`; use the existing domain data source
  or an `AttendanceService` method rather than querying from a composable.
- Feature flags (`feature_flags` table, migration 012) are read via
  `FeatureFlags.load()` / `FeatureFlags.isEnabled(key)`. Flags ship OFF.
- Release builds are minified — add R8 keep rules to `app/proguard-rules.pro` for any
  new serialized class or reflective SDK.

## Push notifications (PROD-02, flag `push_notifications`) — shipped dark 2026-07-13

FCM only (iOS/APNs stays in the edge function, unwired client-side). Pieces:

- `push/PushTokenRegistrar.kt` — upserts the FCM token into `device_tokens`
  after sign-in and on token rotation; no-op while the flag is OFF.
- `push/TavaMessagingService.kt` — shows late/absent/dismissal pushes from the
  `notify-parent` edge function; tapping lands the parent on the dashboard.
- `ParentDashboardScreen.kt` — requests POST_NOTIFICATIONS (API 33+) when the
  flag is ON, and shows a "Mark safely home" card for today's unconfirmed
  dismissals (`mark_safely_home` RPC, migration 030).

`app/google-services.json` is **gitignored** (same treatment as
`secrets.properties`). Fetch it once per checkout:

```bash
firebase apps:sdkconfig ANDROID 1:879371219921:android:dc7a8dbf4d8df141bf66f0 \
  --project tavattendance-5a80e -o app/google-services.json
```

The build fails at the `google-services` plugin step until the file exists.

## NFC arrival station is not an Android port

NFC sign-in is a Linux appliance in `station/`, not a phone kiosk. iOS and
Android only fail closed when `profiles.role` is `arrival_station`. Do not add
an NFC reader to the Android kiosk. Do not treat this as an iOS-to-Android
handoff.

## Known parity gaps (follow-ups)

These iOS items are ported at the data/service layer but still need Compose UI:

- Kiosk UX: auto-refresh (UX-01), search (UX-02), bulk-action confirm (UX-03),
  absent-tap confirm (UX-04), Not-Here-Yet/Absent info (UX-07),
  photo display (PROD-04).
- Parent portal (PROD-01) ported 2026-07-12.
- Kiosk QR sign-in (flag `qr_sign_in`) ported 2026-07-12 (CameraX + ML Kit,
  `QrScannerSheet.kt`). Session notes (flag `session_notes`) ported 2026-07-12.

## September 2026 attendance fix validation handoffs

The Android parity fixes are already included. These blocks retain the separate
platform review step before a release.

```markdown
You are verifying iOS attendance-fix parity in the Android app at
/Users/limboenedmund/Documents/apps/TAVA/TAVAttendance/Android/

## Feature summary
Online saves return the exact server marked_at used for later offline CAS.
Queue corrections retain their original observation. Saves and sync serialize;
End Class cannot overlap a save. Permanent server rejections do not queue.
The implementation is present; verify it before release.

## iOS files changed
- iOS/TAVAttendance/Models/Models.swift preserves exact timestamp receipts.
- iOS/TAVAttendance/Core/PendingAttendanceStore.swift persists raw observations.
- iOS/TAVAttendance/Services/AttendanceService+SessionsAttendance.swift returns receipts.
- iOS/TAVAttendance/Views/Session/RosterView.swift updates snapshots and syncs all owned sessions.

## Android targets
- Android/app/src/main/java/com/example/tavattendance/data/service/SessionAttendanceDataSource.kt
- Android/app/src/main/java/com/example/tavattendance/data/store/PendingAttendanceStore.kt
- Android/app/src/main/java/com/example/tavattendance/screens/RosterScreen.kt
- Android/app/src/test/java/com/example/tavattendance/PendingAttendanceStoreTest.kt

## New Supabase schema (must be consumed by Android)
Migration 060 makes existing sync_attendance observed_marked_at comparisons
atomic. The existing RPC signatures remain compatible. No new RPC call needed.

## Sample test to write
Mark online, queue a correction with the returned microsecond timestamp,
persist/reload, sync, and verify the correction saves. Repeat with a competing
server update and verify skipped_conflict preserves that update.

Match existing Kotlin/Compose patterns. Do not change shared migration files.
```

```markdown
You are verifying iOS attendance-fix parity in the Web app at
/Users/limboenedmund/Documents/apps/TAVA/TAVAttendance/web/

## Feature summary
Native queues preserve exact acknowledged server timestamps and use atomic
observed-state CAS. Web attendance stays online-only; do not add a browser
queue. Verify web corrections remain authoritative when a native device syncs.

## iOS files changed
- iOS/TAVAttendance/Models/Models.swift preserves exact timestamp receipts.
- iOS/TAVAttendance/Core/PendingAttendanceStore.swift persists raw observations.
- iOS/TAVAttendance/Services/AttendanceService+SessionsAttendance.swift sends observations.
- iOS/TAVAttendance/Views/Session/RosterView.swift serializes saves and sync.

## Web targets
- web/app/actions/mobile.ts
- web/lib/mobile-queries.ts

## New Supabase schema (must be consumed by Web)
Migration 060 changes existing sync/clear internals. No new web RPC or column
is required. Preserve online server authorization and Study Space exclusions.

## Sample test to write
A native device queues an absent mark from timestamp A. Web marks late and
receives timestamp B. Native reconnect reports skipped_conflict and web still
shows late. Run with synthetic students in the release environment.

Match existing query/action boundaries. Do not change shared migration files.
```


## September 2026 adaptive login and PIN handoffs

### Android

```markdown
You are porting iOS feature changes to the Android app at
/Users/limboenedmund/Documents/apps/TAVA/TAVAttendance/Android/

## Feature summary
Keep login and kiosk PIN actions reachable in short, narrow, folded and
large-text layouts. Preserve entered values across geometry changes. iOS now
uses scrollable login/PIN content and width-adaptive keypad buttons. Follow
Android's existing IME behavior; do not blindly change its submit semantics.

## iOS files changed
- iOS/TAVAttendance/Views/Auth/LoginView.swift — scrolling and focus navigation.
- iOS/TAVAttendance/Views/Kiosk/KioskPINViews.swift — scrolling and flexible keypad.
- iOS/TAVAttendanceUITests/AdaptiveLoginTests.swift — signed-out geometry checks.
- docs/IPHONE_DUO_QA.md — device-state matrix and actual verification limits.

## Android targets
- Android/app/src/main/java/com/example/tavattendance/auth/LoginScreen.kt
- Android/app/src/main/java/com/example/tavattendance/screens/kiosk/KioskPINDialogs.kt

## New Supabase schema (must be consumed by Android)
None.

## Sample test to write
Set a short landscape viewport and large font scale; type reserved example
email without submitting; resize/rotate; assert the draft survives and Sign In
remains reachable. In isolated PIN fixtures, confirm a mismatch can be retried
and Delete/Cancel remain reachable with IME/insets respected.

Implement the needed changes using existing Kotlin/Compose patterns. Preserve
PIN verification, lockout persistence and authentication. Do not change shared
Supabase migration files. Run Android tests, lint, build and emulator QA.
```

### Web

```markdown
You are porting iOS feature changes to the Web app at
/Users/limboenedmund/Documents/apps/TAVA/TAVAttendance/web/

## Feature summary
Audit short/narrow login layouts, keyboard visibility and text zoom against the
iOS adaptive-layout fix. Preserve the browser form's established Enter/submit
behavior. Apply only issues reproduced on Web; native PIN keypad behavior has
no direct Web counterpart in this change.

## iOS files changed
- iOS/TAVAttendance/Views/Auth/LoginView.swift — scrolling and keyboard reachability.
- iOS/TAVAttendance/Views/Kiosk/KioskPINViews.swift — native PIN layout.
- docs/IPHONE_DUO_QA.md — state matrix and evidence.

## Web targets
- web/app/login/page.tsx — login viewport and field/action reachability.
- Existing browser QA coverage for login and accessibility zoom.

## New Supabase schema (must be consumed by Web)
None.

## Sample test to write
Open signed-out login at a short mobile viewport and 200% text zoom. Type a
reserved example email without submitting; resize; assert the draft persists
and fields, errors and Sign In can be scrolled into view without horizontal
clipping.

Read web/AGENTS.md first. Implement reproduced fixes with existing patterns;
preserve auth routing and invite recovery. Do not change shared migrations.
Run the prescribed Web verification and browser checks.
```

## Demo mode (`demo@thegoodcompanysg.dev`): iOS + web shipped 2026-10-18, Android not ported

- **Feature summary:** demo email sign-in switches the app into an on-device
  in-memory store with invented data, and makes no Supabase calls. Includes a
  Demo badge with reset/exit and sign-out reset. Lauren Tan, Brian Chew, Agrim
  Singh and Nick Chan are on the roster as ordinary students, with no special
  UI.
- **iOS files:** `iOS/TAVAttendance/Demo/*`, demo branches at the top of each
  `AttendanceService+*.swift` method, `AuthManager` (enter/reset/exit),
  `SupabaseManager` (guarded URLSession), `TAVAttendanceApp` (overlay).
- **Android targets:** a `DemoRepository` behind the existing repository
  interfaces, chosen at sign-in, plus an OkHttp interceptor that rejects all
  requests while demo mode is on.
- **Schema:** none. Reuse the deterministic ids from `docs/DEMO_MODE.md`
  (`de{kind:06x}-0000-4000-8000-{n:012x}`) so QR codes match the other apps.
- **Sample test:** demo sign-in leaves the HTTP interceptor's blocked count at 0
  after loading the roster and marking a student present.

## October 2026 demo kiosk unlock handoffs

### Android

```text
You are porting iOS feature changes to the Android app at
/Users/limboenedmund/Documents/apps/TAVA/TAVAttendance/Android/

Feature summary
After Android demo mode is implemented, start its kiosk locked, open the PIN
keypad on a normal lock-icon tap and accept any four digits, including 0853.
Keep live PIN checks and lockouts. Isolate demo PIN/settings/counters from live
storage; reset demo lock state on entry/reset/exit and revoke admin unlock.

iOS files changed
- Demo/DemoMode.swift and Core/AuthManager.swift: demo kiosk storage/lifecycle.
- Views/Kiosk/GlobalKioskView.swift, KioskPINViews.swift, KioskSecurityPolicy.swift:
  tap-to-unlock and demo-only PIN acceptance.
- AppIntents/KioskRouter.swift: use the matching kiosk storage for authorization.

Android targets
- screens/kiosk/GlobalKioskScreen.kt: tap affordance.
- screens/kiosk/GlobalKioskViewModel.kt: demo PIN/storage/authorization lifecycle.
- screens/kiosk/KioskPINDialogs.kt and KioskSecurityPolicy.kt: isolated demo unlock.

New Supabase schema (must be consumed by Android)
None.

Sample test to write
Demo unlock accepts 0853 and 9876, rejects incomplete/non-digit PINs, cancel
stays locked, and lock/unlock can repeat. Exit demo: live settings are unchanged,
admin authorization is revoked and an incorrect live PIN still fails.

Implement with existing Kotlin/Compose patterns after the separate demo port.
Do not change Supabase migrations; they are shared.
```

### Web

```text
You are assessing iOS feature parity for the Web app at
/Users/limboenedmund/Documents/apps/TAVA/TAVAttendance/web/

Feature summary
The iOS demo kiosk accepts a normal lock-icon tap and any four-digit PIN.
Live security stays unchanged; demo credentials and lock state are isolated.
Web currently has no kiosk PIN lock, so no Web change is required for this fix.

iOS files changed
- Views/Kiosk/GlobalKioskView.swift, KioskPINViews.swift, KioskSecurityPolicy.swift.
- Demo/DemoMode.swift, Core/AuthManager.swift, AppIntents/KioskRouter.swift.

Web targets
- components/mobile/sign-in-board.tsx: existing sign-in board, no PIN lock.

New Supabase schema (must be consumed by Web)
None.

Sample test to write
If a Web kiosk lock is separately requested, verify demo accepts 0853/9876
without changing live credentials or authorization, and live wrong PIN fails.

No implementation is needed now. Do not add a PIN feature solely for parity.
Do not change Supabase migrations; they are shared.
```

## Offline batch recovery handoffs

```text
You are verifying iOS feature parity in Android/.
Feature summary: bounded offline sync, partial acknowledgements, retained
quarantine for permanent SQL rejections and visible reconciliation warnings.
iOS files changed: Core/PendingAttendanceStore.swift (policy/persistence),
Views/Session/RosterView.swift (integration), AttendanceLogicTests.swift.
Android targets: data/store/PendingAttendanceStore.kt, screens/RosterScreen.kt,
and PendingAttendanceStoreTest.kt. Equivalent changes are included in this fix.
New Supabase schema: None.
Sample test: queue 501 records including one permanent rejection; verify 500
valid acknowledgements and one retained quarantine. Fail the second chunk with
transport loss and verify the first acknowledgement remains committed locally.
Also verify online corrections and clears acknowledge the captured quarantined
mutation, preserve newer queued edits, and show server truth after reopening.
Run native tests and device QA; no additional port or migration is required.
```

```text
You are assessing iOS feature parity in web/.
Feature summary: native offline queue batch recovery and retained quarantine.
iOS files changed: Core/PendingAttendanceStore.swift, Views/Session/RosterView.swift,
and AttendanceLogicTests.swift.
Web targets: none; Web has no equivalent persisted native offline queue.
New Supabase schema: None.
Sample test if a Web queue is separately introduced: submit 501 mutations with
one rejected record; retain that record and acknowledge the valid ones.
No Web implementation or migration is required for this fix.
```
