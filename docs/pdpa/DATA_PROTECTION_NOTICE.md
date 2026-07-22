# TAVA Attendance — Data Protection Notice

> **DRAFT v1.1 — requires DPO / legal sign-off before publication.** This is the full source
> text. The in-app summary is seeded into the `policy_documents` table (v1.1, migration 015);
> keep the two in sync and bump the `version` whenever this changes.

## Who we are
TAVA is a **study centre operated by Talent Beacon**, a non-profit serving youth and residents of
Bukit Batok. **Talent Beacon** ("we", "us", "the Centre") is the **organisation** responsible for
the personal data described here under the Personal Data Protection Act 2012 (PDPA), and uses the
TAVA Attendance platform to administer the Centre's programmes.

**Data Protection Officer:** _[name / role — to be completed, see HUMANS.md]_, admin@talentbeacon.org,
Talent Beacon, 209 Bukit Batok Street 21, #01-182, Singapore.

## Whose data we collect
- **Students** (most of whom are minors) — name, date of birth, school, year of study, attendance
  records, late reasons, exam result slips, dismissal/pick-up records, awards, and any notes the
  Centre records for the Centre's programmes.
- **Parents/guardians** — name, contact number, relationship to the student, and any messages.
- **Tutors and administrators** — name, contact number, and account/role information.

## Purposes for which we use personal data
1. Enrolling students and managing class rosters.
2. Recording and reporting attendance and punctuality.
3. Recording exam results and academic progress.
4. Managing safe dismissal / pick-up of students.
5. Communicating with parents/guardians about the student and centre matters.
6. Meeting legal, accounting and record-keeping obligations.

We do **not** use personal data for purposes a reasonable person would not consider appropriate
in the circumstances, and we do not collect national identifiers (e.g. NRIC/FIN). The system
actively rejects NRIC/FIN-formatted text entered into free-text notes.

## Consent (including minors)
For students who are minors, we rely on the consent of a **parent or legal guardian**, obtained at
enrolment. The Centre records the fact, date and notice version of that consent. You may
**withdraw consent** at any time by contacting the DPO; we will then stop collecting, using or
disclosing the personal data, subject to legal retention requirements, and explain the likely
consequences (e.g. we may be unable to continue providing the Centre's programmes).

## Disclosure
We disclose personal data only to:
- Centre staff (tutors/administrators) who need it for the purposes above; and
- Our data intermediary **Supabase** (hosting/processing on AWS, Singapore region), under
  contract to protect it.

We do not sell personal data or use it for third-party marketing.

## Protection
Data is stored in **Singapore (Supabase, ap-southeast-1)** and protected by encryption in transit
(TLS) and at rest (AES-256), role-based access (row-level security), audit logging, and access
controls. See `DATA_BREACH_RESPONSE_PLAN.md` for how we handle incidents.

## Retention
We keep personal data only as long as necessary for the purposes above and for legal record-keeping
— **up to 7 years after a student leaves the Centre** — after which direct identifiers are removed
and any retained attendance history remains protected as pseudonymised data, or the data is erased.
See `DATA_RETENTION_SCHEDULE.md`.

## Your rights — access and correction
You may request **access** to the personal data we hold about you or your child, and information
about how it has been used or disclosed in the past year, and you may request **correction** of any
error or omission. Contact the DPO. We will respond within the timeframes required by the PDPA and
may charge a reasonable fee for an access request.

## Overseas transfer
Personal data is hosted in Singapore. If data is ever transferred outside Singapore, we will ensure
a comparable standard of protection as required by the PDPA.

## Changes
We may update this notice. The current version is shown in the app; the version number changes
when the notice changes.

_Last updated: 2026-06-26 (draft v1.1)._
