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
