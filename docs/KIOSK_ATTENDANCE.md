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

The canonical manual regression scripts live in
`.claude/skills/tava-validation-and-qa/SKILL.md`. Database-level invariants live
in `supabase/tests/`, including Study Space exclusion, retrospective attendance,
offline idempotency, and informed-absence coverage.
