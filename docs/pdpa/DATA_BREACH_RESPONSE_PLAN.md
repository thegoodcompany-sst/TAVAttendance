# TAVA Attendance — Data Breach Response Plan

> **DRAFT — requires DPO/legal ownership and sign-off.** This operational plan
> supports Singapore's PDPA Data Breach Notification Obligation. It is not a
> substitute for advice on a specific incident.

Official references:

- [PDPC Guide on Managing and Notifying Data Breaches](https://www.pdpc.gov.sg/help-and-resources/2021/01/data-breach-management-guide)
- [PDPC breach self-assessment](https://www.pdpc.gov.sg/Report-Data-Breach/Self-Assessment)

## Scope and activation

Activate this plan for suspected unauthorised access, collection, use,
disclosure, copying, modification or disposal of personal data; loss of a
device or storage medium; foreign-account data appearing in a client; exposed
credentials with credible access; or unavailable/corrupted personal data.

Do not wait for certainty. Open a restricted incident record and assign an
incident identifier. Use UTC and Singapore timestamps throughout.

## Roles

| Role | Responsibility | Named owner |
|---|---|---|
| Incident lead | coordinates containment, decisions and timeline | _[name]_ |
| DPO | owns PDPA assessment/notification and parent communications | _[to be appointed]_ |
| Technical lead | preserves evidence, scopes access and remediates | _[name]_ |
| Management/legal | approves risk and external statements | _[name/contact]_ |

If the DPO is unavailable, management appoints an acting owner immediately.
Only authorised responders receive raw logs or children's data.

## 1. Contain and preserve

Contain ongoing harm first, while preserving enough evidence to understand it:

1. Record who discovered the issue, exact time, environment, affected account,
   device/build/deployment, symptoms and actions already taken.
2. Export or preserve relevant restricted evidence before routine retention
   expires: Supabase Auth/API/Postgres/Edge logs, Vercel logs, `audit_log`,
   `data_disclosures`, deployment/commit IDs and affected-device state.
3. Do not paste JWTs, cookies, database URLs, secrets, message bodies, student
   names or raw logs into tickets/chat. Store evidence in an access-controlled
   incident folder and record hashes for exported files.
4. Disable affected accounts/sessions and isolate a compromised device or
   deployment. Do not wipe it until evidence has been preserved unless wiping
   is necessary to prevent immediate harm.
5. Rotate only credentials plausibly exposed, in dependency order:
   service-role key, database password, dedicated Edge/Vault invocation
   secrets, provider keys, Vercel/deployment tokens and affected user
   credentials. Update authorised consumers, revoke old values and record each
   action. The anon key is public by design; rotate it only for a specific
   abuse/key-rollover reason, not as a substitute for fixing RLS.
6. If access scope is unclear, disable the affected feature or deployment while
   preserving a known-good public privacy/contact route.

Do not rewrite Git history, delete accounts/data, purge logs or “clean up” the
database during initial containment.

## 2. Assess

Build and continually update a fact table:

- when the breach began, was detected, contained and assessed;
- systems, tables/buckets/logs and environments affected;
- categories and sensitivity of data, including free text, attendance/pick-up
  patterns, results, photos and credentials;
- actual or reasonably estimated number and groups of individuals;
- whether data was viewed, copied, altered, deleted, encrypted or recovered;
- actor/cause, access path, persistence and evidence of misuse;
- mitigating controls such as encryption and confirmed key non-disclosure;
- likely harm and actions individuals can take.

Children's data warrants heightened risk analysis, but do not state a legal
conclusion without the DPO/legal assessment.

Under the current PDPC guidance:

- notify the PDPC if significant harm is likely **or** the breach affects (or
  is reasonably believed to affect) 500 or more individuals;
- notify affected individuals as soon as practicable when significant harm is
  likely, subject to applicable exceptions/directions;
- notify the PDPC as soon as practicable and no later than 3 calendar days
  (72 hours) after determining the breach is notifiable.

Record the assessment time and rationale even when the decision is not to
notify. Use the PDPC self-assessment as support, not as a definitive legal
decision.

## 3. Report and communicate

For a notifiable incident:

1. DPO/legal submits the PDPC notification with the known facts, timing, data
   and number affected, likely harm, containment/remediation and contact.
   Supplement it when facts change; do not delay the initial deadline waiting
   for a perfect investigation.
2. Notify affected parents/guardians as soon as practicable at the same time
   as or after the PDPC, unless an exception or direction applies. For an
   incident likely to attract public attention, notify the PDPC before public
   or individual statements.
3. State what happened, what data was affected, what TAVA has done, concrete
   protective actions, what remains unknown, and the DPO contact. Do not
   speculate, minimise or expose another child.
4. Route media/law-enforcement/provider communications through the incident
   lead and preserve copies.

## 4. Eradicate, recover and verify

- Fix the root cause in a reviewed commit/migration; patch vulnerable
  dependencies and remove persistence.
- Run current-tree/history-aware secret review, dependency scans, CI, local SQL
  regressions, the production drift gate and
  `scripts/prod-security-check.sql`.
- Review RLS/grants, `security_principals`, Auth settings, private Storage,
  signed-upload/finalisation, cleanup queues, Edge invocation secrets and
  branch/deployment protection relevant to the incident.
- Restore in stages. Verify least privilege, affected user flows, logging and
  alerting before returning to normal operation.
- Monitor for recurrence and credential use. Do not declare recovery merely
  because `/login` returns 200.

## 5. Evaluate

- Complete a blameless post-incident review within 2 weeks.
- Record root cause, control failures, detection gap, response timing, affected
  individuals, notification decision, corrective owners and due dates.
- Update threat model, tests, monitoring, training, this plan and HUMANS.md.
- Review whether retained data could be reduced and whether vendors/data
  intermediaries met their notification duties.

## Breach register

| Incident | Detected/assessed | Data and scope | Significant harm/scale | PDPC/individual notification | Cause | Containment/recovery | Owners/due dates |
|---|---|---|---|---|---|---|---|

Store the detailed register in an access-controlled location, not this public
repository.

_Operational content audited 2026-07-26; legal/DPO sign-off remains open._
