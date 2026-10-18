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
- Easter eggs: check in or open the profile of **Lauren Tan** 🌟,
  **Brian Chew** 🏀, **Agrim Singh** 🚀 or **Nick Chan** 🎉 for a friendly
  banner on check-in and a fun-fact card on their profile.

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

## Tests

- iOS: `iOS/TAVAttendanceTests/DemoModeTests.swift` covers email matching, seed
  coverage, demo reads and writes with zero blocked network requests, the
  network guard, and the non-demo path reaching Supabase.
- Web: `web/lib/demo/demo-mode.test.ts` mocks `@supabase/ssr`,
  `@supabase/supabase-js` and `fetch`, then drives the real query functions and
  server actions in demo mode. It asserts that none of them is called, and that
  a non-demo cookie jar uses the real clients.
