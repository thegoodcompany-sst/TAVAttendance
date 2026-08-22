# Kiosk and attendance domain reference

This document owns the detailed behavior of kiosk attendance. Keep the
load-bearing summary in `AGENTS.md`; update this reference when the product
semantics or manual flow changes.

## Session selection

The centre-wide kiosk must be signed in as an administrator. Tutor accounts are
scoped to currently owned or covered classes and cannot supply the full kiosk.

Loading the kiosk calls the day-aware session RPC for every class the current
actor may operate today. A class matches when its recurrence `BYDAY` contains
today's two-letter code, its `schedule_day` matches today's English weekday, or
neither field is set (ad hoc). When `test_mode` is enabled, all active tuition
classes are eligible. Creating attendance-less sessions during kiosk load is
intentional.

Study Space uses its own flagged class and roster. It accepts Present or Not Here
Yet only and must never appear in reports, exports, awards, analytics, report
cards, or parent views.

## Status model

| UI state | Stored data | Meaning |
|---|---|---|
| Not Here Yet | No `attendance_records` row | Unmarked and tappable for sign-in |
| On Time | `status = 'present'` | Present before the late threshold |
| Late | `status = 'late'` | Present after the threshold; may include `late_reason` |
| Absent — informed | `status = 'absent'`, `absence_informed = TRUE` | Family gave notice |
| Absent — no notice | `status = 'absent'`, `absence_informed = FALSE` | Family did not give notice |
| Absent — unspecified | `status = 'absent'`, `absence_informed = NULL` | Legacy or unspecified source |
| Dismissed | Present/late attendance row plus a `dismissals` row | Student attended and was signed out |

Do not add a fourth attendance status for informed absence. Parents never see
`absence_informed`; it does not alter attendance percentage. Offline sync and
retrospective writes must preserve it.

Clearing attendance uses `clear_attendance` with a fresh mutation ID and removes
the row. Dismissal is not clearing or absence: the original present/late row
continues to count toward attendance.

## Kiosk interaction

| State | Appearance | Student-facing action | Admin action |
|---|---|---|---|
| Not Here Yet | Grey | Tap to sign in | Tap to sign in; long-press for overrides where offered |
| On Time | Green | None | Tap/long-press according to current override controls |
| Late | Orange | None | May change to On Time or inspect the late reason |
| Absent | Red | None | Context-menu override only |
| Dismissed | Purple, original attendance beneath | None | Undo dismissal by long-press |

Auto-late parsing accepts PostgreSQL `TIME` values returned as `HH:mm:ss` as
well as form input such as `HH:mm`; parsers use the hour and minute components.

When a student belongs to more than one eligible session, the kiosk presents
one card with the worst stored status: `late > present > absent`. It is unmarked
only when every session has no attendance row. A current dismissal takes visual
precedence while retaining the underlying attendance state.

## Admin mode

| Configuration | Behavior |
|---|---|
| No PIN | Always in admin mode; suitable only for controlled demos/testing |
| PIN set, locked | Student-facing grid; administrative navigation hidden |
| PIN set, unlocked | ADMIN badge and override controls visible |

The unlock state is not persisted across app restarts. The PIN protects the UI,
not the underlying administrator Supabase session; treat the device as
privileged and physically supervise it.

## Verification

Database-level invariants live in `supabase/tests/`, including Study Space
exclusion, retrospective attendance, offline idempotency, and informed-absence
coverage. Run the manual scripts below for whichever flows a change touches;
this document is their canonical copy.

**Kiosk sign-in** (admin login → Sign In tab; needs a class with
`schedule_time` in the past to exercise Late): tap student → green (on time) /
orange (late) → long-press green offers "Mark as Late"/"Mark as Not Here Yet" →
mark late: turns orange → clear to Not Here Yet: attendance row removed, card
grey and tappable again → tap again: re-signs-in.

**Admin mode**: set PIN → lock → unlock with PIN shows ADMIN badge → tap orange
card flips to green → long-press offers "Mark as Absent" (red) → re-lock hides
overrides.

**Teacher roster** (tutor login): Start Today's Class → mark present → "Marked
HH:MM" shows → tap row: Student Profile sheet with history → Wi-Fi off, mark:
orange pending dot → Wi-Fi on: dot clears → verify the server row. Test
sign-out/account transitions with pending data; foreign/mixed queues must fail
closed, not cross-sync.

**Profile history**: a blank list with no error means a swallowed PostgREST
400 — check Supabase logs and suspect the FK join string.

**Study space** (flag on, iPad): header button → `StudySpaceView` → roster is
all active students → Present/Not Here Yet only → verify nothing appears in any
report or parent view.

**Web smoke**: login → dashboard/mobile staff surfaces → student detail → safe
export. Superadmin: `/feature-flags` lists live rows and toggles persist;
ordinary admin gets 404.

```sql
-- security posture of the money view: {security_invoker=on}
SELECT reloptions FROM pg_class WHERE relname='attendance_summary';
-- study-space exclusion holds (0 rows expected)
SELECT COUNT(*) FROM attendance_summary a
JOIN classes c ON c.id = a.class_id WHERE c.is_study_space;
```
