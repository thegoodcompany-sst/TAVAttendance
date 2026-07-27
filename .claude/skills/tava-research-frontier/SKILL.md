---
name: tava-research-frontier
description: Use when choosing what TAVA should build next. Separates current security/operations blockers from dark feature rollout and speculative product work.
---

# TAVA research frontier

Start with current evidence, not the old roadmap. Many formerly “future”
features now exist behind flags: parent results/messages, safely-home push,
session notes, QR sign-in, awards, analytics and retrospective sessions.
Measure live flags and production gates before calling any of them shipped.

## Idea lifecycle

1. Check `tava-failure-archaeology`, HUMANS.md and recent Git history.
2. Write a dated spec/acceptance test for non-trivial work.
3. Add schema as a new migration with reverse script and security regressions.
4. Ship dark with missing/error = OFF; apply schema before clients.
5. Validate every role/platform, then perform a separate human-gated rollout.
6. Record either the measured outcome or the reason the idea was retired.

## Tier 0 — security and operational readiness

These outrank new product work:

1. Rotate the exposed App Review account and production DB credential; complete
   reviewed history cleanup (HUMANS.md §66).
2. Verify/apply the migration-038 boundary and later grant migrations in
   production; require remote security/drift checks (§60/§67).
3. Enforce MFA/AAL2 for privileged users (§62).
4. Replace the full-admin kiosk identity and move the iOS PIN verifier plus
   native offline queues to Keychain/Keystore authenticated encryption
   (§§63–64).
5. Deploy/arm/monitor the durable Storage cleanup worker (§65).
6. Deploy and verify exact-origin web headers (§68).
7. Close DPO/legal/retention decisions (§§46–51/69).

Milestone: all relevant executable gates pass against production, privileged
accounts use MFA, credentials are rotated, and each remaining legal/device
gate has a named owner/date.

## Tier 1 — validate dark workflows

- **Parent portal:** UI exists on all clients with shaped migration-038 RPCs.
  Create a test parent/link and verify exactly one child's non-Study-Space
  attendance/results/messages on every current client.
- **Push/safely home:** APNs/FCM code and triggers exist. Verify dedicated
  invocation secrets, provider credentials, device entitlements and a complete
  dismissal/confirmation round trip before enabling globally.
- **Retrospective sessions:** native clients exist; finish current web handoff
  and physical role/offline/audit QA before flag enable.
- **Analytics, photos, notes, QR and awards:** query live state, validate data
  minimisation/permissions and roll out one flag at a time with rollback.

Milestone: each enabled flag has a dated role matrix, supported minimum client
versions, production evidence and rollback owner.

## Tier 2 — resilience

- Encrypt native pending queues and test account/key invalidation.
- Add security monitoring for Auth anomalies, cleanup queue age, Edge failures,
  drift/advisor changes and privileged actions.
- Exercise the breach plan and backup/restore process with synthetic data.
- Replace environment/operator-dependent release steps with protected,
  provenance-recording workflows.

Milestone: a tabletop incident and restore drill meets documented detection,
containment and recovery objectives without exposing real student data.

## Tier 3 — candidates only

Absence early-warning, multi-centre tenancy, NFC sign-in, food polls and
attendance-to-outcome analysis remain candidates. Require demand validation,
PDPA purpose/retention review and a falsifiable trial before implementation.

## Provenance

Audited 2026-07-26 against README, flags through migration 037, migration 038,
release history and HUMANS.md §§60–69.
