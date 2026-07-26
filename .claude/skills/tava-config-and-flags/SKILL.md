---
name: tava-config-and-flags
description: Use when adding or flipping a feature flag, adding configuration, troubleshooting a hidden feature, or reviewing credentials and privileged principals.
---

# TAVA configuration and flags

## Runtime feature flags

`feature_flags` is read by iOS `FeatureFlagStore`, Android `FeatureFlags`, web
`getFeatureFlags()`, and selected database guard functions. Migration seeds are
defaults, not live-state evidence.

| Key | Surface |
|---|---|
| `parent_portal` | parent attendance/results/messages on all clients |
| `push_notifications` | APNs/FCM attendance/dismissal and safely-home loop |
| `student_photos` | private Storage-backed avatars |
| `study_space_tracking` | internal drop-in attendance |
| `test_mode` | bypasses normal day filters for controlled testing |
| `session_notes` | tutor session notes |
| `qr_sign_in` | kiosk camera sign-in and printable QR |
| `awards` | web awards workflow |
| `analytics` | bounded product events and health/activity views |
| `retrospective_sessions` | authorised past-session/correction workflow |

Always measure:

```sql
SELECT key, enabled, description
FROM feature_flags
ORDER BY key;
```

A global flip is a separate human-gated production change. Verify every
surfacing client/version and the server-side guard first. `test_mode` must be
off outside a controlled test window.

### Add a flag

1. Add a new numbered migration and paired `down/` script; seed OFF.
2. Gate every applicable client and database write path; missing/error defaults
   to OFF.
3. Add automated role/flag regression coverage.
4. Add a numbered HUMANS.md activation/QA item.
5. Apply migration before clients and verify live state before a separate flip.

## Privileged principal

Migration 038 replaced the `SUPERADMIN_EMAIL` environment gate. Exactly one
database row in `security_principals(capability='superadmin')` is the authority
for feature flags, destructive wipe/export and privileged admin management.
The table is not Data-API-readable by ordinary authenticated users.

Verify through the read-only production security script. Rotate the principal
in a reviewed transaction; do not leave zero or multiple valid principals and
do not attempt to reintroduce an application email override.

## Credential/configuration locations

| Platform | Location | Rules |
|---|---|---|
| iOS | gitignored `iOS/Config.xcconfig` | Supabase URL/anon key only; escape xcconfig `//` |
| Android | gitignored `Android/secrets.properties` | Supabase public config plus release keystore references; auth session material is Keystore-encrypted at runtime |
| Web local | gitignored `web/.env.local` | public Supabase URL/anon key; server secret only when testing trusted actions |
| Vercel production | project environment | public URL/anon key, server-only service role, `SITE_URL` |
| GitHub protected workflows | repository/environment secrets | `TAVA_DB_URL`, Supabase access token/DB password only for protected-main remote checks |

The service-role key and database credentials are secrets. The anon key is
public by design, but raw JWT-looking values are still blocked from Git to
prevent confusion and accidental credential commits. Enable:

```bash
git config core.hooksPath .githooks
```

Never put a secret literal in a shell command, ticket, transcript or committed
`.example` file.

## Other security-sensitive configuration

- `supabase/config.toml` controls local Auth only. Verify production signup,
  password, secure-change and MFA settings separately.
- Kiosk PIN is device-local; no PIN means unsafe admin mode. The iOS verifier
  still needs Keychain migration and the kiosk still holds an admin session.
- `notify-parent` and `cleanup-student-storage` each require dedicated
  invocation secrets; provider/service-role credentials must not be reused as
  invocation tokens.
- `iOS/project.yml` is the Xcode source of truth; regenerate after edits.
- `.github/workflows/ci.yml`, `remote-security.yml`, and `advisors.yml` are the
  executable CI/production-check configuration.

## Provenance

Audited 2026-07-26 against migrations 012, 015, 020, 026, 031, 037 and 038,
all three flag clients, Vercel env usage and current workflows. Live flag and
hosted Auth state remain query/dashboard facts.
