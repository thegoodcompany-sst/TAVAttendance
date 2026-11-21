# Teacher prompts HTTP contract

The Swift app can keep its existing JSON models and use a Convex Auth session. Every application response below is one JSON object. Public IDs are UUID strings. Incoming UUIDs accept uppercase from Foundation. Outgoing UUIDs are lowercase. Instants are UTC ISO 8601 strings with milliseconds. Keep `marked_at` exactly as received for the next compare-and-set. Revisions are decimal **strings**. Dates are Singapore civil dates.

## Session

All four auth operations accept JSON at `POST https://<deployment>.convex.cloud/api/mutation` with `Content-Type: application/json`. They accept credentials in the body and work with URLSession or curl. Send access JWTs as bearer tokens only on authenticated application calls. Keep passwords, invitations, and request/response token values out of logs.

**Activate once.** A trusted operator provisions the email, role and digest of a privately delivered invitation. The invitation expires after 24 hours. The teacher chooses a password of at least 10 characters. Password policy errors leave the invitation usable.

```json
{"path":"auth:activate","format":"json","args":{"email":"teacher@example.invalid","invitation":"<one-time secret>","password":"<chosen password>"}}
```

**Sign in** on subsequent visits.

```json
{"path":"auth:signIn","format":"json","args":{"email":"teacher@example.invalid","password":"<password>"}}
```

Activation and sign-in both return the following successful response shape. `userId` is internal. Call `teacher:my_profile` for the public staff UUID that owns the device and queued work. Convex verifies the session JWT against the deployment's cloud JWKS.

```json
{"status":"success","value":{"status":"complete","tokens":{"accessToken":"<access JWT>","refreshToken":"<refresh token>","refreshTokenExpiresAt":1800000000000,"userId":"<Convex user ID>"}}}
```

Inspect both levels of the response. A password rejection has outer `status:"success"` and inner `value.status:"error"` with `userError.error`. Sign-in uses `INVALID_CREDENTIALS` for unknown, inactive, incorrect, or rate-limited credentials. A denied invitation is a Convex error with `errorData:"TP_NOT_AVAILABLE"`.

**Refresh** through its own mutation.

```json
{"path":"auth:refreshSession","format":"json","args":{"refreshToken":"<current refresh token>"}}
```

On `value.kind:"rotated"`, persist both tokens from `value.tokens` together. Serialize refreshes within each session. After a lost response, retry with the last persisted refresh token. On `value.kind:"noSession"`, clear credentials and require sign-in. The default access-token lifetime is one minute. An authenticated request rejected for expiry can be retried once after a successful refresh.

**Sign out.** First unregister the installation under its original session. Send the current refresh token to the following mutation, even if the access JWT expired. Success returns `{"status":"success","value":null}`. The revoked session immediately loses access to staff data. Clear local session state on sign-out, including when the server is unreachable.

```json
{"path":"auth:signOut","format":"json","args":{"refreshToken":"<current refresh token>"}}
```

## Calling the teacher API

Send `Authorization: Bearer <access JWT>` and `Content-Type: application/json` to either interface.

- **Site HTTP actions** use `POST https://<deployment>.convex.site/v2/<name>`. Send the argument object directly and decode the result directly. For example, `POST /v2/my_lessons_today` with `{}` returns the lesson list.
- **Standard Convex (used by iOS)** uses `POST https://<deployment>.convex.cloud/api/query` or `/api/mutation`. Send `{"path":"teacher:my_lessons_today","format":"json","args":{}}`. Read `value` on success. The module is `teacher` for lesson/profile calls and `devices` for registration. Thus registering a device uses `"path":"devices:register_device"` at `/api/mutation`.
- The dev hosts are `adept-duck-658.convex.site` and `adept-duck-658.convex.cloud`. Key discovery is available at `/.well-known/jwks.json` on the site host.

### Reads

| Name | JSON arguments | JSON result |
|---|---|---|
| `my_profile` | `{}` | `{id,display_name,role,active,teacher_prompts,teacher_prompt_push}` |
| `my_lessons_today` | `{}`, `{"p_date":null}` or `{"p_date":"2027-01-07"}` | `{server_now,date,lessons:[Summary],outstanding_count,backlog:[Summary]}` |
| `lesson_for_prompt` | `{"p_lesson_id":"<lesson UUID>"}` | `{server_now,lesson:Summary,roster:[Student],feedback:{body,revision},submission:Submission|null}` |

An authenticated staff member can read their own profile and both rollout flags during disablement or deactivation so their installation can be revoked. Lesson access still requires an active profile and the workflow flag.

A `Summary` has the following wire shape. The values here illustrate a 19:00–21:00 class.

```json
{
  "lesson_id":"00000000-0000-4000-8000-000000000001",
  "class_id":"00000000-0000-4000-8000-000000000002",
  "class_label":"English",
  "scheduled_start_at":"2027-01-07T11:00:00.000Z",
  "scheduled_end_at":"2027-01-07T13:00:00.000Z",
  "state":"awaiting_attendance",
  "accountable_teacher_id":"00000000-0000-4000-8000-000000000003",
  "accountable_teacher_label":"Demo Teacher",
  "is_accountable":true,
  "register_revision":"0",
  "roster_count":3,
  "marked_count":0,
  "submitted_at":null,
  "next_prompt_at":"2027-01-07T13:15:00.000Z",
  "snoozed_until":null,
  "overdue_at":"2027-01-08T01:15:00.000Z",
  "can_edit":true,
  "can_submit":false,
  "can_snooze":true
}
```

The six states are `scheduled`, `in_progress`, `awaiting_attendance`, `overdue`, `submitted` and `cancelled`. A `Student` has `{student_id,display_name,status,absence_informed,marked_at}`. An unmarked student has null in the last three fields. Feedback starts at `{"body":"","revision":"0"}`. A `Submission` has `{id,submitted_at,submitted_by,register_revision}`.

### Writes

Every lesson write includes these two required fields in the same JSON object as its additional fields.

```json
{"p_lesson_id":"<lesson UUID>","p_mutation_id":"<new UUID for this intent>"}
```

Reuse that mutation UUID and identical arguments only when retrying the same intent as the same actor. A successful lesson write always includes `lesson_id` and `replayed` (boolean) alongside the result fields below. A successful replay preserves the original result even after submission, provided the caller still has authority.

| Name | Additional JSON fields (example values) | Additional result fields |
|---|---|---|
| `mark_attendance` | `{"p_student_id":"<UUID>","p_status":"absent","p_absence_informed":true,"p_observed_marked_at":null,"p_expected_revision":"0"}` | `student_id,status,absence_informed,marked_at,register_revision` |
| `mark_all_present` | `{"p_expected_revision":"0"}` | `changed_count,register_revision` |
| `save_feedback` | `{"p_expected_feedback_revision":"0","p_body":"Lesson reviewed."}` | `feedback_revision` |
| `submit_lesson` | `{"p_expected_revision":"1","p_expected_feedback_revision":"0"}` | `submission_id,submitted_at,register_revision` |
| `confirm_all_present_and_submit` | `{"p_expected_revision":"0","p_expected_feedback_revision":"0"}` | `submission_id,submitted_at,register_revision` |
| `snooze_prompt` | `{"p_minutes":10}` | `snoozed_until,next_prompt_at,overdue_at` |

`mark_attendance` requires all nullable keys explicitly. Set `p_status:null` to clear the row. Valid stored statuses are `present`, `late`, `absent`. Only absent accepts a non-null informed flag. Send the projected timestamp when changing or clearing a marked row. On conflict, fetch the current projection and ask the teacher to review it. Only the explicit confirmation action fills unmarked rows and submits in one transaction. Ordinary submit requires a complete register. Feedback is optional.

**Device mutations** have their own argument and receipt shapes.

| Name | Complete JSON arguments | JSON result |
|---|---|---|
| `register_device` | `{"p_installation_id":"<UUID>","p_token":"<lowercase hex>","p_environment":"sandbox"}` | `{device_id,last_seen_at,environment}` |
| `unregister_device` | `{"p_installation_id":"<UUID>"}` | `{"revoked":true}` |

Environment accepts `sandbox` or `production`. Tokens are 16–256 bytes encoded as even-length lowercase hex. Opt-out covers both environments, requires the original authenticated owner, and works after rollout disablement or profile deactivation. A missing/foreign installation returns the same acknowledgement.

### Administration

Use standard Convex endpoints and the `calendar:` module. Each operation derives the active admin role from the database. `admin_missing_submissions` is a query with `{p_from,p_until}` inclusive (up to 92 days). It returns `{server_now,from,until,lessons}` with `delivery_state` and nullable `last_attempt_at` on each summary. Delivery states are `not_attempted`, `pending`, `accepted`, `no_devices` and `failed`. `edit_lesson` takes `{p_lesson_id,p_start_at,p_end_at}`, `assign_lesson_teacher` takes `{p_lesson_id,p_teacher_id,p_keep_previous_as_assistant}`, and `cancel_lesson` takes `{p_lesson_id}`. All three mutations return the updated summary.

### Errors

The site API returns `{"error":"TP_CONFLICT"}` for a stale write, for example. Standard APIs return a Convex error envelope with `status:"error"` and the domain string in `errorData` for application errors. Check the envelope as well as HTTP status. Native clients should map malformed standard-function arguments to `TP_INVALID_INPUT`, invalid or expired bearer credentials to `sessionExpired`, and connectivity or unrecognized server failures to `network`. A platform-rejected JWT can produce HTTP 401 before the site handler runs. Keep provider error messages, passwords and tokens out of client logs.

| Site HTTP status | Swift raw value | Meaning |
|---|---|---|
| 400 | `TP_INVALID_INPUT` | Invalid fields or domain value |
| 401 | `sessionExpired` | Authentication required |
| 403 | `TP_DISABLED` | Master flag OFF |
| 404 | `TP_NOT_AVAILABLE` | Missing lesson or insufficient current authority |
| 409 | `TP_CONFLICT` | Stale revision, observation or calendar overlap |
| 409 | `TP_INCOMPLETE` | Unmarked roster members, or empty teacher register |
| 409 | `TP_LOCKED` | Work closed to this change |
| 409 | `TP_TOO_EARLY`, `TP_TOO_OLD` | Outside the action's time window |
| 409 | `TP_SNOOZE_LIMIT`, `TP_NO_PENDING_PROMPT` | Snooze exhausted or no remaining stage |
| 409 | `TP_MUTATION_REUSED` | Same actor/key with different operation or arguments |
| 500 | `network` | Unexpected handler failure |
