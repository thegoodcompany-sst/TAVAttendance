# TAVAttendance (iOS)

SwiftUI app (iOS 17+) for TAVA's attendance system: the iPad sign-in kiosk,
tutor roster marking with offline sync, admin tools, and the flag-gated parent
portal.

## Project is XcodeGen-managed

`TAVAttendance.xcodeproj` is **generated** — never hand-edit it. Edit
`project.yml`, then:

```bash
brew install xcodegen   # once
cd iOS
xcodegen generate
```

New source files under `TAVAttendance/` are picked up automatically on the next
generate.

## Credentials

```bash
cp Config.xcconfig.example Config.xcconfig   # gitignored
```

Fill in `SUPABASE_PROJECT_URL` and `SUPABASE_ANON_KEY`. xcconfig treats `//` as a
comment — escape the URL as `https:/$()/xyz.supabase.co`. Values flow through
Info.plist and are read in `SupabaseManager.swift`; nothing is hardcoded.

## Build & test

```bash
cd iOS
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild test -project TAVAttendance.xcodeproj -scheme TAVAttendance \
  -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
```

Device builds sign with the `DEVELOPMENT_TEAM` set in `project.yml`; the push
entitlement (`aps-environment`) additionally needs the Push Notifications
capability enabled on the App ID (see HUMANS.md).

## Layout

```
TAVAttendance/
  Core/        SupabaseManager, AuthManager, AppError, PushManager,
               NetworkMonitor, PendingAttendanceStore (offline sync)
  Models/      Models.swift (TAVClass, Student, Session, …)
  Services/    AttendanceService (all queries + kiosk logic), FeatureFlags
  Views/
    Auth/      LoginView
    Classes/   class list (tutor entry point)
    Kiosk/     GlobalKioskView, StudySpaceView
    Session/   SessionListView, RosterView, StudentProfileView
    Admin/     class/student management, export
    Parent/    ParentDashboardView (flag-gated)
  AppIntents/  Siri/Shortcuts intents (untested on device)
TAVAttendanceTests/   pure-logic XCTests (auto-late, worstStatus, classMeetsToday)
```

Localization: `Localizable.xcstrings` String Catalog (en + zh-Hans; zh-Hans is
machine-translated pending native review — HUMANS.md §23).
