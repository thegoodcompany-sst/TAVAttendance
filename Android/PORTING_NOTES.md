# Android porting notes

The Android app mirrors the iOS feature set. When an iOS feature lands, port it
here. Do **not** change Supabase migrations — they are shared across platforms.

## iOS → Android file mapping

| iOS file | Android equivalent |
|---|---|
| `Models/Models.swift` | `data/models/Models.kt` |
| `Services/AttendanceService.swift` | `data/service/AttendanceService.kt` |
| `Services/FeatureFlags.swift` | `data/service/FeatureFlags.kt` |
| `Views/Kiosk/GlobalKioskView.swift` | `screens/kiosk/GlobalKioskScreen.kt` |
| `Views/Parent/ParentDashboardView.swift` | `screens/ParentDashboardScreen.kt` |
| `Views/Kiosk/QRScannerView.swift` | *(pending — CameraX/ML Kit scanner)* |
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

## Known parity gaps (follow-ups)

These iOS items are ported at the data/service layer but still need Compose UI:

- Kiosk UX: auto-refresh (UX-01), search (UX-02), bulk-action confirm (UX-03),
  absent-tap confirm (UX-04), Not-Here/Absent info (UX-07), unsigned text label (A11Y-02),
  photo display (PROD-04).
- FCM push registration (PROD-02). Parent portal (PROD-01) ported 2026-07-12.
- Kiosk QR sign-in (flag `qr_sign_in`): iOS scanner shipped 2026-07-12; Android needs a
  CameraX + ML Kit (or ZXing) scanner in `GlobalKioskScreen` reusing the existing
  sign-in path. Session notes (flag `session_notes`) ported 2026-07-12.
