# Android porting notes

The Android app mirrors the iOS feature set. When an iOS feature lands, port it
here. Do **not** change Supabase migrations — they are shared across platforms.

## iOS → Android file mapping

| iOS file | Android equivalent |
|---|---|
| `Models/Models.swift` | `data/models/Models.kt` |
| `Services/AttendanceService.swift` | `data/service/AttendanceService.kt` |
| `Services/FeatureFlags.swift` | `data/service/FeatureFlags.kt` |
| `Services/Analytics.swift` | `core/Analytics.kt` |
| `Views/Kiosk/GlobalKioskView.swift` | `screens/kiosk/GlobalKioskScreen.kt` |
| `Views/Parent/ParentDashboardView.swift` | `screens/ParentDashboardScreen.kt` |
| `Views/Kiosk/QRScannerView.swift` | `screens/kiosk/QrScannerSheet.kt` |
| `Views/Session/StudentProfileView.swift` | `screens/StudentProfileSheet.kt` |
| `Views/Session/RosterView.swift` | `screens/RosterScreen.kt` |
| `Views/Session/SessionListView.swift` | `screens/SessionListScreen.kt` |
| `Views/Admin/ClassFormView.swift` | `screens/ClassFormDialog.kt` |
| `Views/Admin/StudentManagementView.swift` | `screens/StudentManagementScreen.kt` |
| `Views/Admin/StudentFormView.swift` | `screens/StudentFormDialog.kt` |
| `Views/Admin/TutorAssignmentView.swift` | `screens/TutorAssignmentScreen.kt` |

Base package: `app/src/main/java/com/example/tavattendance/`.

## Conventions

- Models are `@Serializable` with `@SerialName` for snake_case DB columns.
- Service methods live on the `AttendanceService` object; all Supabase access goes
  through it.
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
  absent-tap confirm (UX-04), Not-Here/Absent info (UX-07), unsigned text label (A11Y-02),
  photo display (PROD-04).
- Parent portal (PROD-01) ported 2026-07-12.
- Kiosk QR sign-in (flag `qr_sign_in`) ported 2026-07-12 (CameraX + ML Kit,
  `QrScannerSheet.kt`). Session notes (flag `session_notes`) ported 2026-07-12.
