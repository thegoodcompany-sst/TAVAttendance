# Next build changes

The executable queue for the next approved work. Longer-horizon direction lives
in [`ROADMAP.md`](ROADMAP.md). Full Student Assurance decisions:
[`docs/superpowers/specs/2026-08-17-student-assurance-os-design.md`](docs/superpowers/specs/2026-08-17-student-assurance-os-design.md).

## P1 — before the September 2026 real-child pilot

- Update and run the pre-pilot evidence kit for one centre, fewer than 50
  children, over two months. The existing kiosk, tutor roster, offline recovery,
  paper fallback, and web reconciliation loop are the test scope.

## Post-pilot — specification and architecture gates first

- Synthesize observed routines and failures before approving expansion work.
- Add an authoritative session calendar and expected-today roster before any
  Live Accountability Board. It must represent holidays, cancellations, ad hoc
  sessions, and corrections without relying on client-created sessions.
- Specify and then build one flag-gated, admin-only Web workspace containing the
  Live Accountability Board and Exception Inbox. It uses one security-invoker
  Supabase RPC, server-known facts only, bounded polling, and a hard failure state
  instead of a stale all-clear.
- Keep handoff evidence provisional until the pilot establishes real departure
  routines and TAVA's responsibility boundary. Parent assurance follows the
  approved handoff model; child context follows only when evidence shows a fact
  changes a safe action.

Add agreed, unimplemented work here. When it ships, move it to
`RELEASE_NOTES.md` → `Unreleased` in the same change set.
