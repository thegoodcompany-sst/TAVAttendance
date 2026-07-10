# TAVA Attendance — Demo Run-of-Show

Demo: **Saturday 2026-07-11**. Skim this on your phone mid-presentation.
Web dashboard: https://dash.thegoodcompanysg.dev

---

## 1. Night-before checklist (do tonight)

- [ ] **`test_mode` flag is ON in prod** (seeded by migration 020). This makes the kiosk show *all* active classes regardless of weekday, and analytics show all days — so the Saturday demo isn't empty. Confirm it's on.
- [ ] **Flip `parent_portal` and `student_photos` ON** at `/feature-flags`. Only the superadmin account **edmund@thegoodcompanysg.dev** can see that page. **Flip both back OFF after the demo.**
- [ ] **Relaunch the kiosk app after any flag flip** — iOS reads feature flags once, at sign-in. A flag flipped while the app is open won't take effect until relaunch.
- [ ] **Kiosk iPad signed in as an ADMIN account.** A tutor login only sees its own assigned classes (RLS), which makes the global kiosk useless.
- [ ] **Leave the kiosk PIN unset** → kiosk stays in admin mode (the intended demo posture; overrides available by tap/long-press).
- [ ] **Open the kiosk once tonight as a rehearsal.** The first open with `test_mode` on creates today's (Saturday) session rows for every active class — expected, but don't let the *live* demo be the first run.
- [ ] Run the condensed smoke checklist + the 4 DB verification queries below.

### Condensed smoke checklist

**Web:** login → dashboard renders (today's sessions + daily attendance) → open a student detail → CSV export works. As superadmin: `/feature-flags` lists the flags and a toggle persists across reload.

**Kiosk:** admin login → Sign In tab shows classes → tap a student (green on-time / orange late) → long-press a card offers Mark as Late / Not Here / Absent.

### DB verification queries (paste into Supabase SQL editor)

```sql
-- security posture of the money view
SELECT reloptions FROM pg_class WHERE relname='attendance_summary';  -- {security_invoker=on}
-- flags as expected
SELECT key, enabled FROM feature_flags ORDER BY key;
-- study-space exclusion holds (0 rows expected)
SELECT COUNT(*) FROM attendance_summary a
JOIN classes c ON c.id = a.class_id WHERE c.is_study_space;
-- purge job alive
SELECT jobname, active FROM cron.job WHERE jobname='pdpa-daily-purge';
```

---

## 2. Run-of-show (~10–15 min)

Each beat: **SAY** the framing, **TAP** the action.

**1. Kiosk sign-in (the core loop)**
- SAY: "Students walk in and tap their own name. No teacher taking a paper register."
- TAP: a student card → goes **green** (On Time) or **orange** (Late) depending on class start time.
- SAY: "Late is automatic — it compares the tap time against the class schedule."

**2. Admin overrides**
- SAY: "Staff can correct anything on the spot."
- TAP: long-press a green card → context menu → **Mark as Late** (turns orange) / **Mark as Not Here** (back to grey, student can re-tap) / **Mark as Absent** (red).
- SAY: "And when a parent picks a child up early —" TAP: dismiss a signed-in student → card goes **purple** (Dismissed; still counts as present, just signed out early).

**3. Offline mode (the reliability story)**
- SAY: "Tuition centres have patchy Wi-Fi. The kiosk never blocks a sign-in."
- TAP: turn the iPad Wi-Fi **off** → sign a student in → an **orange pending dot** appears.
- TAP: turn Wi-Fi back **on** → dot clears automatically (synced). "No data lost, no duplicates."

**4. Web dashboard — live view**
- SAY: "Back office sees it live." Open the dashboard.
- SAY: "This auto-refreshes every 30 seconds — the sign-in you just did on the iPad shows up here."

**5. Analytics**
- TAP: the **Analytics** page → attendance % / punctuality per student per class.
- SAY: "This is what a parent-teacher meeting used to take an hour of paper to produce."

**6. Student profile + history**
- TAP: a student → profile sheet with their recent attendance history (dates, class, status).

**7. Parent portal view**
- SAY: "Parents get a read-only view of their own child only." Show the parent portal (flag on).

**8. Feature-flag toggle — the ops "wow"**
- SAY: "Everything unfinished ships dark behind a flag. Watch." At `/feature-flags`, toggle a flag and show it persist.
- SAY: "That's how we ship safely — features go live the moment they're ready, no redeploy."

---

## 3. Do NOT demo

- **Android app** — behind iOS; UI follow-ups pending. Would invite unfavourable comparison.
- **PDPA privacy panel** — not wired into the web student page yet (open decision). Half-finished.
- **Siri / Shortcuts intents** — end-to-end voice flow untested. Fragile live.

---

## 4. If things go wrong

- **Blank student-history sheet, no error** → swallowed PostgREST 400. Check Supabase logs; suspect the FK join string in `fetchStudentAttendanceHistory`.
- **Kiosk empty / "No Classes Today"** → confirm `test_mode` is ON, the iPad is on an **admin** login, and you **relaunched** the app after the last flag flip.
- **Dashboard looks stale** → wait for the 30s auto-refresh, or hard-reload the page.

---

## 5. Post-demo teardown

- Flip **`test_mode` OFF**.
- Flip **`parent_portal`** and **`student_photos`** back **OFF** at `/feature-flags`.
- Delete the Saturday demo session/attendance rows.

Full teardown SQL lives in **HUMANS.md §37**.
