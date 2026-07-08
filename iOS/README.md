# TAVAttendance iOS — Developer Setup

## Prerequisites

- Xcode 16+
- iOS 17+ deployment target
- Access to the TAVA Supabase project (URL + anon key)

---

## Step 1 — Add the Supabase Swift Package

1. Open `TAVAttendance.xcodeproj` in Xcode
2. **File → Add Package Dependencies…**
3. Paste the URL: `https://github.com/supabase/supabase-swift`
4. Select version rule: **Up to Next Major** from `2.0.0`
5. Click **Add Package**
6. When asked which products to add, select **Supabase** (the umbrella product — includes Auth, PostgREST, Realtime, Storage)
7. Click **Add to Target: TAVAttendance**

---

## Step 2 — Add the New Source Files to Xcode

The scaffolding files live in `TAVAttendance/` but Xcode doesn't know about them yet.

1. In the Xcode Project Navigator, right-click on the **TAVAttendance** group
2. Choose **Add Files to "TAVAttendance"…**
3. Select these folders (check **Create groups**, not folder references):
   - `Core/`
   - `Models/`
   - `Services/`
   - `Views/`
4. Make sure **Add to targets: TAVAttendance** is checked
5. Click **Add**

> You can delete the old `ContentView.swift` — it is no longer used.

---

## Step 3 — Fill in Your Supabase Credentials

Credentials are never hardcoded in `SupabaseManager.swift` — they flow in via a gitignored
xcconfig file, referenced from `Info.plist` through XcodeGen's `project.yml`.

```bash
cp Config.xcconfig.example Config.xcconfig
```

Then edit `Config.xcconfig`:

### Local dev (after running `supabase start` at the repo root)

```
SUPABASE_PROJECT_URL = http://127.0.0.1:54321
SUPABASE_ANON_KEY = <anon key printed by `supabase start`>
```

### Production

```
SUPABASE_PROJECT_URL = https:/$()/YOUR_PROJECT_REF.supabase.co
SUPABASE_ANON_KEY = <anon key from Supabase Dashboard → Settings → API>
```

> `//` starts a comment in `.xcconfig` syntax, so the URL's slashes must be split with an
> empty `$()` reference as shown (see `Config.xcconfig.example`) — don't wrap the value in quotes.

`SupabaseManager.swift` reads these at runtime via
`Bundle.main.object(forInfoDictionaryKey:)` — no rebuild-from-source-edit needed after
changing `Config.xcconfig`, just re-run the build so Xcode re-reads the xcconfig values.

---

## Step 4 — Build & Run

Build with **⌘B**. All SourceKit errors clear once the package resolves.

Sign in with one of the dev seed accounts:

| Role   | Email           | Password     |
|--------|-----------------|--------------|
| Admin  | admin@tava.dev  | TAVAdev123!  |
| Tutor  | tutor@tava.dev  | TAVAdev123!  |
| Parent | parent@tava.dev | TAVAdev123!  |

---

## Project Structure

```
TAVAttendance/
├── Core/
│   ├── SupabaseManager.swift        Supabase client singleton + credentials ← FILL IN KEYS HERE
│   ├── AuthManager.swift            Auth state (ObservableObject)
│   ├── NetworkMonitor.swift         Online/offline detection
│   └── PendingAttendanceStore.swift Local offline queue (UserDefaults)
├── Models/
│   └── Models.swift                 All Codable structs
├── Services/
│   └── AttendanceService.swift      All Supabase API calls
└── Views/
    ├── Auth/
    │   └── LoginView.swift          Sign-in screen
    ├── Classes/
    │   └── ClassListView.swift      Home screen after login
    └── Session/
        ├── SessionListView.swift    Sessions per class + "Start Today's Class"
        └── RosterView.swift         Attendance marking (P / A / L / E buttons)
```

---

## Offline Behaviour

- **Online**: `markAttendance()` writes directly to Supabase.
- **Offline**: record saved to `PendingAttendanceStore` (UserDefaults).
- **On reconnect**: `syncPending()` runs automatically, pushing all queued records.
- Roster shows an orange wifi-slash icon when offline.

---

## Adding Phase 2 / 3 Features

Backend tables for `result_slips`, `messages`, `awards`, `dismissals`, `food_polls` already exist with admin-only access. To wire a new feature:

1. Add a method to `AttendanceService.swift` (or a new `XxxService.swift`)
2. Add the model to `Models.swift`
3. Build the view
4. Add a migration in `supabase/migrations/` to open up RLS for the new role/feature
