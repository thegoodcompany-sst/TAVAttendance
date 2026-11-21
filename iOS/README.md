# TAVAttendance (iOS)

SwiftUI app (iOS 17+) for TAVA's attendance system: the iPad sign-in kiosk,
tutor roster marking with offline sync, admin tools, and the flag-gated parent
portal.

## Teacher prompts (ships OFF)

The actual app now includes the v2 teacher lesson list, attendance/notes/submit and
push/deep-link flow. `TEACHER_PROMPTS_V2_ENABLED=NO` remains the build master in
Debug and Release/TestFlight; shared `teacher_prompts` / `teacher_prompt_push` flags
and explicit push opt-in provide runtime gates. Debug-only `--teacher-prompts-demo`
opens fake data without a network; add `--teacher-prompts-dark` for dark screenshots.
For a connected teacher build, set `CONVEX_URL` in `Config.xcconfig` (dev example
`https:/$()/adept-duck-658.convex.cloud`) and pass `TEACHER_PROMPTS_V2_ENABLED=YES`
to the Debug build. Sign in with an activated Convex staff email and password.
The app refreshes the token pair from Keychain and loads profile and rollout
flags from Convex. Master-OFF builds use the usual Supabase settings.
See [native integration, checks and port handoffs](../docs/teacher-prompts/ios/README.md)
and `HUMANS.md` §89. No APNs entitlement or Associated Domain was added.

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

For iPhone Duo, build with Xcode 27.1's SDK and use the display/flow matrix in
[`docs/IPHONE_DUO_QA.md`](../docs/IPHONE_DUO_QA.md). The separate
`TAVAttendanceLayout` scheme runs signed-out login UI regressions. The
`TAVLayoutLab` scheme builds a separate application with the real PIN controls
and synthetic attendance cards. It has its own storage domain and no backend
configuration; use it for destructive PIN/lockout experiments. Neither the lab
entry point nor its fixtures are included in the production application target.

## Layout

```
TAVAttendance/
  Core/        SupabaseManager, AuthManager, AppError, PushManager,
               NetworkMonitor, PendingAttendanceStore (offline sync)
  Models/      Database DTOs and domain values
  Services/    AttendanceService domain extensions and supporting services
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
