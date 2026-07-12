# Contributing to TAVA Attendance

This is a multi-platform monorepo: an iOS kiosk (`iOS/`), an Android app
(`Android/`), a Next.js admin dashboard (`web/`), and a shared Supabase backend
(`supabase/`). This guide consolidates local setup for all of them.

> Agent note: project-specific conventions live in `CLAUDE.md`. Read it before
> changing code.

---

## 1. Supabase (shared backend)

```bash
# Install the Supabase CLI, then from the repo root:
supabase start          # boots local Postgres + Auth + Storage + Studio
supabase db reset       # applies every migration in supabase/migrations in order
```

### Migrations

Forward migrations are `NNN_name.sql`, applied in numeric order. From migration
012 onward each ships a paired reverse script in `supabase/migrations/down/` — see
`supabase/migrations/README.md`. Migrations 001–011 predate that convention.

### Storage buckets

Two private buckets back file features. `supabase db reset` creates them via
migrations (`011` and `014`); for a brand-new remote project verify they exist:

| Bucket | Created in | Used by | RLS |
|---|---|---|---|
| `result-slips` | `011_pdpa_compliance.sql` | exam result slips | admin write; parent reads own child |
| `student-photos` | `014_feature_tables.sql` | student avatars (PROD-04) | admin write; any authenticated read |

Both are **private** (`public = false`); clients fetch short-lived signed URLs.
Client uploads are size-capped (result slips 10 MB, photos 5 MB).

### Edge functions

`supabase/functions/notify-parent` sends parent push on late/absent. It is gated
by the `push_notifications` flag and needs real APNs/FCM secrets (see §6).

```bash
supabase functions deploy notify-parent
```

### Feature flags

The `feature_flags` table (migration 012) gates in-progress features and ships
all-OFF. Flip one (admin only):

```sql
UPDATE feature_flags SET enabled = true WHERE key = 'parent_portal';
-- keys: parent_portal, push_notifications, student_photos, study_space_tracking,
--       test_mode, session_notes, qr_sign_in, awards
```

---

## 2. iOS (`iOS/`)

```bash
cp iOS/Config.xcconfig.example iOS/Config.xcconfig   # fill in URL + anon key
open iOS/TAVAttendance.xcodeproj
```

Credentials are read from `Info.plist` (`$(SUPABASE_PROJECT_URL)` /
`$(SUPABASE_ANON_KEY)`) via `SupabaseManager.swift` — never hardcode them.
The kiosk (Sign-In tab) must be signed in as an **admin** account (see CLAUDE.md).

## 3. Android (`Android/`)

```bash
cp Android/secrets.properties.example Android/secrets.properties   # fill in values
cd Android && ./gradlew installDebug
```

`build.gradle.kts` reads `secrets.properties` at configure time; values surface
as `BuildConfig.SUPABASE_PROJECT_URL` etc. Release builds are minified
(R8/ProGuard) — keep rules for Supabase / kotlinx-serialization live in
`app/proguard-rules.pro`.

## 4. Web (`web/`)

```bash
cp web/.env.local.example web/.env.local   # NEXT_PUBLIC_SUPABASE_URL / _ANON_KEY
cd web && npm install && npm run dev
```

> The web app pins a non-standard Next.js — read `web/AGENTS.md` before editing.

---

## 5. Local testing checklist

Automated tests cover the core attendance logic only (iOS `TAVAttendanceTests`, Android
`DayAwareKioskTest`, `supabase/tests/sync_attendance_test.sql`); test the rest manually
(full script in `CLAUDE.md`):

- **Kiosk sign-in**: admin login → Sign-In tab → tap a student → green (on time) /
  orange (late); long-press for overrides; search filters the grid.
- **Roster**: tutor → Start class → mark present; offline dot appears/clears; "Absent
  rest" marks all unmarked.
- **Profile history**: tap a roster row → history + attendance % render.

| Platform | Command | Dir |
|---|---|---|
| iOS | `xcodebuild test -project TAVAttendance.xcodeproj -scheme TAVAttendance -destination 'platform=iOS Simulator,name=iPhone 17'` (or build via Xcode; scheme name comes from `project.yml`, XcodeGen-managed) | `iOS/` |
| Android | `./gradlew test` (needs JDK 17 or 21 — fails under newer JDKs with a jlink error; fall back to `./gradlew clean compileDebugKotlin`) | `Android/` |
| Web | `npm run build` / `npm run lint` | `web/` |

Machine-specific caveats (Xcode-beta `DEVELOPER_DIR`, `CODE_SIGNING_ALLOWED=NO`)
live in `CLAUDE.md` §Running tests — agents should use that table.

---

## 6. Operations & monitoring (DEVOPS-04)

- **Web (Vercel)**: enable Vercel's built-in health checks / deployment protection;
  watch the project's Analytics + Runtime Logs.
- **Supabase**: subscribe to <https://status.supabase.com>; review the Advisors
  (security + performance) in the dashboard after schema changes.
- **External uptime**: add a ping monitor (e.g. UptimeRobot) against the dashboard
  URL and a Supabase health endpoint.
- **Secrets**: the repo ships a pre-commit hook (`.githooks/pre-commit`) that rejects
  staged files containing `SUPABASE_*_KEY=`. Enable it once per clone:
  ```bash
  git config core.hooksPath .githooks
  ```
- **Push (PROD-02)**: provide APNs key (iOS) and an FCM server key (Android) as
  Supabase function secrets before enabling the `push_notifications` flag.
