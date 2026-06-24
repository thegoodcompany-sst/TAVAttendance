# HUMANS.md — actions only a human can complete

Some PDPA (and related) compliance steps cannot be done in code or by an agent. They need a
person with organisational authority, legal judgement, or access to dashboards/contracts.
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

### ☐ 14. Apply migrations 012–014 to the live project
`012_feature_flags.sql`, `013_audit_fixes.sql`, `014_feature_tables.sql` add the
`feature_flags` table, fix the `handle_new_user` admin guard (SEC-05), change the
`sync_attendance` return shape (`blocked_ended_session`), drop the `result_slips`
subject CHECK, add the `student-photos` bucket + `avatar_url` + `device_tokens`, and
the `get_roster_for_date` RPC. Apply to a **dev branch first**, verify, then prod.
Each has a paired `.down.sql`.

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

## Notes
- Accepted/intentional advisor warnings: the `is_admin()/is_parent()/...` and the new
  `anonymise_student/erase_student/export_student_personal_data` SECURITY DEFINER functions are
  callable by `authenticated` **by design** — each guards with `is_admin()` (or is required by RLS).
  `rate_limit_events` has RLS on with no policy **by design** (service-role only).
- Anon key remains in old git history (`build.gradle.kts`, old `SupabaseConfig.kt`); the anon key is
  public-by-design, but rotate it via the dashboard if this repo ever goes public.
