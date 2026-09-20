# iPhone Duo readiness

Research date: 2026-09-20. This is a test matrix, not a claim that every cell
has passed. Attendance behavior remains defined in `KIOSK_ATTENDANCE.md`.

## Toolchain

Use **Xcode 27.1 beta (27A9269)** and its Duo simulator runtime. Rebuilding
with its iOS 27.1 SDK enables the new full-display layout and system bars;
raising TAVA's iOS 17 minimum is unnecessary. Xcode 27.2 beta was released
earlier and explicitly does not contain this Duo support.

Sources: [Apple's Duo resources](https://developer.apple.com/iphone-duo/),
[27.1 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27_1-release-notes),
[27.2 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27_2-release-notes).

## Display and transition matrix

| State | Variations to exercise | Acceptance |
|---|---|---|
| Closed, outer display | Supported rotations; keyboard hidden/shown | All fields and actions reachable; no camera/status-bar overlap |
| Fully open, inner display | Portrait, upside down, landscape left/right | No fixed-phone-width assumptions; correct safe areas |
| Partially open | Book posture and tabletop posture; intermediate angles | Important controls avoid the fold; scrolling content remains usable |
| Multitasking | App on either side; resize; video stacked with app | Both asymmetric safe-area configurations work |
| Open/close transition | Repeat while navigating, typing, selecting, or presenting a sheet | Preserve destination, draft, selection and pending-operation state |
| Fold/unfold and rotation | Repeat during loading, errors and keyboard presentation | No crash, clipped action, accidental submission or duplicate mutation |
| Scene lifecycle | Background/foreground, app switcher, lock/unlock | Privacy cover remains opaque; configured kiosk and biometric locks relock |
| Camera | QR sheet; permission denied; interrupted capture; rotate/fold | Dismissal and error recovery reachable; preview tracks bounds |

The inner display uses regular size classes and does not honor the app's
orientation restrictions. Use actual view geometry and independent safe-area
insets, not a device-name or screen-size lookup. Standard navigation and sheets
adapt automatically. See [Prepare your app](https://developer.apple.com/videos/play/tech-talks/111461/).

Vertical toolbars share limited space with navigation and tabs. Test overflow,
text buttons, and cancellation/confirmation actions in sheets. See
[Raise the bar](https://developer.apple.com/videos/play/tech-talks/111462/).

The fold is a division reserved region; the active inner camera is an occlusion
region. Use reserved-region/arrangement APIs for custom fixed controls rather
than hardcoded hinge coordinates. Do not displace continuous scrolling content.
See [Adaptive layouts](https://developer.apple.com/videos/play/tech-talks/111463/).

All apps participate in Duo multitasking. Optional extra windows and
simultaneous outer-display camera accessories are separate product features;
TAVA does not add them merely for compatibility. See
[Displays and scenes](https://developer.apple.com/videos/play/tech-talks/111464/)
and [Camera](https://developer.apple.com/videos/play/tech-talks/111465/).

Cross each relevant state with light/dark appearance, largest accessibility text,
long labels, empty/populated/loading/error content, and keyboard presentation.
Physical QR capture and biometric enrollment require device evidence. StandBy
and most app-extension debugging are unavailable in this beta simulator.

## TAVA flow inventory

| Area | Screens and conditions |
|---|---|
| Entry/security | Login, invalid input/loading/error, Privacy Notice sheet, biometric cover, station-account restriction |
| Staff classes | Class list, add/edit class, session list, retrospective session, session details, roster, end-class confirmation |
| Students | List/search, add/edit, detail/profile/history, enrollment, tutor assignment, results and result-slip upload |
| Kiosk | Initial loading, empty day, failed load/retry, populated grid, refresh, search/no matches, selection and all bulk confirmations |
| Kiosk safety | PIN setup/confirmation/mismatch/delete/cancel; unlock/incorrect/lockout/recovery; settings challenge; relock on background |
| Attendance cards | Not Here Yet, present, late/reason, absent/informed, dismissed, pending, selection and long-press menus |
| Optional surfaces | Study Space, QR scanning, photos, session notes, parent links/dashboard/messages, correction requests |
| Data operations | Import picker/validation, export/share sheet, privacy/consent screens; use only synthetic records for writes |

Flags remain unchanged. A missing flagged screen is recorded as skipped, not
passed. Login credentials stay outside source, screenshots and test fixtures.

## Repeatable login checks

Use a **signed-out disposable simulator**. These tests type reserved example
credentials but never submit them. Privacy Notice performs its normal read.

```sh
cd iOS
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild test -project TAVAttendance.xcodeproj \
  -scheme TAVAttendanceLayout \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO
```

Select the installed Duo destination to repeat there. Run the ordinary
`TAVAttendance` scheme for attendance/security unit regressions as well.

## Execution evidence

- Initial iPhone 17 / iOS 27.0 baseline: 76 unit tests passed, one skipped.
- Computer interaction reproduced clipped login content in landscape before
  the fix. After the fix, swiping reached Sign In and Privacy Notice.
- Installed Xcode 27.1 beta (27A9269), updated CoreSimulator, and installed
  iOS 27.1 (24A94401). Created and booted **TAVA iPhone Duo**
  (`191C6F80-2A9F-4A49-891D-B54FDD36B08B`); installed both applications.
- Rebuilt with the iOS 27.1 SDK. Unit regressions on iPhone 17: **76 passed,
  one skipped** (`testPendingStoreReturnsAllOwnedSessionsForSync`). Signed-out UI regressions: **3 passed on iPhone 17** and
  **3 passed on Duo**, zero failures. They cover rotation with typed email,
  keyboard Next/Done, reachable actions, and largest-text Privacy presentation.
- Computer interaction on Duo: closed/open/book login, rotation, retained email
  draft, and Privacy presentation preserved through folding. Privacy content
  loaded and its Done action remained available.
- Synthetic PIN setup survived inner-to-outer folding at confirmation; the
  matching confirmation configured the PIN. Unlock preserved two entered digits
  through close/reopen and accepted the completed PIN. Dark appearance and the
  largest accessibility text kept the keypad and Cancel reachable by scrolling.
- iPhone 17 synthetic PIN checks included mismatch/retry, deletion, successful
  unlock, rotation during confirmation, short landscape scrolling, and a
  375 × 667 resized viewport. Device Hub clamped a requested smaller viewport;
  this is not evidence for a 320-point viewport.
- Normal light appearance and default text size were restored after checking.

Result bundles (local DerivedData `TAVAttendance-*/Logs/Test/`):
`Test-TAVAttendance-2026.09.20_09-42-15-+0800.xcresult` and
`Test-TAVAttendanceLayout-2026.09.20_09-45-25-+0800.xcresult`.
The Duo UI suite reports the existing Supabase initial-session behavior warning;
this change does not alter authentication session semantics.

## Outstanding coverage

The inventory above is broader than the completed checks. Authenticated admin,
tutor and parent navigation, live grid/bulk controls, all loading/error states,
multitasking on both sides, every intermediate fold angle, lockout/recovery,
camera permission flows and real-device QR/biometrics still need evidence.
A username/password account does not supply all three roles or guarantee
synthetic records. Sign in locally and identify disposable fixtures before
mutation tests. Do not call this a complete Duo release sign-off yet.
