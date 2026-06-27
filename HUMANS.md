# HUMANS.md — actions only a human can complete

Some PDPA (and related) compliance steps cannot be done in code or by an agent. They need a
person with organisational authority, legal judgement, or access to dashboards/contracts.
**The technical controls are in place; these items make the compliance real and lawful.**

Tracking key: ☐ = to do · ☑ = done. Owner: the Centre's Data Protection Officer unless noted.

---

## 0. Verify now (2026-06-27 prod fix)

- ☐ **Log into `https://dash.thegoodcompanysg.dev` as an admin and confirm the dashboard
  loads** (no "This page couldn't load"). Background: the deployed web filtered
  `classes.is_study_space`, a column missing from prod → dashboard 500. Fixed by applying
  migration **015** + the `students.avatar_url` prereq to prod via MCP. All 38 columns/RPCs
  the authenticated pages query are verified present and CI is green, but only a human with
  admin creds can confirm the actual logged-in render. This is the last unverified step.

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

### ☐ 4. Enable leaked-password protection (Supabase dashboard)
Auth → Providers → Password → enable "Leaked password protection" (HaveIBeenPwned).
*Cannot be set via SQL/MCP.* (Advisor: `auth_leaked_password_protection`.)

### ☐ 5. Verify data residency (region)
Confirm the **live Supabase project region is Singapore (ap-southeast-1)** and that backups/replicas
do not leave Singapore. Dashboard → Project Settings → General/Infrastructure.

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
`pg_cron` was enabled and the daily job `pdpa-daily-purge` (18:20) is scheduled and active. Verify:
```sql
SELECT * FROM cron.job WHERE jobname='pdpa-daily-purge';
SELECT purge_expired_personal_data();  -- safe to run manually; returns counts
```
If the project is ever restored/migrated and pg_cron is missing, re-run `011_pdpa_compliance.sql`
or schedule the job manually.

### ☐ 9. Result-slip Storage object cleanup
`erase_student` / `anonymise_student` delete result-slip **rows**, but Storage **objects** under the
`result-slips` bucket are not deleted from SQL. Either delete objects from the app at erasure time,
or run a periodic Storage cleanup of orphaned objects (path convention: `<student_id>/<file>`).

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

### ☐ 13. Decide how to wire Supabase credentials into the build (pre-existing, NOT caused by PR #1)
On a fresh checkout the app **crashes at launch** in `SupabaseManager.init()` because
`SUPABASE_PROJECT_URL` / `SUPABASE_ANON_KEY` never reach the Info dictionary: `iOS/project.yml`
`info.properties` doesn't list them, so XcodeGen generates an `Info.plist` without them, and
`Config.xcconfig`'s values have nowhere to flow. (Confirmed: injecting the keys into the built
`Info.plist` makes the app launch cleanly to the login screen.) Fix options for a human to choose:
add the two keys to `project.yml` `info.properties` as `$(SUPABASE_PROJECT_URL)` /
`$(SUPABASE_ANON_KEY)` **and** correct the `Config.xcconfig` URL escaping (the `//` in
`https://` is otherwise read as an xcconfig comment). Left for you since it touches credential
wiring / security setup. This affects `main` regardless of PR #1.

---

## D. IMPROVEMENTS.md second wave (2026-06-24)

### ◐ 14. Apply migrations 012–014 to the live project — PARTIALLY DONE 2026-06-25
**Done (applied to prod via MCP, 2026-06-25):**
- `012_feature_flags` — full migration: `feature_flags` table + `is_feature_enabled()` + RLS + 3 seeded OFF flags. (Recorded in `schema_migrations`.)
- `014a_get_roster_for_date` — *partial 014*: only the `get_roster_for_date(DATE)` RPC, applied to fix a production login crash (`Could not find the function public.get_roster_for_date(p_date)`). PostgREST schema cache reloaded.

**Still to do (BLOCKED by live-schema drift — needs a dev-branch reconciliation, do NOT apply verbatim to prod):**
The live DB has drifted from the migration sequence — several columns the later
migrations assume are **missing in prod**:
- `classes.recurrence_rule` — absent → **`013_audit_fixes.sql` fails** (its `classes_recurrence_rule_check` CHECK targets this column).
- `attendance_records.late_reason` — absent → the `014` rebuild of `get_session_roster` (adds `avatar_url`, references `late_reason`) fails.
- live `get_session_roster(uuid)` returns 6 cols (no `avatar_url`); `CREATE OR REPLACE` can't change return type (needs `DROP FUNCTION` first).

Remaining un-applied pieces: all of **013** (handle_new_user SEC-05 guard, sync_attendance
`blocked_ended_session` return shape, result_slips subject-CHECK drop, recurrence_rule CHECK)
and the **rest of 014** (student-photos bucket + policies, `students.avatar_url`,
`device_tokens`, `get_session_roster` avatar_url). These back features that are flag-gated
OFF, so prod is functional without them. Recommended: spin up a Supabase **dev branch**,
add the missing columns (`classes.recurrence_rule`, `attendance_records.late_reason`) so the
migrations apply cleanly, verify, then promote. Each migration has a paired `.down.sql`.

### ☐ 15. Decide whether to keep `iOS/TAVAttendance 2.xcodeproj/` (CONTRIB-06)
This untracked directory looks like a Finder duplicate of the real project. Confirm
and delete it (or keep intentionally) before committing — an agent must not delete an
unrecognised file it didn't create.

### ☐ 16. Flip feature flags when each feature is ready
Features ship OFF. Enable per platform-ready feature:
```sql
UPDATE feature_flags SET enabled = true WHERE key = 'parent_portal';      -- PROD-01
UPDATE feature_flags SET enabled = true WHERE key = 'student_photos';     -- PROD-04
UPDATE feature_flags SET enabled = true WHERE key = 'push_notifications'; -- PROD-02
```

### ☐ 17. Provide APNs / FCM credentials for push (PROD-02)
The `notify-parent` edge function is scaffolded but unwired. Supply an APNs key
(iOS) and an FCM server key (Android) as Supabase function secrets, finish the sender
in `supabase/functions/notify-parent/index.ts`, then enable `push_notifications`.

### ☐ 18. Finish the Android port UI follow-ups
All three builds were verified during implementation: iOS (`xcodebuild`, BUILD
SUCCEEDED), web (`npm run build`, OK), Android (`./gradlew compileDebugKotlin`,
BUILD SUCCESSFUL). Still to do: run a full `./gradlew assembleDebug` (exercises R8 +
the new ProGuard keep rules) and complete the Compose UI parity items listed in
`Android/PORTING_NOTES.md` (kiosk UX + parent screen + FCM).

### ☐ 19. Enable the secret-scanning pre-commit hook (DEVOPS-03)
Per clone: `git config core.hooksPath .githooks`.

### ☐ 20. Mirror/verify production Supabase `[auth]` + monitoring (DEVOPS-04/05)
Confirm prod auth settings match `config.toml`, and set up the uptime monitor /
Supabase status subscription described in `CONTRIBUTING.md` §6.

---

## E. Superadmin feature-flags web section (2026-06-25)

A `/feature-flags` admin page now lets the superadmin toggle the `feature_flags`
rows from the web dashboard (an alternative to the SQL in §16). Access is gated
**app-layer only** to one email — the DB RLS write policy stays at `is_admin()`
(intentional; documented in `web/lib/superadmin.ts` and the design spec).

### ☐ 21. (Optional) Set `SUPERADMIN_EMAIL` in Vercel
The gate defaults to `edmund@thegoodcompanysg.dev` if unset, so nothing is required
to keep current behaviour. To change who can access the section, set the
`SUPERADMIN_EMAIL` env var (no `NEXT_PUBLIC_` prefix — it must stay server-side) in
the Vercel project and redeploy.

### ☐ 22. Manual sign-in verification (needs the running app + real accounts)
Cannot be automated (requires Supabase auth + accounts). With the web app running:
- Sign in as `edmund@thegoodcompanysg.dev`: a **"Feature Flags"** link appears in the
  sidebar (and mobile nav); `/feature-flags` lists the seeded flags
  (`parent_portal`, `push_notifications`, `student_photos`); toggling a flag persists
  across a page reload.
- Sign in as a **different admin**: no "Feature Flags" link, and visiting
  `/feature-flags` directly returns a **404**.

### ☐ 23. Review the Chinese (Simplified) UI translations
iOS localization now uses a String Catalog (`iOS/TAVAttendance/Localizable.xcstrings`) with
**English source + best-effort `zh-Hans` translations** for the Privacy Notice screen. The
notice term has been set to **"数据保护声明"** (data protection notice) to match
`docs/pdpa/DATA_PROTECTION_NOTICE.md`. A native speaker should still review overall wording
before shipping. Edit translations in Xcode's String Catalog editor (open `Localizable.xcstrings`).
Strings covered: Loading…, Version %@, Notice Unavailable, Privacy, Done, Privacy Notice, and the
two load-failure messages. Other app screens are not yet localized — adding them is the next step.

---

## F. Dashboard outage hotfix (2026-06-25)

### ☐ 24. Push the dashboard hotfix commit to `origin/main`
Production was down — the dashboard home page 500'd for every logged-in user
(`ERROR 961535271` / PostgREST `PGRST200`) because `getTodaySessions` embedded
`enrollments` directly on a `sessions` query with no FK between them. Fixed in
`web/lib/queries.ts` by routing the embed through `sessions → classes → enrollments`.
**Already deployed to prod** (Vercel CLI, `dpl_sftgTHzdNJbSbVyRTvbWENtDx6Mg`, verified
live) and **committed locally** as `68fabc4`, but **not pushed**. Push it so
`origin/main` matches prod and a future git-triggered deploy doesn't revert the fix:
```bash
git push origin main
```

---

## G. tava.sg alignment + Study Space tracking (2026-06-26)

### ☐ 25. Apply migration `015_study_space_and_notice.sql` to the live project
Adds `classes.is_study_space` + the singleton Study Space class, seeds the
`study_space_tracking` flag (OFF), adds `get_study_space_roster`, excludes study space from
`attendance_summary` + `get_roster_for_date`, and publishes Data Protection Notice **v1.1**.
The notice (§B-style) and flag parts are independent of the §14 schema drift, but verify the
column/function changes apply cleanly against the live schema first (use a dev branch if unsure).
Paired down migration: `015_study_space_and_notice.down.sql`.

### ☐ 26. Finish DPO contact on the v1.1 notice — *ties into §1/§2*
The v1.1 notice now names **Talent Beacon** as the controller and `admin@talentbeacon.org` /
209 Bukit Batok Street 21, #01-182 as the contact, but the **DPO name/role** is still a
placeholder in `docs/pdpa/DATA_PROTECTION_NOTICE.md` and the seeded `policy_documents` v1.1 body.
Fill it in and get legal/DPO sign-off (removes "DRAFT v1.1").

### ☐ 27. Flip `study_space_tracking` when the Study Space feature is ready
Ships OFF. Enable per §16 (or via the superadmin `/feature-flags` page) **only after** the
Android + web ports land, so study-space sessions never exist before every reporting surface
excludes them:
```sql
UPDATE feature_flags SET enabled = true WHERE key = 'study_space_tracking';
```

### ☐ 28. Fix tava.sg's own copy inconsistency (website, not the app)
The site states opening hours as both **"12–6pm"** (header) and **"1–6pm"** (registration prose),
and lists tuition at **7:30pm** though the drop-in space closes at 6pm. Confirm the canonical
figures and correct them on tava.sg. (No app change — the app does not hardcode these.)

### ☐ 29. Unblock Android build/test verification (environment)
`compileDebugKotlin` passes for the Study Space changes, but a full `./gradlew test` /
`assembleDebug` can't complete in this environment for two pre-existing reasons:
- **macOS Finder duplicates** — ~48 `… 2.kt` / `… 2.xml` / `… 2.png` files under `Android/app/src`
  (and the `iOS/TAVAttendance 2.xcodeproj` per §15) break resource merge + cause redeclarations.
  Delete them (they are untracked Finder copies) before building.
- **JDK 26** is the only installed JDK; the Android Gradle Plugin's `jlink` JDK-image transform
  fails on it. Install a **JDK 17 or 21** and point `JAVA_HOME`/Gradle toolchain at it, then run
  `./gradlew testDebugUnitTest` (includes the new `DayAwareKioskTest`).

---

## Notes
- Accepted/intentional advisor warnings: the `is_admin()/is_parent()/...` and the new
  `anonymise_student/erase_student/export_student_personal_data` SECURITY DEFINER functions are
  callable by `authenticated` **by design** — each guards with `is_admin()` (or is required by RLS).
  `rate_limit_events` has RLS on with no policy **by design** (service-role only).
- Anon key remains in old git history (`build.gradle.kts`, old `SupabaseConfig.kt`); the anon key is
  public-by-design, but rotate it via the dashboard if this repo ever goes public.
