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
| **Absent informed / not informed** | **Shipped** (migration 056 + iOS UI, 2026-08-07). Android/web UI still pending (handoff blocks). |
| **Students → year attendance** | **Shipped on iOS** (Students tab → year-detail sheet). Android/web parity still pending (handoff blocks). |
| **Retrospective** | **Shipped + flag ON in prod** (verified `enabled = true`). Remaining risk is physical-device QA / staff familiarity, not “is it in the build?” |

---

## Still queued for next build

_(empty — both 2026-08-06 queue items shipped in this change set.)_

### Closed — do not re-queue

- ~~Absent: informed vs did not inform~~ — companion boolean `absence_informed` (056); iOS kiosk/roster; not a new status.
- ~~Students tab → attendance detail (copy web)~~ — iOS year-detail sheet over rolling 12 months; tutor-scope caption.
- ~~Retire PALE “E” / excused~~ — merged into Not Here Yet (055 + clients); prod clean.
- ~~New Pending status / extend marking window as a separate feature~~ — pending = Not Here Yet; late catch-up = retrospective marking (flag already ON).
- ~~Build retrospective session editing from scratch~~ — already in clients; prod flag enabled.

---

## Pilot framing (not a build feature)

- Near-term goal remains pilot readiness: familiarisation and UX polish.
- On-site support on first usage day is welcome if staff can spare people.
- Invite concrete feedback when something feels unintuitive.
