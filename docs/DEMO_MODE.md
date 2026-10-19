# Demo mode (iOS + web)

Sign in with **`demo@thegoodcompanysg.dev`** (any password, or none) to open a
self-contained demo of TAVA. Demo mode never talks to Supabase: there is no demo
database, no backend change, and no migration. Every read and write goes to an
in-memory store seeded with invented data, so you can tap anything during a demo
without touching real records.

## What you get

- A small amber **Demo** badge (bottom-left on iOS, top bar on web). Tap it to
  **Reset demo data** (fresh seed) or **Exit demo**.
- Signed in as "Demo Admin" (admin role), so every screen is reachable.
- 4 classes (P5 English and Sec 1 English on Monday, P6 Mathematics and Sec 2
  Mathematics on Thursday, 7 pm) plus Study Space; 24 students with
  Singapore-style names; three tutors; two linked parents.
- Eight weeks of attendance history, today's open sessions for every class with
  a few early arrivals, grades, result slips, parent messages, a pending
  correction request, consent records, an award, and an NFC card binding.
- Feature flags for the parent portal, Study Space, session notes, QR sign-in,
  retrospective sessions, NFC and test mode are on, so check-in works on any day.
  Push, analytics and student photos are off. File uploads and the data wipe
  say they are switched off in demo mode.
- Familiar names: **Lauren Tan**, **Brian Chew**, **Agrim Singh** and
  **Nick Chan** are on the roster as ordinary students. Their names are the
  only Easter egg. Demo mode adds no UI beyond the Demo badge.

Demo ids are deterministic and shared by iOS and web, so a QR code printed from
the web demo scans on the iOS demo kiosk.

## How it works

### iOS

- `iOS/TAVAttendance/Demo/DemoMode.swift`: demo flag and email check. The flag
  lasts until sign-out. A relaunch stays in demo mode with a fresh seed.
- `DemoStore.swift` / `DemoSeed.swift`: in-memory store and seed.
- Each `AttendanceService` method starts with
  `if DemoMode.isActive { return DemoStore.shared… }`, so the service layer is
  the only switch point.
- `DemoNetworkGuard` (a `URLProtocol` installed into the Supabase client's
  `URLSession`) refuses every Supabase request while demo mode is on. It is a
  safety net in case a call site skips the service layer.
- The iOS demo kiosk starts locked. **Tap the lock icon**, then enter **any
  four digits** (for example `0853`) to unlock admin controls. Cancel keeps it
  locked; Kiosk Settings → Lock Kiosk Now lets you rehearse again. Demo PIN,
  lock and failure-counter settings are separate from the real kiosk and reset
  on demo entry, reset and exit. Live kiosks still require a long press and
  their configured PIN.
- Sign-out resets demo data. `NetworkMonitor` reports "connected" in demo mode,
  so the demo still works in airplane mode and never queues offline writes.

### Web

- `web/lib/supabase/server.ts` `createClient()` and `admin.ts`
  `createAdminClient()` return the in-memory emulator
  (`web/lib/demo/emulator.ts`) when the `tava_demo` cookie is present. The
  browser client (`lib/supabase/client.ts`) returns a no-network stub.
  `proxy.ts` skips Supabase Auth for demo browsers.
- Demo changes are kept as a compressed journal in this browser's
  `tava_demo_state.N` cookies, on top of the deterministic seed. Nothing is
  stored on the server. Reset or sign-out clears them.
- `is_superadmin` is false in demo mode, so export, flags and wipe stay hidden.

## Offline and hard-coded

- **iOS works fully offline.** The demo email, the seed data and the demo
  feature flags are compiled into the app. No remote flag, remote config, env
  var or server toggle can change or disable them, and nothing is `#if DEBUG`.
  A missing `Config.xcconfig` no longer crashes the app, and the launch spinner
  is capped at 3 s, so the sign-in screen appears in airplane mode. In demo
  mode, push, analytics, feature-flag fetches and the auth listener make no
  network calls, and the offline banner never shows. A relaunch stays in demo
  mode with fresh data. CI builds the iPad target in the Release configuration,
  the one used for Archive.
- **Web needs a connection.** The dashboard is server-rendered on Vercel, so
  pages can't load offline. Demo mode on the web only avoids the database.

## Tests

- iOS: `iOS/TAVAttendanceTests/DemoModeTests.swift` covers email matching, seed
  coverage, demo reads and writes with zero blocked network requests, the
  network guard, and the non-demo path reaching Supabase.
- Web: `web/lib/demo/demo-mode.test.ts` mocks `@supabase/ssr`,
  `@supabase/supabase-js` and `fetch`, then drives the real query functions and
  server actions in demo mode. It asserts that none of them is called, and that
  a non-demo cookie jar uses the real clients.

### Demo kiosk verification (2026-10-19)

Xcode-beta, signing disabled, iPhone Duo / iOS 27.1: **85 unit tests passed,
one skipped**. The demo kiosk UI regression passed: normal lock-icon tap,
Cancel stays locked, `0853` unlocks, Kiosk Settings relocks, then `9876`
unlocks. The storage regression also checks invalid/incomplete input, unchanged
live settings, revoked demo authorization and wrong-PIN rejection outside demo.

The canonical iPhone 17 command could not run: `Unable to find a device matching
the provided destination specifier`. Creating it against the installed runtime
failed with `Incompatible device`; the available Duo destination was used.
Physical presentation-device installation and QA remain in `HUMANS.md` §85.
