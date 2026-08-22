# TAVA Attendance roadmap

Future work for **every child accounted for**. This file is not a changelog and
not an inventory of what already exists.

| File | Role |
|---|---|
| This file | What we will build next, in what order, and what we will not |
| [`NEXT_BUILD_CHANGES.md`](NEXT_BUILD_CHANGES.md) | The next approved implementation queue |
| [`RELEASE_NOTES.md`](RELEASE_NOTES.md) | What changed between builds |
| [`README.md`](README.md) | What the product does today |
| [`docs/superpowers/specs/2026-08-17-student-assurance-os-design.md`](docs/superpowers/specs/2026-08-17-student-assurance-os-design.md) | Approved Student Assurance design |

When a roadmap item is approved for a build, copy a short executable entry into
`NEXT_BUILD_CHANGES.md`. When it ships, record it in `RELEASE_NOTES.md` →
`Unreleased` and remove it from this file.

No roadmap expansion enters the September 2026 real-child pilot.

## Non-goals

Out of scope unless a later, explicit decision reverses this:

- payments, invoicing, fees, payroll, accounting;
- generic CRM, marketing, enrolment funnels, or engagement feeds;
- behavioural profiling, child/family risk scores, or AI-generated labels;
- a model in the accountability loop (guessing arrival, “probably home”, or
  auto-messaging parents about a missing child);
- features that do not change a safe session-day action or staff confidence.

Software assists staff. It does not replace judgement.

## 2026 — prove the existing loop

One centre, fewer than 50 children, two months. Centre lead owns go/no-go.
Edmund observes. Each session has a named desk lead.

The test is the kiosk, tutor roster, offline recovery, paper fallback, and web
reconciliation — tap-name sign-in, not QR or NFC.

Before real children: an older unprocessed offline mutation must not overwrite a
newer authorised correction. Readiness gates live in `HUMANS.md` and
`docs/test-kit/PRE_PILOT_CHECKLIST.md`. The executable pre-pilot work is in
[`NEXT_BUILD_CHANGES.md`](NEXT_BUILD_CHANGES.md).

## After the pilot — evidence-gated, in this order

Synthesize observed routines and failures before approving expansion. Then:

1. **Authoritative session calendar and expected-today roster** — holidays,
   cancellations, ad hoc sessions, corrections; one server projection every
   client shares. No Live Accountability Board before this.
2. **Admin-only Web Board and Exception Inbox** — one security-invoker RPC,
   server-known facts only, bounded polling, hard failure instead of a stale
   all-clear. Flag-gated, ships OFF.
3. **Handoff evidence** — only after the pilot shows real departure routines and
   TAVA's responsibility boundary. Current dismissal history is not that.
4. **One Parent Assurance channel and one high-value trigger** — sending is not
   receipt; delivery failure feeds the Inbox. Privacy notice/consent gates first.
5. **Longitudinal child context** — only a fact the pilot showed changes a safe
   action. Source, purpose, access, correction, retention, audit.

Detail and SLC gates: the Student Assurance spec linked above.

## 2027 — dedicated arrival station (NFC)

A device that lives at the centre, so staff do not have to remember an iPad.
NFC is the student-facing input. Do not invest further in camera QR; that path
is not the 2027 target.

Assumptions: tags are not a high-clone threat at this centre; staff still
override on a named grid.

- **Arrival station** — always-on reader plus a small success/failure cue
  (on time, late, already signed in, not on today's roster). Tutor phones keep
  class rosters; web keeps Board, inbox, and admin.
- **NFC, chip UID → student** — do not write the student UUID into the tag.
  Admin pairs and reissues cards. Same mark path as tapping a kiosk card.
- **Kiosk-scoped device identity** — the box must not hold a full admin session
  in a cupboard. Prefer RPCs limited to today's expected roster. No service-role
  key on the device. Offline queue stays actor-bound.
- **Client choice** — prefer reusing the Android kiosk on a cheap NFC phone if
  that is enough; a Raspberry Pi + reader is fine if we will own the Linux
  appliance. Do not build both.
- **Fail closed** — unexpected taps wait for the expected-today roster. Paper
  fallback remains.

Do not start this until the 2026 loop is evidenced and the calendar/roster
authority exists. When it is time to build, add a flagged, sequenced entry to
`NEXT_BUILD_CHANGES.md`.

Not in this station: an unsupervised door reader, student/parent phone as the
check-in actor, replacing tutor roster / PIN overrides / paper, or AI at the tap.

## Later, only if the Inbox proves the pain

Staff-side **draft and classify** (suggested next action, draft parent reply)
may follow the Board. Not a product chatbot, not auto-send, not child PII to a
trainer by default. Revisit only with a named workflow and PDPA purpose.
