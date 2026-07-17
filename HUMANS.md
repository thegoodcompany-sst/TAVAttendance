# HUMANS.md — actions only a human can complete

Some PDPA (and related) compliance and operational steps cannot be done in code or by an agent.
They need a person with organisational authority, legal judgement, or access to dashboards/contracts.
**The technical controls are in place; these items make the compliance real and lawful.**

Tracking key: ☐ = to do · ☑ = done. Owner: the Centre's Data Protection Officer unless noted.

---

## A. Must-do for PDPA compliance

### ☐ 1. Appoint a Data Protection Officer (DPO) — *s11(3), mandatory*
Designate a DPO and **publish a business contact** (name/role + email/phone). Then fill it into:
- `docs/pdpa/DATA_PROTECTION_NOTICE.md` (the "Data Protection Officer" line), and
- the in-app notice: update the `policy_documents` row (see §B for how to re-publish).

### ☐ 2. Legal/DPO sign-off on the governance documents
Review and approve, then mark as published (remove "DRAFT"):
- `docs/pdpa/DATA_PROTECTION_NOTICE.md`
- `docs/pdpa/DATA_RETENTION_SCHEDULE.md`
- `docs/pdpa/DATA_BREACH_RESPONSE_PLAN.md`
The 7-year retention period and the consent-for-minors approach in particular should be confirmed
with counsel.

### ☐ 3. Confirm the consent wording is legally valid for minors
We record parent/guardian consent by **admin attestation** (the Centre collects consent offline at
enrolment and an admin attests in-app). Confirm the **paper/portal consent form** parents sign
covers all purposes in the notice, and keep those signed forms on file.

### Leaked-password protection — not possible on the free plan
Auth → Providers → Password → "Leaked password protection" (HaveIBeenPwned) requires a paid
Supabase plan. Not actionable until the project is upgraded.

### ☑ 5. Verify data residency (region) — DONE
Confirmed the live Supabase project region is Singapore (ap-southeast-1) and backups/replicas
do not leave Singapore, via Dashboard → Project Settings → General/Infrastructure.

### ☐ 6. Sign the Supabase Data Processing Addendum (DPA)
Supabase is a data intermediary. Execute their DPA and record it in the accountability file.
(Reference: https://supabase.com/legal/dpa)

---

## B. Operational follow-ups

### ☐ 7. Re-publish the in-app notice after edits
The app shows the notice from the `policy_documents` table. After editing the source doc, publish a
new version:
```sql
UPDATE policy_documents SET is_current = false WHERE doc_type='data_protection_notice';
INSERT INTO policy_documents (doc_type, version, title, body)
VALUES ('data_protection_notice', '1.1', 'TAVA Attendance — Data Protection Notice', '<new text>');
```

### ☑ 8. Retention purge job (pg_cron) — DONE
`pg_cron` is enabled and the daily job `pdpa-daily-purge` (18:20) is scheduled and active. Verify:
```sql
SELECT * FROM cron.job WHERE jobname='pdpa-daily-purge';
SELECT purge_expired_personal_data();  -- safe to run manually; returns counts
```
If the project is ever restored/migrated and pg_cron is missing, re-run `011_pdpa_compliance.sql`
or schedule the job manually.

### ◐ 9. Finish scheduled Storage object cleanup
Explicit admin-driven erase/anonymise now deletes objects from both private
`result-slips` and `student-photos` buckets in the web, iOS, and Android clients
before calling the database RPC (implemented 2026-07-16; path convention:
`<student_id>/<file>`). The daily seven-year `pg_cron` purge still runs entirely
inside Postgres and cannot call Supabase Storage, so it can leave orphaned files.
Add and monitor a server-side orphan cleanup before marking this item complete.

### ☐ 10. Turn on Supabase log/security alerting
Enable log drains/alerts and review `get_advisors` (security + performance) regularly — this backs
the Data Breach Response Plan's detection step.

### ☐ 11. Maintain the breach register
Keep `docs/pdpa/DATA_BREACH_RESPONSE_PLAN.md`'s register up to date; review the plan annually.

---

## C. App Intents / Siri (PR #1, merged 2026-06-24)

### ☐ 12. End-to-end Siri / Shortcuts voice testing (cannot be automated)
The build compiles and all 7 intents pass App Intents metadata validation, but spoken
invocation needs a real device/Siri and a signed-in **admin** session (the kiosk is admin-only).
On an admin-signed-in build, verify in the Shortcuts app + Siri:
- "Sign in <student>" → marks On Time/Late; spoken status matches the kiosk card.
- "Mark <student>'s attendance" → Siri prompts for status; "Absent" asks for confirmation first.
- "Is <student> here today?" / "What's <student>'s attendance rate?" / "How punctual is <class>?"
  / "How many students have signed in?" → spoken numbers match Student Profile / kiosk / punctuality.
- "Open the sign-in kiosk" → app opens on the Sign-In tab.
- Signed-out / non-admin caller → friendly spoken error, no crash.

### ☐ 13. Wire Supabase credentials into the iOS build
Decide how the two credentials reach the Info dictionary on a fresh checkout: add
`SUPABASE_PROJECT_URL` / `SUPABASE_ANON_KEY` to `iOS/project.yml` `info.properties` as
`$(SUPABASE_PROJECT_URL)` / `$(SUPABASE_ANON_KEY)`, and make sure the `//` in the `https://` URL in
`Config.xcconfig` is escaped (an unescaped `//` is read as an xcconfig comment). Left for a human
since it touches credential wiring / security setup.

---

## D. Migrations & feature flags

### ☑ 14. Finish applying migrations 012–015 to the live project — DONE (2026-07-09)
Full drift reconciliation completed via MCP `apply_migration`, in order:
`005_backfill_prod_columns` (late_reason, recurrence_rule/_end_date) →
`004_security_fixes_backfill` (profiles policies; 004 had never been applied — prod still had the
world-readable profiles policy AND the self-role-escalation WITH CHECK) → `013_audit_fixes` →
`014_feature_tables` (with a `DROP FUNCTION get_session_roster(uuid)` prereq, 42P13) →
`015` re-applied (restores its study-space filters over 014's function versions) →
`005_backfill_parent_link_fns` → `016_security_fixes` → `017_advisor_followups`.
Verified: all gate queries in `.claude/skills/tava-prod-drift-campaign` passed; advisors show only
the accepted WARNs. Prod now matches migrations 001–017.

### ☑ 59. Apply migration 034 (privacy/authorization hardening) to prod — DONE (2026-07-17)
Applied via MCP `apply_migration` after verifying all 21 prerequisite functions and the current
data-protection notice existed in prod. Adds `create_student_with_consent` RPC + restrictive
insert/consent policies, removes the `handle_new_user` bootstrap-admin exception, excludes Study
Space from the export/punctuality RPCs, scopes tutor grade access, and pins SECURITY DEFINER
search_paths. Migration's own ASSERT block passed; unblocked the PR #3 drift detector (was failing
on the missing RPC). Reverse script: `supabase/migrations/down/034_privacy_authorization_hardening.sql`.

### ☐ 16. Flip feature flags when each feature is ready
Features ship OFF. Enable per platform-ready feature:
```sql
UPDATE feature_flags SET enabled = true WHERE key = 'parent_portal';      -- PROD-01
UPDATE feature_flags SET enabled = true WHERE key = 'student_photos';     -- PROD-04
UPDATE feature_flags SET enabled = true WHERE key = 'push_notifications'; -- PROD-02
```
Before enabling `parent_portal`, verify with a real parent account: assigned children appear;
attendance excludes Study Space; a PDF/JPG/PNG result slip uploads and opens; a parent message
appears at admin `/messages`; an admin reply appears in the parent thread; acknowledgement appears
on the parent slip. Migrations 035–036 and the web deployment are live as of 2026-07-17.

### ☐ 17. Provide APNs credentials for push (PROD-02) — configs DONE 2026-07-14, flag still OFF
1. ☑ Function secrets set 2026-07-14: `APNS_KEY` (AuthKey_U968QPQQ67.p8), `APNS_KEY_ID=U968QPQQ67`,
   `APNS_TEAM_ID=DUU8J39BA7`. `APNS_TOPIC` defaults to `com.tava.TAVAttendance`; `APNS_HOST`
   defaults to prod (`api.push.apple.com`) — set `https://api.sandbox.push.apple.com` for dev builds.
2. ☑ Vault secret `notify_parent_service_key` seeded 2026-07-14 — the DB trigger is armed but the
   edge function still no-ops while `push_notifications` is OFF.
3. ☐ Enable Push Notifications on the App ID (§38), set `FCM_SERVICE_ACCOUNT` (download the
   service-account JSON from Firebase Console → Project settings → Service accounts, then
   `supabase secrets set FCM_SERVICE_ACCOUNT="$(cat <file>.json)"`), then flip
   `push_notifications` per §16.

### ☐ 18. Finish the Android port UI follow-ups
iOS, web, and Android all compile. Still to do: run a full `./gradlew assembleDebug` (exercises R8 +
the new ProGuard keep rules) and complete the Compose UI parity items listed in
`Android/PORTING_NOTES.md` (kiosk UX + parent screen + FCM).

### ☐ 19. Enable the secret-scanning pre-commit hook (DEVOPS-03)
Per clone: `git config core.hooksPath .githooks`.

### ☐ 20. Mirror/verify production Supabase `[auth]` + monitoring (DEVOPS-04/05)
Confirm prod auth settings match `config.toml`, and set up the uptime monitor /
Supabase status subscription described in `CONTRIBUTING.md` §6.

---

## E. Superadmin feature-flags web section

A `/feature-flags` admin page lets the superadmin toggle the `feature_flags`
rows from the web dashboard (an alternative to the SQL in §16). Access is gated
**app-layer only** to one email — the DB RLS write policy stays at `is_admin()`
(intentional; documented in `web/lib/superadmin.ts` and the design spec).

### ☑ 21. (Optional) Set `SUPERADMIN_EMAIL` in Vercel — DONE
The gate defaults to `edmund@thegoodcompanysg.dev` if unset. `SUPERADMIN_EMAIL` env var
(no `NEXT_PUBLIC_` prefix) is set in the Vercel project and deployed.

### ☑ 22. Manual sign-in verification (needs the running app + real accounts) — DONE
Cannot be automated (requires Supabase auth + accounts). With the web app running:
- Sign in as `edmund@thegoodcompanysg.dev`: a **"Feature Flags"** link appears in the
  sidebar (and mobile nav); `/feature-flags` lists the seeded flags
  (`parent_portal`, `push_notifications`, `student_photos`, `study_space_tracking`); toggling a flag persists
  across a page reload.
- Sign in as a **different admin**: no "Feature Flags" link, and visiting
  `/feature-flags` directly returns a **404**.

### ☐ 23. Review the Chinese (Simplified) UI translations
iOS localization uses a String Catalog (`iOS/TAVAttendance/Localizable.xcstrings`) with
**English source + best-effort `zh-Hans` translations** for the Privacy Notice screen. The
notice term is set to **"数据保护声明"** (data protection notice) to match
`docs/pdpa/DATA_PROTECTION_NOTICE.md`. A native speaker should review overall wording
before shipping. Edit translations in Xcode's String Catalog editor (open `Localizable.xcstrings`).
Strings covered: Loading…, Version %@, Notice Unavailable, Privacy, Done, Privacy Notice, and the
two load-failure messages. Other app screens are not yet localized — adding them is the next step.

---

## F. Study Space tracking (2026-06-26)

### ☑ 24. Apply migration `015_study_space_and_notice.sql` to the live project — DONE
Applied to prod 2026-06-27 via MCP `apply_migration` (plus the `students.avatar_url` prereq) —
see §14. Kept for the record; original text below.
Adds `classes.is_study_space` + the singleton Study Space class, seeds the
`study_space_tracking` flag (OFF), adds `get_study_space_roster`, excludes study space from
`attendance_summary` + `get_roster_for_date`, and publishes Data Protection Notice **v1.1**.
The notice and flag parts are independent of the §14 work, but verify the column/function
changes apply cleanly against the live schema first (use a dev branch if unsure).
Paired down migration: `supabase/migrations/down/015_study_space_and_notice.sql`.

### ☐ 25. Finish DPO contact on the v1.1 notice — *ties into §1/§2*
The v1.1 notice names **Talent Beacon** as the controller and `admin@talentbeacon.org` /
209 Bukit Batok Street 21, #01-182 as the contact, but the **DPO name/role** is still a
placeholder in `docs/pdpa/DATA_PROTECTION_NOTICE.md` and the seeded `policy_documents` v1.1 body.
Fill it in and get legal/DPO sign-off (removes "DRAFT v1.1").

### ☐ 26. Flip `study_space_tracking` when the Study Space feature is ready
Ships OFF. Enable per §16 (or via the superadmin `/feature-flags` page) **only after** the
Android + web ports land, so study-space sessions never exist before every reporting surface
excludes them:
```sql
UPDATE feature_flags SET enabled = true WHERE key = 'study_space_tracking';
```

### ☑ 28. Unblock the full Android build/test on this machine (environment) — DONE
JDK 17/21 blocker resolved, see §34. `./gradlew testDebugUnitTest` (includes `DayAwareKioskTest`)
now runs; `assembleDebug` still to be run to exercise R8/ProGuard.

---

## G. Refactor follow-up (2026-07-03)

### ☑ 29. Decide whether to wire `PdpaPanel` into the web student detail page — DONE (see §52)
`web/app/(admin)/students/[id]/pdpa-panel.tsx` (plus `getStudentConsent` and the
withdraw/anonymise/erase/export actions behind it) has never been imported by
`students/[id]/page.tsx` — it looks like the panel was built and never wired in.
It is the s16/s21/s25 PDPA machinery, so it was deliberately NOT deleted in the
2026-07 refactor. Decide: wire it into the student page (one import + render), or
schedule it with the PDPA app-UI work.
**2026-07-10: deliberately left unwired for demo day** — it puts destructive
Erase/Anonymise buttons on the exact page being demoed. Wire it after the demo.

---

## H. Security audit follow-up (2026-07-06)

Code/migration fixes from the 2026-07-06 audit are committed (migration `016_security_fixes.sql`,
iOS/Android/web patches). These remaining items need a human with dashboard/prod access.

### ☑ 30. Apply migration `016_security_fixes.sql` to the live project — DONE (2026-07-09)
Applied as part of the §14 reconciliation. Gate output:
`SELECT reloptions FROM pg_class WHERE relname='attendance_summary';` → `{security_invoker=true}`
(the leak is closed); study-space rows in `attendance_summary` → 0; `handle_new_user` is
SECURITY DEFINER with pinned search_path and defaults new users to least-privilege `parent`;
`sync_attendance` catches only SQLSTATE `TA001`; dismissals FKs cascade. Migration `017`
(advisor follow-ups: search_path pin on `check_session_not_ended`, anon revokes on
`class_punctuality` + parent-link fns) was added and applied the same day.

### ☑ 31. Disable public sign-ups in the prod Supabase dashboard — DONE
Auth → Providers → Email → turned **OFF** "Allow new users to sign up". Every account is created by
admin invite; public signup + metadata role was the admin-escalation vector. `supabase/config.toml`
is already set to `enable_signup = false` for local, but prod auth is dashboard-controlled.
(Migration 016 also hardens `handle_new_user` so metadata can no longer mint privileged roles even
if signup is on, and `web/app/actions/invite.ts` now sets the invited role via the service role
after creation — but keep public signup off as defence in depth.)

### ☐ 32. (Optional) Rotate the Supabase anon key
The public GitHub history contains the **anon** key (not service_role) — public-by-design, security
rests on RLS, so rotation is not strictly required. If you want defence-in-depth, rotate to the new
publishable/secret key pair in the dashboard and update all three platforms' config. History rewrite
is pointless (the key is legitimately shipped in every client).

### ☐ 33. iOS kiosk PIN — confirm Keychain migration on a real device
If the iOS fix moved the kiosk PIN hash from UserDefaults to Keychain, verify on a physical iPad that
an existing PIN still validates after upgrade and that a restored/migrated device isn't permanently
locked (the pre-fix bug). If the migration was deferred (left as a TODO), the UserDefaults+idfv
lock-out risk remains — see the `ponytail:` note in `GlobalKioskView.swift`.

### ☑ 34. Install JDK 17 or 21 to unblock Android unit tests — DONE
`brew install --cask temurin@21` installed; `./gradlew test` (including `DayAwareKioskTest`)
now runs on this machine.

### ☐ 35. Add CI secrets so the drift-detector job runs (GitHub → repo Settings → Secrets and variables → Actions)
- `TAVA_DB_URL` — prod Postgres connection string (Supabase Dashboard → Connect → Session pooler URI)
- `SUPABASE_ACCESS_TOKEN` — a Supabase personal access token
- `SUPABASE_DB_PASSWORD` — the prod database password

Until these are set, the CI `Drift detector` job logs a warning and skips (CI stays green).
`SUPABASE_ACCESS_TOKEN` also arms the weekly `Advisor watch` workflow (added 2026-07-13:
diffs Supabase security/performance advisors against `scripts/advisor-accepted.json` and
fails on new findings), which is likewise dormant until the secret exists.
Heads-up: the first `supabase db diff --linked` run may surface residual diff left over from the
2026-07-09 reconciliation — triage that output before treating the job as a hard gate.

**Status 2026-07-10 (end of day): fully live and green.** Secrets added; both halves run on
every push — the web-schema check and a live-to-live `db diff` (prod vs a replayed local DB;
the shadow-based `--linked` mode false-positives on the `security_invoker` view). Privilege
statements are filtered as platform noise; structural DDL fails the job.

### ☑ 36. Decide: fix the invalid syntax in migration 005 to make the chain replayable — DONE (2026-07-10)
Approved and fixed: 005's two `CREATE POLICY IF NOT EXISTS` became `DROP POLICY IF EXISTS` +
`CREATE POLICY`; the CI shadow-provisioning skip was removed. Bonus find while fixing: prod had
NO substitute-tutor policies at all (the reconciliation missed them) — restored as migration
018 (applied to prod, verified). Original item below for the record.

### Original §36 text
CI's `supabase db diff` found that `005_sprint_features.sql` uses `CREATE POLICY IF NOT EXISTS`,
which is not valid Postgres — the migration chain cannot be replayed onto a fresh database
(shadow DB, new dev machine, disaster recovery), and the native drift diff can't run.
Prod never executed this file as-is (its 005 content arrived via the 2026-07-09 timestamped
backfill migrations), so editing the file would not obscure what prod ran — but it breaks the
"never edit an existing migration" rule, so it needs your sign-off. If approved: replace each
`CREATE POLICY IF NOT EXISTS` with `DROP POLICY IF EXISTS …; CREATE POLICY …` (same end state),
then remove the shadow-provisioning skip in `.github/workflows/ci.yml`. Until then the CI db-diff
step logs a warning and skips.

---

## I. Demo day (2026-07-11)

### ☑ 37. After demo day: flip `test_mode` OFF and delete the demo data — DONE 2026-07-12
Done via agent session 2026-07-12: `test_mode` OFF; all 4 demo sessions (Jul 10 **and**
11 — the "Lycia" classes), their 12 attendance records and 9 dismissals deleted; the 4
duplicate demo classes + 12 enrollments deleted per Edmund's instruction. Verified:
0 sessions ≥ 2026-07-10 remain, guard trigger re-enabled, `parent_portal` /
`student_photos` were already OFF. Original context:
Migration 020 seeded the `test_mode` flag **ON** so the Saturday demo works (kiosk
shows all classes regardless of weekday; analytics shows all days). After the demo:
```sql
UPDATE feature_flags SET enabled = FALSE WHERE key = 'test_mode';
DELETE FROM attendance_records
 WHERE session_id IN (SELECT id FROM sessions WHERE session_date = '2026-07-11');
DELETE FROM sessions WHERE session_date = '2026-07-11';
```
The DELETEs are load-bearing, not cosmetic: `attendance_summary` and the monthly-drop
analytics aggregate **all** dates, so leftover Saturday rows would permanently skew
real students' attendance percentages. Also flip `parent_portal` / `student_photos`
back OFF if they were turned on for the demo (§16).

### ☐ 38. Enable Push Notifications capability on the App ID
**Blocked on a paid Apple Developer Program membership** — personal teams cannot
sign the Push capability at all ("Personal development teams … do not support the
Push Notifications capability", hit 2026-07-11), so the `aps-environment`
entitlement was removed from `iOS/project.yml` that day to unblock device builds
(the restore snippet is commented in the file). Once on a paid team:
Apple Developer portal → Identifiers → `com.tava.TAVAttendance` → enable Push
Notifications, then restore the commented `entitlements:` block and rerun
`xcodegen generate`.

---

## J. Go-live: test batch (planned 2026-07-12, date TBD)

Launch bar (Edmund's decision): **full PDPA close-out before any real student data.**
MVP scope: kiosk sign-in + tutor roster marking + admin web dashboard; nothing parent-facing.
Plan details: `PDPA_COMPLIANCE.md` §4c + agent memory `project_launch_plan`.

### ☐ 39. Provide the launch date and the roster CSV
2–3 test-batch classes. The CSV (any format) gets inserted directly via SQL — send it
to the agent when it arrives.

### ☐ 40. Appoint the DPO and finish the notice (same as §1/§2/§25)
Still the hard blocker for the launch bar: DPO name/contact into the notice, then
legal/DPO sign-off on the three `docs/pdpa/` documents.

### ☐ 41. Attest consent per student before their first class
Decision 2026-07-12: consent is collected offline and an admin attests it **in-app**
before that student's first session. Easiest path: import the roster CSV via
**`/students/import`** on the dashboard — its attestation checkbox writes a granted
`consent_records` row per created student automatically (QA-verified 2026-07-12:
the erase/anonymise/export backend all pass; the export now includes grades, mig 025).

### ☐ 42. Kiosk iPad setup on launch day
Signed in as an **admin** account (RLS makes a tutor login useless for the kiosk),
kiosk PIN set, AltStore refresh routine confirmed (personal-team signing expires
every 7 days — keep AltServer reachable on the same Wi-Fi).

### ☐ 43. Flip the new feature flags when ready (migration 026, all OFF)
Shipped dark 2026-07-12; flip via the superadmin `/feature-flags` page when the
preconditions hold. A flag is global — every platform must handle it first.

- [ ] `session_notes` — flip once tutors want it; iOS + Android + web all handle it.
- [ ] `qr_sign_in` — print the student QR sheet from the dashboard first
      (`/students` QR page, visible once the flag is ON — so flip, print, done).
      iOS kiosk needs camera permission granted on the iPad on first scan.
- [ ] `awards` — web-only admin page; flip whenever you want to start recording awards.

### ☐ 44. App Store submission — remaining blockers (2026-07-13)
Version 1.0 in App Store Connect is staged: metadata, age rating, free pricing (base SGP),
build 3 attached, release type MANUAL, review demo account
`apple-testing@example.com` / `apple-review-tester` (admin role, created in prod Supabase).
`asc validate --app 6790169580 --version 1.0` reports two blockers:

- [ ] **Availability** — run `asc web auth login --apple-id <your Apple ID>` once
      (interactive 2FA), then Claude can run
      `asc web apps availability create --app 6790169580 --territory SGP --available-in-new-territories false`.
      Or set it in ASC → Pricing and Availability.
- [ ] **Screenshots** — at least one device size (6.9" iPhone + 13" iPad since the app
      supports iPad). Take on device/simulator signed in as the review account — do NOT
      screenshot real student names (PDPA).
- [ ] **App Privacy labels** — dashboard-only: https://appstoreconnect.apple.com/apps/6790169580/appPrivacy
      (declares: name, contact info; linked to identity; not used for tracking).

### ☐ 45. Request unlisted app distribution from Apple
After §44 is done and the app is submittable, fill in the request form at
https://developer.apple.com/support/unlisted-app-distribution/ with app ID 6790169580.
Apple replies by email; only then submit for review. Release stays MANUAL, so approval
will not auto-publish.

---

## Notes
- Accepted/intentional advisor warnings: the `is_admin()/is_parent()/...` and the
  `anonymise_student/erase_student/export_student_personal_data` SECURITY DEFINER functions are
  callable by `authenticated` **by design** — each guards with `is_admin()` (or is required by RLS).
  `rate_limit_events` has RLS on with no policy **by design** (service-role only).
- The Supabase anon key is public-by-design; rotate it via the dashboard if this repo ever goes public.

## §38 — Firebase App Distribution (Android) — one-time interactive setup

Android release signing + build are wired (2026-07-12). Remaining steps need your Google login:

- [x] `firebase login` — done 2026-07-12.
- [x] App registered; App ID `1:879371219921:android:dc7a8dbf4d8df141bf66f0`
      (now the default in `distribute.sh` — just run `./distribute.sh`).
      Release workflow lives in `.claude/skills/release`.
- [ ] Keep `Android/release.jks` + the `KEYSTORE_*` values in `secrets.properties`
      backed up somewhere safe — losing them means you can't ship an update under
      the same signing identity.

---

## K. Pre-go-live PDPA checklist (2026-07-13)

Consolidated from the prod audit (`docs/pdpa/AUDIT_2026-07-13.md`). The audit confirmed the
technical machinery is in place and matches the docs (consent ledger, export/anonymise/erase RPCs,
current notice v1.1 live and served at the public privacy page, `attendance_summary` still
`security_invoker`, daily purge job active, no new security-advisor findings). **These items are
the human/legal work that must be closed before real student data goes in.** Do them in order.

### ☐ 46. Appoint + register the DPO and put the contact into the notice (blocks §1/§2/§40)
Designate the DPO and publish a business contact. Then fill the name/contact into
`docs/pdpa/DATA_PROTECTION_NOTICE.md` **and** re-publish the in-app notice (bump the
`policy_documents` row per §7). The DPO placeholder currently shows as "[email protected]" on the
public page — it must be a real contact before distributing anything to parents.

### ☐ 47. Legal/DPO sign-off on the three governance docs (same as §2)
Approve and remove "DRAFT" from `DATA_PROTECTION_NOTICE.md`, `DATA_RETENTION_SCHEDULE.md`,
`DATA_BREACH_RESPONSE_PLAN.md`. Confirm the 7-year retention period and the consent-for-minors
approach with counsel.

### ☐ 48. Print + distribute the parent consent pack
`docs/pdpa/CONSENT_PACK.md` is the print-ready parent-facing document (one-page plain-English
summary + a consent form that maps 1:1 to the single `data_collection` consent the system records +
withdrawal instructions). **Fill in the DPO name/contact first** (item 46), then print and hand one
to each parent/guardian at enrolment. Keep every signed form on file.

### ☐ 49. Validate the signed consent form wording covers every notice purpose (same as §3)
Before collecting real signatures, confirm the consent pack's wording covers all six purposes in
the notice and is legally valid for minors (parent/guardian consent).

### ☐ 50. Attest consent per student before their first class (same as §41)
Collect the signed form offline, then have an admin attest it in-app — easiest via
`/students/import` on the dashboard, whose attestation checkbox writes a granted `data_collection`
`consent_records` row per created student. Audit note: the 8 students currently in prod are test
data with only 2 consent rows — do not treat these as real, cleared records.

### ☐ 51. Decide on leaked-password protection (conscious call, not a miss)
Security advisor still flags `auth_leaked_password_protection` as OFF. Per §4 it needs a **paid**
Supabase plan (HaveIBeenPwned check). Either upgrade the plan and turn it on
(Auth → Providers → Password), or accept the risk in writing. Not a blocker, but record the
decision.

### ☑ 52. Confirm PdpaPanel is live on the web student page — DONE (verified 2026-07-13)
The audit found `PdpaPanel` is wired into `web/app/(admin)/students/[id]/page.tsx` (renders consent
ledger + withdraw + export + anonymise/erase). This supersedes the open question in §29 — §29 can
be marked done.

---

## L. TestFlight staff trial (date TBD — waiting on the centre)

The guided test kit is ready in `docs/test-kit/` (STAFF_GUIDE.md + a 15-minute
TEST_SCRIPT.md). These are the day-of steps only a human can do.

### ☐ 53. On the confirmed trial morning: seed the demo data
Apply `docs/test-kit/SEED_DEMO_DATA.sql` to prod (5 "Demo …" students + 1 ad-hoc
demo class with fixed UUIDs), and run `docs/test-kit/TEARDOWN_DEMO_DATA.sql` the
same day after the trial, before anyone reads reports — demo rows must not skew
`attendance_summary`. If staff will run Part C (tutor roster) with a tutor login,
fill a real tutor UUID into the commented `class_tutor_assignments` insert first.

### ☐ 54. Hand the staff their access
Give the trial staff the admin login for the kiosk iPad and have them set a kiosk
PIN (the test script walks them through it). Print or send `STAFF_GUIDE.md` and
`TEST_SCRIPT.md`.

### ☐ 55. (Optional) richer screenshots for the guide
Only the login screen could be captured safely — the current prod test students
carry real-looking names (PDPA), and the simulator has no scriptable tap tooling.
If you want full screenshots in the guide: capture them manually on the iPad after
§53's demo students are seeded (their names are PDPA-safe), or rename the
name-like test students in prod first.

---

## M. Push notifications: FCM + safely-home loop (2026-07-13, shipped dark)

Migration 030 is applied to prod (dismissal trigger + `mark_safely_home` RPC, both inert);
the `notify-parent` edge function v2 routes iOS→APNs / Android→FCM. Remaining human steps:

### ☐ 56. Create the FCM service-account secret
Firebase console → project settings → Service accounts → **Generate new private key**, then:
```sh
supabase secrets set FCM_SERVICE_ACCOUNT="$(cat key.json)" --project-ref zgikcbsxzjgbigywxbbj
```
Never commit the key. (APNs secrets remain the separate, still-pending §17 items.)

### ☐ 57. Arm the trigger + flip the flag (same Vault step as §17)
Both 021 and 030 triggers stay no-ops until the Vault secret
`notify_parent_service_key` exists (§17 step 2). Then flip `push_notifications` —
but only after the iOS `aps-environment` entitlement is restored (§38 recipe in
project.yml; needs a paid Apple team) — the iOS client code (token registration +
safely-home card) is already in place. iOS loads flags once at sign-in: relaunch
after flipping. On first Android run, the parent must accept the notification
permission prompt (Android 13+).

---

## N. Analytics and observability (2026-07-14, shipped dark)

Migrations 031–033 are applied to prod. Web, iOS, and Android capture code is built behind
the global `analytics` flag; raw events retain for 90 days.

### ☐ 58. Flip `analytics` after the Android CI build is green

Preconditions met 2026-07-14: production web deploy is healthy, iOS XCTest passed 19/19,
and PR #2 CI passed the Android build. The flag remains OFF pending a deliberate rollout.

```sql
UPDATE feature_flags
SET enabled = TRUE, updated_at = NOW()
WHERE key = 'analytics';
```

Verify:

```sql
SELECT key, enabled FROM feature_flags WHERE key = 'analytics';
SELECT jobname, active FROM cron.job WHERE jobname = 'app-events-purge';
```

Then fully relaunch iOS and Android so their once-per-sign-in flag caches reload. Click through
staff screens and confirm `/activity` receives events and `/health` renders without errors.
