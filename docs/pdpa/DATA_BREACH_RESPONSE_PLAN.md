# TAVA Attendance — Data Breach Response Plan

> **DRAFT — requires DPO ownership and sign-off.** Implements the PDPA Data Breach Notification
> Obligation (ss 26A–26E), mandatory since 1 Feb 2021.

## Scope
A "data breach" is unauthorised access, collection, use, disclosure, copying, modification or
disposal of personal data, or loss of storage media/device on which personal data is stored.

## Roles
- **Data Protection Officer (DPO):** owns this plan, decides on notification. _[to be appointed]_
- **Technical lead:** contains and investigates. _[name]_
- **Management:** approves external communications.

## Step 1 — Contain (immediately)
- Revoke/rotate compromised credentials and the Supabase service-role key.
- Disable affected accounts; if needed, rotate the Supabase anon key (dashboard).
- Preserve evidence: do not delete logs. Capture `audit_log`, Supabase logs, and access logs.

## Step 2 — Assess (within hours)
Determine what data, how many individuals, and the likely harm. **Children's personal data is
involved in almost every table** — assume elevated harm.

A breach is **notifiable** if it:
- is likely to result in **significant harm** to affected individuals (e.g. exposure of children's
  identities, schools, attendance/pick-up patterns, results); **or**
- is of **significant scale** — **500 or more** individuals.

## Step 3 — Notify (if notifiable)
- **PDPC:** as soon as practicable, **no later than 3 calendar days** after assessing the breach is
  notifiable. Use the PDPC data breach notification form: https://www.pdpc.gov.sg
- **Affected individuals (parents/guardians):** notify as soon as practicable, at the same time as
  or after notifying PDPC, unless an exception applies (e.g. remedial action makes significant harm
  unlikely, or a law-enforcement/PDPC direction to withhold). Use the templates below.

## Step 4 — Remediate & review
- Fix the root cause; run `get_advisors` (security + performance) and re-check RLS.
- Record the incident in the breach register (date, scope, cause, actions, notifications).
- Post-incident review within 2 weeks; update controls and this plan.

## Breach register (maintain)
| Date | Discovered by | Data/scope | Notifiable? | PDPC notified | Individuals notified | Root cause | Actions |
|---|---|---|---|---|---|---|---|

## Notification templates
**To PDPC (summary):** _Nature of breach, when/how discovered, personal data and number of
individuals affected, likely harm, remedial actions taken/planned, DPO contact._

**To parents/guardians:** _"We are writing to inform you of a data security incident affecting
personal data relating to your child… [what happened, what data, what we are doing, what you can do,
DPO contact]."_

## Detection aids (technical)
- `audit_log` records every change with `changed_by`; `data_disclosures` logs exports/SAR.
- Recommended: enable Supabase log alerts and review `get_advisors` regularly (see HUMANS.md).

_Last updated: 2026-06-15 (draft)._
