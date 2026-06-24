# Phase 2/3 RLS plan (DOC-01)

The Phase 2/3 tables are created with RLS enabled and **admin-only** policies
(`002_rls.sql`). Some already have scoped parent-read policies added defensively in
`011_pdpa_compliance.sql`. This document records the intended policies for each table
when its feature is implemented, so the admin-only lock can be relaxed deliberately.

Helper predicates available (from `002_rls.sql`): `is_admin()`, `is_tutor()`,
`is_parent()`, `parent_owns_student(student_id)`, `tutor_owns_class(class_id)`,
`is_feature_enabled(key)` (from `012`).

| Table | Current | Intended policies when implemented |
|---|---|---|
| `result_slips` | admin ALL; parent SELECT own child (011) | parent INSERT own child's slip; admin/tutor SELECT for their classes; gate writes behind a flag. |
| `messages` | admin only | both participants (sender, recipient) SELECT; sender INSERT; no UPDATE/DELETE except admin. Thread-scoped. |
| `awards` | admin only | admin/tutor write; student's parent SELECT own child (`parent_owns_student`). |
| `dismissals` | admin ALL; parent SELECT own child (011) | admin/tutor INSERT for their class sessions; parent SELECT own child only. |
| `food_polls` | admin only | admin write; any authenticated SELECT active polls. |
| `food_poll_responses` | admin only | responder INSERT/UPDATE own row; admin SELECT all; parent SELECT own child's. |

## Principles

- Default deny: keep admin-only until a feature's policies are written and reviewed.
- Parents are always scoped through `parent_owns_student()` — never a blanket
  `is_parent()` read.
- Tutors are scoped through `tutor_owns_class()` for class-linked data.
- Where a feature is gated by a `feature_flags` row, prefer gating in the **app/UI**;
  add `is_feature_enabled()` to a policy only when the data itself must stay sealed
  server-side until launch.
