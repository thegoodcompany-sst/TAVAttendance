# PDPA Implementation Contract (backend → apps)

This began as the frozen backend contract delivered by migration 011. Migration
038 intentionally supersedes the unsafe parent/erasure/upload access described
by that historical baseline; the table purposes remain, but the current access
contract below is authoritative. Existing applied migrations remain immutable.

## New tables (RLS already configured)

| Table | Purpose | App access |
|---|---|---|
| `policy_documents` | Privacy notice text + version (`doc_type='data_protection_notice'`, `is_current=true`) | Any authed user can SELECT; admin writes |
| `consent_records` | Append-only consent ledger | Admin only; no parent base-table read |
| `correction_requests` | Data-correction requests | Admin SELECT only; review through `review_correction_request`; add a rate-limited shaped parent submission RPC before exposing a parent UX |
| `data_disclosures` | Log of exports / SAR fulfilments | Admin only |
| `rate_limit_events` | Backs the invite rate limiter | service_role only (web server action) |

`students` gained `deactivated_at TIMESTAMPTZ`; `enrollments.unenrolled_at` is now auto-stamped.

## RPCs (call via PostgREST `rpc/<name>`)

| RPC | Args | Returns | Notes |
|---|---|---|---|
| `export_student_personal_data` | `p_student_id uuid` | `jsonb` bundle of all data on a student | admin-guarded; auto-logs a `data_disclosures` row |
| `review_correction_request` | `p_request_id uuid, p_decision text, p_review_note text` | reviewed student UUID | admin-guarded; locks one pending request and atomically applies/rejects, derives reviewer/time, and appends a value-free disclosure event |
| `create_student_with_consent` | profile fields + `p_source_note` | student row | admin-only atomic student + initial consent event; direct student INSERT is denied |
| `record_admin_consent` | `p_student_id, p_consent_type, p_status, p_source_note` | consent UUID | admin-only append path; server derives method, notice, actor and time |
| `anonymise_student_secure` | `p_student_id uuid, p_actor_id uuid` | void | service-role-only web orchestration; **pseudonymises** by rotating identifiers/redacting PII, retains session-linked attendance facts, queues Storage cleanup |
| `erase_student_secure` | `p_student_id uuid, p_actor_id uuid` | void | service-role-only web orchestration; hard delete + audit scrub + durable Storage cleanup |
| `submit_app_events` | `p_events jsonb` | accepted count | shaped/bounded staff telemetry; server derives actor, role and time |
| `register_device_token` | `p_token text, p_platform text` | void | parent-only, push-flagged, native platforms, newest-five cap |
| `consume_invite_rate_limit` | `p_actor_id uuid` | void | service-only atomic 20/hour invite quota |

`current_consent` view: latest consent row per `(student_id, consent_type)`.

## Consent model (agreed)

- **Admin attestation only** for now. When an admin creates a student (single or bulk import),
  the admin must tick *"Parent/guardian consent obtained for collection of this child's data"*.
  Use `create_student_with_consent`; do not separately insert the student and
  `consent_records` row. Later grant/withdraw events use `record_admin_consent`.
- **Block student creation/import if the box is unticked.**
- Withdrawal = insert a new row with `status:'withdrawn'` (admin "Withdraw consent" action).
- Build UI so a future `method:'parent_in_app'` path can be added without schema change
  (parents barely use the app today — do not build parent-facing consent yet).

## Per-platform feature checklist (all three platforms)

1. **Privacy notice screen** — fetch `policy_documents` where `doc_type='data_protection_notice' AND is_current`, render `title`+`body`. Link it from settings / login footer.
2. **Consent attestation gate** — on single student create AND bulk CSV import; write `consent_records`; block on unticked.
3. **Consent view + withdraw** — in the student profile / admin student management.
4. **Erase / pseudonymise student** — admin action in student management; confirm dialog; use the trusted web Server Action. The legacy database function name contains `anonymise`, but retained longitudinal attendance may remain linkable and must not be described as anonymous. Use hard erasure for an accepted deletion request. Native clients fail closed to both paths.
5. **Subject-access export** — admin "Export this student's data" → call `export_student_personal_data`, save/share the returned JSON (filename `pdpa-export-<student_id>-<date>.json`).
6. **Correction-request review** — admin queue listing `correction_requests` where `status='pending'`; call `review_correction_request` for both Apply and Reject. Never update the student/request/disclosure tables as separate client operations. The RPC allowlists supported fields, locks the request, derives reviewer/time, and writes a minimal `correction_response` event without copying either corrected value.
7. **NRIC/sensitive-data warning** — on any notes field (student/session/attendance), show inline guidance "Do not enter NRIC/FIN or sensitive identifiers." The DB also rejects NRIC-pattern notes with an error — surface that error gracefully.
8. **Result-slip uploads** — the web server authorizes/rate-limits a random canonical path and mints a signed upload token. After direct upload it verifies size, MIME and file signature, then calls the service-only atomic finalizer. Parent bucket SELECT/INSERT policies do not exist; downloads are server-minted short-lived URLs.

### Platform-specific
- **iOS / Android only:** pending attendance is versioned and account-bound;
  purge legacy/corrupt/foreign-owner data, clear on sign-out, and recheck owner
  immediately before sync. App-level Keychain/Keystore encryption remains an
  operational hardening follow-up; do not regress to an unscoped queue.
- **Web only:** consume the atomic invite quota through the service-only
  `consume_invite_rate_limit` RPC immediately before inviting. Never implement
  a separate count-then-insert sequence in application code.

## Conventions
- Match existing patterns in each platform (error handling: iOS `AppError`/`errorAlert`, web throws in `lib/queries.ts`, Android `runCatching`).
- Add at least one unit test mirroring the repo's existing test style per platform where feasible.
- Do **not** edit `supabase/migrations/**`.
