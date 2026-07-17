# Native Parent Portal Phase 2 Design

**Date:** 2026-07-17  
**Platforms:** iOS and Android  
**Feature flag:** `parent_portal` (remains OFF until centre verification)

## Goal

Bring the web parent portal's Phase 2 capabilities to the native apps while preserving the existing attendance and safely-home flows.

Parents can:

- view each linked child's 30-day attendance history;
- submit and view text-only exam results;
- see whether a result has been acknowledged by TAVA;
- exchange private per-child messages with TAVA.

Native result submissions do not upload PDF or image files. File uploads remain available on the web portal.

## Existing foundation

Both apps already:

- route `parent` accounts to a feature-flagged parent dashboard;
- fetch linked children through parent-scoped student RLS;
- show attendance history through the shared student profile UI;
- exclude Study Space attendance at the query source;
- show pending safely-home confirmations.

The backend is already live:

- migration 035 permits parent-owned `result_slips` and `messages` inserts;
- migration 036 scopes messages to the sending or receiving parent;
- admins acknowledge results and reply to messages from the web dashboard.

No new migration, bucket, RPC, or feature flag is required.

## Navigation and UI

The parent dashboard and safely-home cards remain unchanged.

Tapping a child opens the existing child-detail presentation in parent mode. Parent mode adds three tabs:

1. **Attendance** — current 30-day summary and session history.
2. **Results** — result list, acknowledgement state, and an append-only result form.
3. **Messages** — private chronological thread and message composer.

Staff continue using the current profile presentation without parent tabs or messaging. The shared profile receives a parent-mode input rather than creating a duplicate attendance screen.

### Results tab

Each row shows:

- subject;
- exam name;
- exam date;
- score / maximum score;
- `Acknowledged` or `Pending review`.

The add form uses native controls:

- subject picker (Math / English);
- required exam-name text field;
- date picker;
- score and maximum-score numeric fields.

Submissions are append-only. Native apps do not provide result edit, delete, or file upload.

### Messages tab

The thread shows parent messages on the trailing side and TAVA replies on the leading side. Each bubble may show its optional subject.

The composer contains:

- optional subject;
- required message body;
- Send button.

Messages refresh when the tab opens, when the user retries, and after a successful send. Realtime subscriptions and push-to-thread navigation are out of scope.

## Data contracts

### Result slip

Native models decode:

- `id`;
- `student_id`;
- `exam_name`;
- `exam_date`;
- `subject`;
- `score`;
- `max_score`;
- `uploaded_at`;
- `acknowledged_at`.

A parent insert sends:

- `student_id`;
- `exam_name`;
- `exam_date`;
- `subject`;
- `score`;
- `max_score`;
- `uploaded_by = current authenticated user`;
- no `file_path`.

Validation occurs before the network call:

- exam name is non-empty;
- score is finite and at least zero;
- maximum score is finite and greater than zero;
- score does not exceed maximum score.

### Message

Native models decode:

- `id`;
- `sender_id`;
- `recipient_id`;
- `student_id`;
- `subject`;
- `body`;
- `sent_at`;
- `read_at`.

Parent reads filter by `student_id`; migration 036 RLS further limits rows to `sender_id = auth.uid()` or `recipient_id = auth.uid()`.

A parent insert sends:

- `sender_id = current authenticated user`;
- `student_id`;
- `recipient_id = null`;
- optional trimmed subject;
- required trimmed body.

Admin replies continue to be sent from the web dashboard with `recipient_id` set to the target parent.

## Platform implementation

### iOS

- Extend `ResultSlip` with acknowledgement data and add a message model.
- Add result-submit and message fetch/send methods to `AttendanceService`.
- Add parent mode and tab selection to the existing `StudentProfileView`.
- Reuse `ResultSlipUploadSheet`, adding parent-safe validation and `uploaded_by`.
- Add a focused messages view/composer under `Views/Parent/`.
- Add English and Simplified Chinese strings to the String Catalog.
- Surface independent tab failures with `AppError` / `errorAlert` without replacing successfully loaded tabs.

### Android

- Add serializable result-slip and message models.
- Add result fetch/submit and message fetch/send methods to `AttendanceService`.
- Extend `StudentProfileViewModel` with independent attendance, result, and message state.
- Add parent mode and a Material 3 tab row to `StudentProfileSheet`.
- Add text-only result form and message composer using existing Compose patterns.
- Surface load errors with retry state and write errors through `rememberSnackbarError`.

## Privacy and invariants

- All access uses the signed-in user's Supabase client; mobile code never uses the service-role key.
- Parent ownership is enforced by RLS, not by trusting route parameters or local state.
- Migration 036 prevents one linked parent from reading another linked parent's direct thread.
- Study Space remains excluded in `fetchStudentAttendanceHistory` on both platforms.
- Result submissions contain no native file attachment and do not request photo or storage permissions.
- The feature remains behind the existing global `parent_portal` flag.

## Error handling

Attendance, Results, and Messages load independently. A failure in one tab does not erase or hide data from another tab.

Writes:

- disable the submit button while in flight;
- retain entered form text after failure;
- clear the form only after success;
- refresh the affected list after success;
- present a user-actionable error with retry guidance.

## Verification

### Automated

- iOS XCTest: result validation accepts valid values and rejects negative, zero maximum, non-finite, and score-greater-than-maximum inputs.
- Android unit test: equivalent result validation cases.
- Existing iOS and Android test suites remain green.

### Manual

With a linked parent account and `parent_portal` enabled in a non-production verification context:

1. Open each linked child and switch among all three tabs.
2. Confirm Attendance excludes Study Space.
3. Submit a valid text-only result and see `Pending review`.
4. Acknowledge it on web `/result-slips`; refresh native and see `Acknowledged`.
5. Send a parent message; confirm it appears on web `/messages` under the correct parent and child.
6. Reply on web; refresh native and confirm only the intended parent sees it.
7. Disable connectivity and confirm each failed write retains its form values and shows a retryable error.
8. Confirm safely-home and sign-out behavior remain unchanged.

## Non-goals

- Native PDF/image result-slip upload or viewing.
- Native admin/tutor acknowledgement or message-reply UI.
- Message realtime subscriptions, typing indicators, attachments, search, or push deep links.
- Result editing or deletion.
- New database objects or feature flags.
