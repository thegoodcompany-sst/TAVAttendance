# Next build changes

Planned work for the **next app build**. Plan queue only — not a release ledger.

When an item ships, add it under `RELEASE_NOTES.md` → `Unreleased` and clear or
mark it here in the same change set. Agents: see `AGENTS.md` §Next-build plans.

Source: staff chat 2026-08-06 (Lycia ↔ Edmund), clarified 2026-08-06 after
code/prod verification.

---

## Verification snapshot (2026-08-06)

Checked against repo clients + live prod `zgikcbsxzjgbigywxbbj`:

| Topic | Result |
|---|---|
| **E / excused** | **Done.** Migration `055_merge_not_here_yet` applied to prod (HUMANS §71, 2026-08-03). Prod has **0** `excused` rows; statuses are present 31 / late 23 / absent 7; check constraint is `present\|absent\|late` only; `attendance_summary` has no `excused_count`. iOS/Android enums and web `AttendanceStatus` are present/late/absent (+ null = Not Here Yet). Notify-parent test still asserts `excused` is **rejected** (good). README had a stale “P/A/L/E” line — fixed in the same docs pass. |
| **Pending** | **Not a new status.** Staff “pending” = unmarked / session not marked yet = existing **Not Here Yet** (no row). Catch-up after class is covered by **retrospective session editing** (built; prod flag `retrospective_sessions` is **enabled**). Do not add a separate Pending status. |
| **Absent informed / not informed** | **Still to build** for next build (confirmed product yes). No `informed` / absence-reason split exists yet (only `late_reason` for late). |
| **Students → year attendance** | **Still to build on iOS** (and tighten native parity). Web already has the reference UX. |
| **Retrospective** | **Shipped + flag ON in prod** (verified `enabled = true`). Remaining risk is physical-device QA / staff familiarity, not “is it in the build?” |

---

## Still queued for next build

### 1. Absent: informed vs did not inform
- [ ] Split absent into **Absent (informed)** and **Absent (did not inform)**.
- [ ] Decide storage (new status values vs `absent` + reason/flag column), kiosk/roster/web labels, reports/`attendance_summary` impact, and whether parents may see the distinction (PDPA).
- [ ] Ship behind a flag if the schema change is risky mid-pilot; otherwise document the migration-before-deploy order in the usual way.

### 2. Students tab → attendance detail (copy web)
Reference implementation (do not invent a parallel design):

- Web list: `web/app/(admin)/students/page.tsx` → link to `/students/[id]`
- Web detail: `web/app/(admin)/students/[id]/page.tsx`
  - **Attendance by class** via `getStudentClassSummary` → `attendance_summary` (lifetime per class, study-space excluded)
  - **Recent records** via `getStudentRecentRecords` (last 50, study-space excluded)
- Mobile web twin: `web/app/mobile/students/[id]/page.tsx`

Native gaps vs that reference:

- [ ] **iOS** `StudentManagementView`: row is **not tappable** today (swipe = edit/remove, context = privacy). Add navigation/sheet that mirrors the web detail (class summary + recent register). Existing `StudentProfileView` is a **last-30-days** history sheet from roster/parent flows — not the same as web’s `attendance_summary` by class.
- [ ] **Android** `StudentManagementScreen` already opens `StudentProfileSheet` on tap, but that sheet is also **last-30-days** history, not web’s by-class summary. Align content with the web student detail.
- [ ] Product wording: Lycia said “attendance for the year”; web today is **all recorded sessions in `attendance_summary`**, not a calendar/academic-year filter. Match web unless we explicitly add a year filter later.
- [ ] Keep study-space exclusion on every new query/surface.

### Closed — do not re-queue

- ~~Retire PALE “E” / excused~~ — merged into Not Here Yet (055 + clients); prod clean.
- ~~New Pending status / extend marking window as a separate feature~~ — pending = Not Here Yet; late catch-up = retrospective marking (flag already ON).
- ~~Build retrospective session editing from scratch~~ — already in clients; prod flag enabled.

---

## Pilot framing (not a build feature)

- Near-term goal remains pilot readiness: familiarisation and UX polish.
- On-site support on first usage day is welcome if staff can spare people.
- Invite concrete feedback when something feels unintuitive.
