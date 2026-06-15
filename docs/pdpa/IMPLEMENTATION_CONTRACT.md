# PDPA Implementation Contract (backend → apps)

This is the frozen backend contract delivered by `supabase/migrations/011_pdpa_compliance.sql`
(already applied to the live DB). iOS, Android and web each implement the app-layer features
below against exactly these objects. **Do not change the migration files** — they are shared.

## New tables (RLS already configured)

| Table | Purpose | App access |
|---|---|---|
| `policy_documents` | Privacy notice text + version (`doc_type='data_protection_notice'`, `is_current=true`) | Any authed user can SELECT; admin writes |
| `consent_records` | Append-only consent ledger | Admin full; parent reads own child |
| `correction_requests` | Data-correction requests | Admin full; parent creates/reads own child |
| `data_disclosures` | Log of exports / SAR fulfilments | Admin only |
| `rate_limit_events` | Backs the invite rate limiter | service_role only (web server action) |

`students` gained `deactivated_at TIMESTAMPTZ`; `enrollments.unenrolled_at` is now auto-stamped.

## RPCs (call via PostgREST `rpc/<name>`)

| RPC | Args | Returns | Notes |
|---|---|---|---|
| `export_student_personal_data` | `p_student_id uuid` | `jsonb` bundle of all data on a student | admin-guarded; auto-logs a `data_disclosures` row |
| `anonymise_student` | `p_student_id uuid` | void | admin-guarded; redacts PII, keeps anonymous attendance |
| `erase_student` | `p_student_id uuid` | void | admin-guarded; hard delete + audit scrub |

`current_consent` view: latest consent row per `(student_id, consent_type)`.

## Consent model (agreed)

- **Admin attestation only** for now. When an admin creates a student (single or bulk import),
  the admin must tick *"Parent/guardian consent obtained for collection of this child's data"*.
  On save, insert a `consent_records` row:
  `{ student_id, consent_type:'data_collection', status:'granted', method:'admin_attestation',
     notice_version: <current policy_documents.version>, granted_by: <admin uid> }`.
- **Block student creation/import if the box is unticked.**
- Withdrawal = insert a new row with `status:'withdrawn'` (admin "Withdraw consent" action).
- Build UI so a future `method:'parent_in_app'` path can be added without schema change
  (parents barely use the app today — do not build parent-facing consent yet).

## Per-platform feature checklist (all three platforms)

1. **Privacy notice screen** — fetch `policy_documents` where `doc_type='data_protection_notice' AND is_current`, render `title`+`body`. Link it from settings / login footer.
2. **Consent attestation gate** — on single student create AND bulk CSV import; write `consent_records`; block on unticked.
3. **Consent view + withdraw** — in the student profile / admin student management.
4. **Erase / anonymise student** — admin action in student management; confirm dialog; call `anonymise_student` (default) or `erase_student` (explicit erasure request). Surface success/error via existing error-handling pattern.
5. **Subject-access export** — admin "Export this student's data" → call `export_student_personal_data`, save/share the returned JSON (filename `pdpa-export-<student_id>-<date>.json`).
6. **Correction-request review** — admin queue listing `correction_requests` where `status='pending'`; Apply (write the change + mark `applied` + add a `data_disclosures` row type `correction_response`) or Reject (mark `rejected` + `review_note`).
7. **NRIC/sensitive-data warning** — on any notes field (student/session/attendance), show inline guidance "Do not enter NRIC/FIN or sensitive identifiers." The DB also rejects NRIC-pattern notes with an error — surface that error gracefully.
8. **Result-slip uploads** — confirm uploads target the (now private) `result-slips` bucket; store objects under path `"<student_id>/<filename>"` so the parent-read storage policy works.

### Platform-specific
- **iOS / Android only:** clear the offline pending-attendance cache promptly after successful sync (device-side PII hygiene). iOS: `PendingAttendanceStore`. Android: equivalent store.
- **Web only:** add an **invite rate limit** to `web/app/actions/invite.ts` using `rate_limit_events`
  (admin/service client): before inviting, count rows where `actor_id=<caller>` AND `action='invite'`
  AND `created_at > now() - interval '1 hour'`; if `>= 20`, return an error; else insert one and proceed.

## Conventions
- Match existing patterns in each platform (error handling: iOS `AppError`/`errorAlert`, web throws in `lib/queries.ts`, Android `runCatching`).
- Add at least one unit test mirroring the repo's existing test style per platform where feasible.
- Do **not** edit `supabase/migrations/**`.
