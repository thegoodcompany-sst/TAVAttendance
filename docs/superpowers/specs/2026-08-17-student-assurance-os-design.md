# TAVA Student Assurance OS Design

**Date:** 2026-08-17

**Status:** Approved product direction; implementation remains gated

**Pilot:** September 2026 start, one centre, fewer than 50 children, two months

## Product promise

**Every child accounted for.**

TAVA owns the operational loop from expected arrival to the
centre-approved responsibility endpoint. Home acknowledgement belongs only
when an approved travel mode and policy make it part of TAVA's duty.

The defensible asset is not a dashboard. It is the compounding reliability of
TAVA's real routines: authoritative expectations, safe attendance recovery,
owned exceptions, staff habits, parent trust, and carefully governed context.

The product follows SLC:

- **Simple:** one daily question—are all expected children accounted for?
- **Lovable:** staff can act calmly without reconciling several screens, chats,
  or memories.
- **Complete:** every state inside the approved responsibility boundary has a
  clear path, including failure and recovery.

## Product boundary

TAVA is a student-operations system. It is not a business ERP.

In scope only when required to close the assurance loop:

- expected-today scheduling and roster authority;
- arrival, attendance, absence context, and safe offline reconciliation;
- unresolved-condition ownership and closure;
- evidence-based departure and parent assurance, after policy approval; and
- minimal consented context proven to change a safe action.

Explicitly out of scope:

- payments, invoicing, fee collection, payroll, or accounting;
- generic CRM, marketing, enrolment funnels, or engagement feeds;
- behavioural profiling, child/family risk scores, or AI-generated labels; and
- features that do not change a safe session-day action or confidence.

## September evidence gate

The first priority is the existing attendance core, not a new Board or parent
workflow. The test covers:

- centre-wide kiosk sign-in and PIN-unlocked corrections;
- tutor class start, roster marking, and student history;
- offline marking, reconnect, account transition, and Web reconciliation;
- paper fallback and controlled reconciliation; and
- observation of actual arrival, absence, departure, and workaround routines.

### Ownership

| Role | Responsibility |
|---|---|
| Edmund | Product readiness, observation, private notes, evidence synthesis, and fix list; does not coach routine flows |
| Centre lead | Operational go/no-go before and during the pilot |
| Named desk lead | Runs the kiosk/PIN flow and owns immediate fallback or safety stop |
| Tutors | Run assigned rosters and report discrepancies |

A flow that succeeds only with builder coaching is a usability failure. Edmund
may intervene for safety, privacy, or data-integrity risk.

### Pre-pilot blockers

1. An old, previously unprocessed offline mutation must not overwrite a newer
   authorised correction merely because it reaches the server later. The server
   must enforce precedence without trusting client wall-clock time.
2. `docs/test-kit/PRE_PILOT_CHECKLIST.md` must pass on the real devices and
   accounts.
3. The privileged-account, kiosk-session, and physical-device gates in
   `HUMANS.md` §62–§64 must have an approved disposition.
4. The centre lead signs off the authoritative roster against the approved
   paper source before each pilot session.

### Evidence capture

Use a private structured exception register. Each entry records:

- stable entry ID;
- date/time and affected session or child;
- event type and what staff expected;
- named owner and next action;
- escalation or fallback used;
- outcome and closure time; and
- whether the app, process, or training needs a fix.

Before the first session, record the planned session count, expected-child
count, devices, roles, and observation owner. After two months, expansion
decisions must cite observed events, not hypothetical scale.

## Post-pilot sequence

```text
pilot evidence
    -> authoritative session calendar / expected roster
    -> arrival-accountability state specification
    -> Web Live Accountability Board + Exception Inbox
    -> observed and approved handoff evidence
    -> one Parent Assurance channel and trigger
    -> only child context proven to change a safe action
```

Each phase is SLC for its approved boundary before the next begins.

## Authoritative expected roster

The current client-created session pattern is not sufficient for a safety
surface. Before the Board, the server must represent:

- approved scheduled sessions;
- holidays and cancellations;
- ad hoc sessions;
- roster and schedule corrections with actor/time evidence; and
- one expected-today projection shared by every client.

An unexpected child cannot receive an unrostered attendance mark. An admin
first fixes and verifies the authoritative roster.

## Phase 1 Board and Inbox

Phase 1 is one admin-only Web workspace. Native apps keep supplying attendance
events and may consume the same server contract later.

### Board contract

- one row per child, even if duplicate same-day sessions exist;
- one verified arrival satisfies the centre-level arrival state for the day;
- session attendance remains separate for class reporting;
- a child becomes due at the earlier of a server-confirmed **Start Class** action
  or five minutes after the authoritative scheduled start;
- before the due trigger the child is `not due`; afterward a missing accepted
  attendance fact is unresolved;
- the Board displays name, class, and accountability status only;
- unresolved children appear before accounted-for children; and
- all-clear appears only when the snapshot is fresh and no blocker remains.

The Board shows server-known facts only. A fully offline device queue is visible
on that device, not to the canonical server snapshot. A due child with no server
fact is unresolved; the Board never guesses `client-pending`.

### Canonical architecture

```text
authoritative calendar + roster + attendance + server evidence
                              |
                              v
          RLS-protected security-invoker Supabase RPC
                              |
                              v
                admin Web Board + derived Inbox
```

Clients do not independently reconstruct accountability truth. The first design
uses bounded polling, refetches after writes/resume/reconnect, rejects older
responses, and exposes snapshot age. If the snapshot is stale or unavailable,
the workspace removes child data, shows a hard failure, and directs staff to the
approved paper fallback.

Study Space uses a separately named internal live-safety projection when needed.
It remains excluded at the source from reports, exports, summaries, analytics,
awards, report cards, and every parent-facing surface.

### Exception lifecycle

The RPC derives unresolved conditions. It does not create rows while reading.
A durable case begins when an authorised admin first claims or acts on a derived
item. The workflow stores only lifecycle facts:

- stable condition identity and source age;
- owner, next action, and escalation;
- resolution evidence, correction, and reopening; and
- actor, server time, and mutation identity.

Attendance and roster tables remain the operational sources of truth. UI
in-flight protection and server idempotency ensure one user intent creates one
audit event. An active source condition cannot be hidden by resolving its case.

## Reliability and rollout

- Pure domain functions own accountability transitions; Web components render
  states and a small coordinator owns polling/recovery.
- Tests use an injected clock and fake timers for due, freshness, retry, and
  recovery boundaries.
- Phase 1 proves twice the observed peak daily roster with 10 Board clients and
  canonical RPC p95 below 500 ms.
- Operational telemetry contains event type, timing, outcome, role, and
  correlation ID—never child names, contacts, notes, or individual status.
- Schema and role/security tests land and are verified before dependent Web
  code. The shared feature flag ships OFF, then opens to one admin in a
  controlled session.
- Rollback turns the flag OFF first and preserves workflow evidence.

## Later phases

### Handoff evidence — provisional

Observe independent travel, guardian pickup, arranged transport, staff escort,
changed plans, and non-response before designing the model. The UI names only
the event actually proved. Current delete-based dismissal history is not
audit-grade handoff evidence and must not be presented as such.

### Parent Assurance Channel

Start with one channel and one high-value trigger. Sending is not proof of
receipt. Delivery failure, expired action, and required non-response feed the
Exception Inbox. Handoff-related messages wait for the approved responsibility
boundary. Before any new parent-visible event ships, verify that the current
data-protection notice covers its purpose; otherwise complete the notice,
consent, DPO, and re-publication gates in `HUMANS.md` and `docs/pdpa/`.

### Longitudinal child context

Add only a fact shown during the pilot to change a safe action. Every fact needs
a source, purpose, access boundary, correction path, retention rule, and audit.
Never collect data merely to create a moat.

## Approval gates

- Product owner and centre lead approve the post-pilot state specification,
  exception catalogue, role/action matrix, and executable acceptance tests.
- The privacy/DPO reviewer also approves handoff, parent, or longitudinal data
  before those phases begin.
- Planned work lives in `NEXT_BUILD_CHANGES.md`; completed work moves to
  `RELEASE_NOTES.md` under `Unreleased`.
