# Pre-production security review — 2026-07-21

This review covered the Next.js dashboard, Supabase schema/RLS/Storage and Edge
function, iOS and Android clients, dependencies, secrets handling, and CI. It
did not mutate or deploy to production. Security is an ongoing control process;
this document is evidence and a release checklist, not a claim that the system
is impossible to compromise.

## Fixed in this change

- Database authorization now respects tutor assignment start dates, validates
  substitute tutors, binds every attendance write to the session class/current
  actor/server clock, and makes historical session edits RPC-only. An RLS-hidden
  mutation-receipt ledger prevents delayed offline retries from overwriting a
  later correction. Correction decisions now use a locked admin-only RPC that
  applies or rejects once and records a minimal disclosure in the same
  transaction; authenticated clients have read-only access to the queue.
  Parent core and specialty reads now use safe-column RPC
  projections instead of base-table policies that exposed staff notes, actor
  IDs, reviewer fields, and mutation IDs.
- Profile role transitions and feature-flag writes are enforced at the database
  boundary. A signed-in user cannot self-promote, and one UUID-based
  `security_principals` row is the source of superadmin authority for both the
  app and destructive database operations.
- The legacy-named anonymisation workflow now removes linked operational data,
  rotates student/attendance identifiers, and scrubs free text/actor data. It
  is documented and labelled as **pseudonymisation**, because retained
  session-level longitudinal facts can remain re-identifiable in a small
  cohort. Hard erasure remains the deletion-request path.
- Result-slip and student-photo Storage enforce private buckets, canonical
  student paths, bounded file sizes, and allowed MIME types. Erasure RPCs are
  no longer directly callable by authenticated clients: the trusted web flow
  recursively sweeps nested/legacy paths before and after the database commit,
  closing the upload race. Native erasure controls fail closed to that flow.
  Database-only retention also writes a durable cleanup queue consumed by a
  bounded, retrying Edge worker. Parent file uploads use rate-limited,
  server-minted path tokens, durable upload intents, content-signature checks,
  and an atomic service-only finalizer; abandoned intents and objects are
  claimed and removed without racing a valid finalization.
- Feature flags are enforced at Server Action and database write boundaries for
  parent portal, session notes, awards, and photo/result upload paths.
- Kiosk mode no longer exposes native navigation or privileged attendance
  actions while locked. Restarts/backgrounding revoke admin mode; PIN recovery
  requires device-owner authentication; sensitive App Intents and entity
  queries fail closed.
- Android blocks screenshots/screen recording and iOS covers inactive scenes so
  student data is not captured in recent-app snapshots.
- Native offline queues are now account-bound and fail closed: legacy, corrupt,
  mixed-owner, or foreign-account records are purged, sign-out clears pending
  data, and sync rechecks ownership immediately before the RPC. The JSON remains
  protected by the OS sandbox/device encryption rather than app-level
  Keystore/Keychain encryption.
- Native student profiles are capability-gated and identity-bound. Substitute
  tutors cannot open a misleading partial-history profile, result slips are
  offered only to parents/admins, and canceled or late Android requests cannot
  relabel one student's history, slips, or messages as another student's data.
- The web app uses exact Supabase CSP origins and additional browser security
  headers. Result-slip bytes upload directly to a path-scoped Supabase signed
  URL, avoiding the Vercel function-body limit; Server Actions authorize the
  intent, verify Storage metadata and file signatures, then atomically consume
  the intent while recording metadata. Render-time GET requests no longer
  mutate read state.
- Public/email signup defaults are off, password defaults are stronger, and the
  push Edge function validates bounded requests with a dedicated invocation
  secret instead of receiving the service-role JWT. Push registration and
  analytics use bounded RPCs; provider setup, fan-out, timeouts, and stale-token
  cleanup are isolated so one bad token/provider cannot suppress the other.
- Current-tree and staged secret scanning is redacted and fail-closed. The
  review did find a real App Review credential in reachable Git history and a
  production database credential in an ignored owner-only local note. Those
  values are not reproduced here; both require rotation before release.
- CI third-party actions and the Supabase CLI are immutable-version pinned;
  workflows use read-only repository permissions, verify the Gradle wrapper,
  audit all npm dependencies, type-check Edge Functions, replay/lint migrations,
  run SQL regressions, and assert critical production grants/RLS/Storage state
  that structural drift filtering cannot safely compare.

## Required before production

1. Disable/rotate the exposed App Review admin credential, update App Store
   Connect, and remove it from all reachable Git history (currently 63
   revisions). Rotation is mandatory even if history is rewritten.
2. Rotate the production database password found in the ignored local operator
   note; update authorized pooler/deployment consumers and revoke the old value.
3. Require pull requests on `main`: passing CI/security checks, review,
   CODEOWNERS, protected deployment environments, admin enforcement, and no
   force-push/deletion. The repository currently has no effective protection.
4. Replay migration 038 and every SQL regression against a clean Postgres/Supabase
   runtime, then apply it before dependent clients. Static parsing passed, but
   local runtime replay was unavailable because Docker/Postgres was not running.
5. Run `scripts/prod-security-check.sql` and require exactly one valid admin
   `security_principals(capability='superadmin')` row.
6. Deploy both Edge Functions, install matching dedicated Edge/Vault invocation
   secrets, and verify the Storage cleanup cron drains its queue.
7. Deploy the hardened web build and verify production serves its exact-origin
   CSP and new security headers; the site observed during review still served
   the older wildcard Supabase policy.
8. Mirror `supabase/config.toml` Auth settings in the hosted project and verify
   Vercel's server-only environment values.
9. Obtain DPO/legal acceptance of pseudonymised attendance retention, or use
   hard erasure where the required outcome is no reasonably linkable history.
10. Implement TOTP MFA and AAL2 enforcement for privileged accounts.
11. Require a configured kiosk PIN and plan a least-privileged kiosk identity;
    do not treat a full admin JWT plus a client-only PIN as the final boundary.
12. Exercise account-transition/legacy-queue purging on physical shared devices,
    then add app-level Keystore/Keychain authenticated encryption and move the
    Android auth session manager off plaintext SharedPreferences.

The detailed operational checklist is in `HUMANS.md` §P.
