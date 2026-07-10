---
name: tava-config-and-flags
description: Use when adding/flipping a feature flag, adding an env var or credential, wondering what configuration exists in TAVA, or when a feature "doesn't show up" (probably flag-gated OFF). Catalogs every configuration axis — feature_flags rows, per-platform credential files, Vercel env vars, superadmin gate — with defaults, guards, and the add-a-flag checklist.
---

# TAVA Config and Flags

Every knob in the system, where it lives, and how to add one.

**When NOT to use this skill:** creating the config files on a fresh machine
(use `tava-build-and-env`); deciding WHEN a flag may flip (use
`tava-change-control` — flips are human-gated).

## Feature flags (`feature_flags` table, migration 012)

The only runtime feature gating. One table, read by all three platforms:
iOS `FeatureFlagStore` (`Services/FeatureFlags.swift`), Android
`FeatureFlags` (`data/service/FeatureFlags.kt`), web `getFeatureFlags()`
(`lib/feature-flags.ts`). Writes are admin-only via RLS;
`is_feature_enabled()` backs DB-side checks.

| Key | Feature | Status (2026-07-09) |
|---|---|---|
| `parent_portal` | Parent attendance view (iOS `ParentDashboardView`, web `/parent`) | Built, OFF (PROD-01) |
| `push_notifications` | APNs/FCM via `notify-parent` edge function + `device_tokens` | Scaffolded, OFF; needs real keys (HUMANS.md §17) + prod migration 014 |
| `student_photos` | Kiosk avatars (`students.avatar_url` + `student-photos` bucket) | Built, OFF; prod backend complete since 2026-07-09 (migration 014) |
| `study_space_tracking` | Internal drop-in room tracking (iPad `StudySpaceView`) | Built (iOS), OFF; flip ONLY after Android+web ports land (§26) |

Read state: `SELECT key, enabled FROM feature_flags;`
Flip (human-gated step, per change control): `UPDATE feature_flags SET enabled = true WHERE key = '<key>';`
or via the superadmin web page below. **A flag is global across platforms — every platform must handle it before flipping.**

### Checklist: adding a new flag

1. New migration (never edit 012): `INSERT INTO feature_flags (key, enabled, description) VALUES ('my_feature', false, '...');` + `.down.sql` deleting it.
2. Gate the code on ALL platforms that surface the feature (query the store/helper above; default to OFF when the row is missing or the read fails).
3. Nothing else — the web `/feature-flags` page renders every row generically, so the toggle appears automatically once the row is seeded.
4. Add a HUMANS.md item for the eventual flip with its preconditions.
5. Re-verify after applying: `SELECT key, enabled FROM feature_flags;`

## Superadmin gate (web `/feature-flags` page)

- App-layer gate to ONE email; DB RLS write policy deliberately stays `is_admin()` (documented in `web/lib/superadmin.ts` and the design spec `docs/superpowers/specs/2026-06-25-superadmin-feature-flags-design.md`).
- Env var `SUPERADMIN_EMAIL` (server-side only — **no `NEXT_PUBLIC_` prefix**); defaults to `edmund@thegoodcompanysg.dev` when unset.
- Non-superadmin admins get no nav link and a 404 on direct visit.

## Credentials (all gitignored; `.example` files are committed)

| Platform | File | Mechanism |
|---|---|---|
| iOS | `iOS/Config.xcconfig` (from `Config.xcconfig.example`) | xcconfig → `Info.plist` `$(SUPABASE_PROJECT_URL)` / `$(SUPABASE_ANON_KEY)` → read in `SupabaseManager.swift`. **Escape `//` in the URL** — xcconfig treats `//` as a comment. |
| Android | `Android/secrets.properties` (from `secrets.properties.example`) | read at Gradle configure time → `BuildConfig.SUPABASE_PROJECT_URL` etc. |
| Web local | `web/.env.local` (from `.env.local.example`) | `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY` |
| Web prod (Vercel) | project env vars | the two above + `SUPABASE_SERVICE_ROLE_KEY` (invite/remove server actions) + `SITE_URL` (`https://dash.thegoodcompanysg.dev`, controls invite-email redirects) + optional `SUPERADMIN_EMAIL` |

Check prod: `cd web && vercel env ls production`. Add:
`printf 'value' | vercel env add VAR_NAME production` (then redeploy).

The service-role key is the ONLY secret credential (bypasses RLS — server-side
only, never in client code or `NEXT_PUBLIC_*`). The anon key is public by
design. The pre-commit scanner (`.githooks/pre-commit`) blocks staged
`SUPABASE_*_KEY=` assignments and raw JWT literals; enable per clone:
`git config core.hooksPath .githooks`.

## Other configuration axes

- **`supabase/config.toml`** — LOCAL stack only (signup disabled, site_url, etc.). Prod auth is dashboard-controlled and can drift from it (HUMANS.md §20/§31).
- **Kiosk PIN** — set in-app (gear → Kiosk Settings). No PIN = kiosk always in admin mode (demo default). Hash currently in UserDefaults (known weak point).
- **Edge function secrets** — `supabase/functions/notify-parent` needs APNs/FCM keys as Supabase function secrets before `push_notifications` flips (§17).
- **`iOS/project.yml`** — XcodeGen manifest (bundle id prefix `com.tava`, iOS 17 target, packages). The de-facto iOS build config; regenerate with `xcodegen generate`.
- **CI (`.github/workflows/ci.yml`)** — uses placeholder Supabase values; web lint+build, Android assembleDebug (JDK 17), non-blocking `supabase db lint`.

## Provenance and maintenance

Current as of 2026-07-09 (4 flags).
- Flags drift — always re-check: `SELECT key, enabled FROM feature_flags;` (per environment!)
- Vercel vars: `cd web && vercel env ls production`
- Gate default email: `grep -n 'thegoodcompanysg' web/lib/superadmin.ts`
- Example files still current: `ls iOS/Config.xcconfig.example Android/secrets.properties.example web/.env.local.example`
