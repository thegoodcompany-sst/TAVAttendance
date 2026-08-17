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

## Known parity gaps (follow-ups)

These iOS items are ported at the data/service layer but still need Compose UI:

- Kiosk UX: auto-refresh (UX-01), search (UX-02), bulk-action confirm (UX-03),
  absent-tap confirm (UX-04), Not-Here-Yet/Absent info (UX-07),
  photo display (PROD-04).
- Parent portal (PROD-01) ported 2026-07-12.
- Kiosk QR sign-in (flag `qr_sign_in`) ported 2026-07-12 (CameraX + ML Kit,
  `QrScannerSheet.kt`). Session notes (flag `session_notes`) ported 2026-07-12.
