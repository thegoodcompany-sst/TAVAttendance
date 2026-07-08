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
`pg_cron` is enabled and the daily job `pdpa-daily-purge` (18:20) is scheduled and active. Verify:
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
A draft implementation exists on the unmerged local branch `worktree-agent-a0964c91cbe6e7bb4`
(commit `cc63405`, 2026-06); its migration is numbered `013` which now clashes with main — renumber
before merging, or treat it as reference only.

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

### ◐ 14. Finish applying migrations 012–015 to the live project — IN PROGRESS
**Applied to prod (via MCP):** `012_feature_flags`, `014a_get_roster_for_date`, and `015` plus its
`students.avatar_url` prereq.

**Still to do:** the remaining pieces of **013** and **014** (handle_new_user SEC-05 guard,
`sync_attendance` `blocked_ended_session` return shape, result_slips subject-CHECK drop,
`recurrence_rule` CHECK, student-photos bucket + policies, `device_tokens`, `get_session_roster`
`avatar_url`). These need a few columns added first (`classes.recurrence_rule`,
`attendance_records.late_reason`) so the migrations apply cleanly. They back features that are
flag-gated OFF, so prod is functional without them. Recommended: apply on a Supabase **dev branch**,
verify, then promote. Each migration has a paired `.down.sql`.

### ☑ 15. `iOS/TAVAttendance 2.xcodeproj/` Finder duplicate — GONE (CONTRIB-06)
Verified 2026-07-02: the directory no longer exists in the working tree. Nothing to do.

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
iOS localization uses a String Catalog (`iOS/TAVAttendance/Localizable.xcstrings`) with
**English source + best-effort `zh-Hans` translations** for the Privacy Notice screen. The
notice term is set to **"数据保护声明"** (data protection notice) to match
`docs/pdpa/DATA_PROTECTION_NOTICE.md`. A native speaker should review overall wording
before shipping. Edit translations in Xcode's String Catalog editor (open `Localizable.xcstrings`).
Strings covered: Loading…, Version %@, Notice Unavailable, Privacy, Done, Privacy Notice, and the
two load-failure messages. Other app screens are not yet localized — adding them is the next step.

---

## F. Study Space tracking (2026-06-26)

### ☐ 24. Apply migration `015_study_space_and_notice.sql` to the live project
Adds `classes.is_study_space` + the singleton Study Space class, seeds the
`study_space_tracking` flag (OFF), adds `get_study_space_roster`, excludes study space from
`attendance_summary` + `get_roster_for_date`, and publishes Data Protection Notice **v1.1**.
The notice and flag parts are independent of the §14 work, but verify the column/function
changes apply cleanly against the live schema first (use a dev branch if unsure).
Paired down migration: `015_study_space_and_notice.down.sql`.

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

### ☐ 27. Fix tava.sg's own copy inconsistency (website, not the app)
The site states opening hours as both **"12–6pm"** (header) and **"1–6pm"** (registration prose),
and lists tuition at **7:30pm** though the drop-in space closes at 6pm. Confirm the canonical
figures and correct them on tava.sg. (No app change — the app does not hardcode these.)

### ☐ 28. Unblock the full Android build/test on this machine (environment)
`compileDebugKotlin` passes, but a full `./gradlew test` / `assembleDebug` needs one local fix:
- **JDK version** — the Android Gradle Plugin's `jlink` transform needs **JDK 17 or 21**; point
  `JAVA_HOME`/the Gradle toolchain at one, then run `./gradlew testDebugUnitTest` (includes
  `DayAwareKioskTest`).

---

## G. Refactor follow-up (2026-07-03)

### ☐ 29. Decide whether to wire `PdpaPanel` into the web student detail page
`web/app/(admin)/students/[id]/pdpa-panel.tsx` (plus `getStudentConsent` and the
withdraw/anonymise/erase/export actions behind it) has never been imported by
`students/[id]/page.tsx` — it looks like the panel was built and never wired in.
It is the s16/s21/s25 PDPA machinery, so it was deliberately NOT deleted in the
2026-07 refactor. Decide: wire it into the student page (one import + render), or
schedule it with the PDPA app-UI work.

---

## H. Security audit follow-up (2026-07-06)

Code/migration fixes from the 2026-07-06 audit are committed (migration `016_security_fixes.sql`,
iOS/Android/web patches). These remaining items need a human with dashboard/prod access.

### ☐ 30. Apply migration `016_security_fixes.sql` to the live project — *high priority*
016 closes two criticals: (a) `attendance_summary` lost `security_invoker` in 015, so on any
environment where 015 has been applied the view runs as owner and leaks every student's attendance
to any authenticated/anon reader; (b) `handle_new_user` let public self-signup mint an **admin**.
016 depends on 013–015 being applied first (see §D.14). Apply 013→014→015→016 in order, then
verify: `SELECT relname, reloptions FROM pg_class WHERE relname='attendance_summary';` must show
`security_invoker=on`.

### ☐ 31. Disable public sign-ups in the prod Supabase dashboard — *high priority*
Auth → Providers → Email → turn **OFF** "Allow new users to sign up". Every account is created by
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

### ☐ 34. Install JDK 17 or 21 to unblock Android unit tests
`./gradlew test` fails on this machine (jlink error under JDK 26; `/usr/libexec/java_home -v 17`
and `-v 21` both fall back to temurin-26). `brew install --cask temurin@21` (or 17) fixes it.
Until then agents verify Android with `./gradlew clean compileDebugKotlin` only — no unit tests run.

---

## Notes
- Accepted/intentional advisor warnings: the `is_admin()/is_parent()/...` and the
  `anonymise_student/erase_student/export_student_personal_data` SECURITY DEFINER functions are
  callable by `authenticated` **by design** — each guards with `is_admin()` (or is required by RLS).
  `rate_limit_events` has RLS on with no policy **by design** (service-role only).
- The Supabase anon key is public-by-design; rotate it via the dashboard if this repo ever goes public.
