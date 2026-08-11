# iOS change guide

The root `AGENTS.md` applies here. This file adds iOS-specific editing rules.

## Before editing

- Copy `Config.xcconfig.example` to the gitignored `Config.xcconfig` for local
  builds. Never hard-code Supabase credentials.
- The project is XcodeGen-managed. Edit `project.yml`, never
  `TAVAttendance.xcodeproj`; run `xcodegen generate` after project-structure
  changes.
- Follow the existing SwiftUI and structured-concurrency patterns. Keep
  Supabase access in `Services/`, not views.

## Where changes belong

- Database DTOs and domain values: `TAVAttendance/Models/`
- Supabase reads/writes: the focused `AttendanceService+*.swift` extension or
  an existing dedicated service
- Cross-cutting app state/auth/network concerns: `TAVAttendance/Core/`
- UI and local presentation state: `TAVAttendance/Views/`
- Pure behavior regressions: `TAVAttendanceTests/`

When a view becomes responsible for domain transitions, authorization policy,
or complicated merge rules, extract that logic behind a small testable
interface rather than adding another view-local branch.

## Verification and parity

Run from this directory:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild test \
  -project TAVAttendance.xcodeproj \
  -scheme TAVAttendance \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO
```

Use `.claude/skills/tava-validation-and-qa/SKILL.md` for manual flow checks.
After an iOS feature, emit Android and Web port handoff blocks using
`Android/PORTING_NOTES.md`; do not spawn the porting agents automatically.
