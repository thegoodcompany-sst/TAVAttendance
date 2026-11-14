# Teacher prompts — implementation contract v1

Status: prototype contract, 2026-11-14. Owner: Edmund; integration: supervisor.
Normative words MUST/SHOULD describe implementation requirements, not live state.
The five implementation passes consume this file independently. Do not silently
rename interfaces; report necessary deviations to the supervisor before integration.

## 1. Scope, evidence, and safety

Build an interactive, local, fake-data prototype for a January 2027 fresh database:
calendar-backed lessons → generic phone reminder → authenticated attendance review
→ optional feedback → explicit submission → admin view of outstanding work.
Submission means the register was reviewed; it does not mean children went home.
No parent notification, dismissal, payment, behavioural scoring, or email workflow.

Read-only sources inspected for this contract:

- `/workspace/tav-eod-link/research.md` (t464u, including independent verification).
- `supabase/migrations/001_schema.sql`, `038_security_boundary_hardening.sql`,
  `054_defense_in_depth_authz.sql`, `060_atomic_offline_attendance_cas.sql`,
  `062_attendance_session_lock.sql`, and `supabase/functions/notify-parent/index.ts`.
- `web/AGENTS.md`, `web/package.json`, `web/app/actions/mobile.ts`, login/mobile layout;
  iOS `Core/AuthManager.swift`, `Core/PushManager.swift`, `TAVAttendanceApp.swift`;
  Android session auto-end and auth queue cleanup flows.
- `docs/KIOSK_ATTENDANCE.md`, `ROADMAP.md`, `HUMANS.md`, `PDPA_COMPLIANCE.md`.

Findings that drive the design: old sessions are client-created, unique per class/day;
native auto-end is not review; ended sessions reject normal corrections; existing
push registration is parent-only; login does not retain a lesson destination.
V2 deliberately replaces these seams. Nothing here asserts production readiness.
The research's email-first proposal is superseded by Edmund's explicit push brief.

Every pass MUST stay within its assigned paths and supervisor-assigned database.
Only `postgresql://postgres@localhost:55432/<assigned_db>` is permitted; no remote
database, Supabase API, credentials, `.env` inspection, deploy, real push, commit,
push, branch, or PR. Architect uses no database. Never reuse an existing DB name
unless assigned. Local binaries: `/workspace/tav-teacher-prompts/pgbin/package/native/bin`.
Do not edit the historical migration chain, live apps, or root release documents.
This explicit task overrides the usual commit/push and documentation-update rules.
No code in this pass; subsequent passes implement only their owned artifacts.

## 2. Ownership and layout (five implementation passes)

| Pass | Exclusive ownership | Interfaces consumed |
|---|---|---|
| A — database | All `supabase/v2/migrations/`, `local/`, `seed/`, `tests/` | This contract |
| B — dispatcher | All `supabase/v2/functions/` | A's SQL and wire shapes below |
| C — web | All `prototypes/teacher-prompts/` | A's RPCs; B's pure payload module |
| D — iOS sketch | All `docs/teacher-prompts/ios/` | RPCs, payload, route/action IDs |
| E — docs/runner | Other listed docs, diagrams, `scripts/teacher-prompts-local.sh` | All fixed entrypoints below |

`CONTRACT.md` remains architect/supervisor-owned. Tests belong with their owner.
No pass edits another pass's file to unblock itself; use explicit test doubles
matching these interfaces, label integration tests pending, and report the blocker.

Required paths (additional focused files inside owned directories are allowed):
```text
supabase/v2/
  local/supabase_shim.sql
  migrations/0001_core.sql
  migrations/0002_calendar.sql
  migrations/0003_attendance_rpc.sql
  migrations/0004_prompt_scheduler.sql
  seed/demo_week.sql
  tests/{schema,calendar,rls,attendance,submission,scheduler,devices,demo}_test.sql
  tests/concurrency_test.py
  functions/_shared/{prompt-dispatch,prompt-payload,prompt-strings}.ts
  functions/_shared/{apns-sender,dry-run-sender}.ts
  functions/teacher-prompt-dispatch/{index,local}.ts
  functions/tests/{dispatch,payload,apns-sender}.test.ts
  functions/{deno.json,package.json,bun.lock}
prototypes/teacher-prompts/
  package.json, bun.lock, next.config.ts, playwright.config.ts
  app/{layout,page,error}.tsx, app/globals.css
  app/demo/page.tsx, app/t/lesson/[lessonId]/page.tsx, app/admin/page.tsx
  app/actions/{identity,lessons}.ts
  lib/{db,identity,rpc,types,strings}.ts
  lib/queries/{lessons,admin}.ts
  tests/{identity,rpc}.test.ts
  e2e/{teacher-flow,authorization,reminders}.spec.ts
docs/teacher-prompts/
  README.md, cutover.md, strings.md, preview-deploy.md
  diagrams/{lesson-state,prompt-timeline,auth-route,dispatch}.mmd
  ios/Package.swift, ios/Sources/PromptRouter/{PromptRouter,PromptStrings}.swift
  ios/Tests/PromptRouterTests/PromptRouterTests.swift
  ios/Sketch/{TeacherPushRegistration,TeacherNotificationDelegate}.swift
  ios/README.md
scripts/teacher-prompts-local.sh
```

A owns all SQL, including scheduler SQL; B MUST NOT introduce a competing migration.
0001 owns tables/RLS helpers, 0002 calendar, 0003 work RPCs, 0004 scheduler/device RPCs
and queue hooks; install hooks referencing plan_prompts only after its definition.
Apply 0001..0004 in order, on an empty database only, never alongside old migrations.
Each file is transactional and ends with `NOTIFY pgrst, 'reload schema';` after functions.
Fresh-chain rollback is drop/recreate of the assigned throwaway DB, not historical
down scripts. Future accepted changes append 0005 onward; never amend accepted SQL.
The local shim precedes migrations and is never part of a hosted schema deployment.
It creates missing NOLOGIN roles `anon`, `authenticated`, `service_role` (BYPASSRLS),
`auth.users(id uuid PRIMARY KEY, email text, raw_user_meta_data jsonb DEFAULT '{}',
created_at timestamptz DEFAULT now())`, and schema usage grants. `auth.jwt()` returns
`coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb`;
`auth.uid()` casts its nonempty `sub` to uuid, or returns NULL when absent.
It must refuse to replace an existing incompatible `auth.users`; no hosted stubs.
Migrations require only Postgres 17 + pgcrypto, not pgTAP, pg_cron, pg_net, or btree_gist.

## 3. Shared conventions and relational model

All application tables/functions use schema `public`, without a `v2_` prefix.
UUID PKs default to `gen_random_uuid()` unless specified; timestamps are timestamptz.
`created_at` defaults to server `now()`; changed rows use server `clock_timestamp()`.
All fields below are NOT NULL unless `?`; FKs default RESTRICT, explicitly noted
CASCADE applies only to dependent records. No deletion of historical lessons in UI.
Strings are trimmed; nonempty labels/names ≤80 characters; free text limits below.
Enums are TEXT + CHECK, not PostgreSQL enum types. All FK lookup columns need indexes
unless already the leading columns of a PK/unique index. All tables have RLS enabled.
Dates are Singapore civil dates. Never depend on a connection's default timezone.
Wire timestamps are ISO-8601 instants, UUIDs lowercase strings; bigint revisions
are decimal strings in JSON to avoid JavaScript precision loss. Dates are YYYY-MM-DD.

Core tables:
| Table | Columns and constraints beyond conventions |
|---|---|
| `profiles` | `id uuid PK REFERENCES auth.users(id)`, `display_name text`, `role text CHECK IN ('admin','teacher','parent')`, `active boolean DEFAULT true`, `created_at`. No phone, student identity, or auth token. |
| `students` | `id`, `display_name text`, `active boolean DEFAULT true`, `created_at`. Only invented names in prototype; no DOB/contact/school/photos. |
| `classes` | `id`, `short_label text UNIQUE`, `subject text`, `is_study_space boolean DEFAULT false`, `active boolean DEFAULT true`, `created_at`. |
| `terms` | `id`, `label text`, `starts_on date`, `ends_on date`, CHECK end≥start. Ranges inclusive. |
| `calendar_exceptions` | `id`, `class_id uuid? FK classes` (NULL = centre-wide), `starts_on date`, `ends_on date`, `kind text IN ('holiday','closure')`, `reason_code text IN ('public_holiday','centre_closed')`, CHECK end≥start. Index `(starts_on,ends_on)`. No arbitrary PII reason. |
| `timetable_rules` | `id`, `class_id FK classes`, `term_id FK terms`, `iso_weekday smallint CHECK 1..7`, `local_start time`, `duration_minutes int CHECK 15..240`, `effective_from date`, `effective_until date`, `default_teacher_id uuid FK profiles`, `active boolean DEFAULT true`, `revision bigint DEFAULT 1`. CHECK end≥start; rule dates within term (trigger). Multiple rules per class allowed. |
| `enrollments` | `id`, `student_id FK students`, `class_id FK classes`, `starts_on date`, `ends_on date?`, CHECK end≥start. UNIQUE(student_id,class_id,starts_on); trigger rejects overlapping inclusive ranges for same pair under pair advisory lock. Index `(class_id,starts_on,ends_on)`. |
| `feature_flags` | `key text PK CHECK key IN ('teacher_prompts','teacher_prompt_push')`, `enabled boolean DEFAULT false`, `updated_at`. Both inserted OFF by 0001. |
| `runtime_settings` | `id boolean PK DEFAULT true CHECK(id)`, `demo_enabled boolean DEFAULT false`. Seed may enable only on assigned local DB. No user RPC can enable it. |

No duplicate people table: profiles are authenticated staff/parents, students are
separate children without accounts. `parent` is reserved, with no prototype access.
Never derive role from JWT metadata; `sub` identifies an active profile whose DB role
is authoritative. Creating an Auth account does not automatically grant staff access.

Lesson and work tables:
| Table | Columns and constraints |
|---|---|
| `lessons` | `id`, `class_id FK classes`, `timetable_rule_id uuid? FK timetable_rules`, `occurrence_date date`, `scheduled_start_at timestamptz`, `scheduled_end_at timestamptz`, `source_rule_revision bigint?`, `schedule_overridden boolean DEFAULT false`, `staffing_overridden boolean DEFAULT false`, `accountable_teacher_id uuid FK profiles`, `started_at timestamptz?`, `ended_at timestamptz?`, `cancelled_at timestamptz?`, `cancellation_reason text? IN ('public_holiday','centre_closed','manual','rule_removed')`, `snoozed_until timestamptz?`, `snooze_count int DEFAULT 0 CHECK 0..3`, `register_revision bigint DEFAULT 0 CHECK >=0`, `plan_revision bigint DEFAULT 1 CHECK >=1`, `overdue_at timestamptz`, `created_at`, `updated_at`. CHECK end>start and duration≤4h; ended requires started and end≥start; cancellation timestamp/reason both NULL or both non-NULL. UNIQUE(timetable_rule_id,occurrence_date) for generated rows. |
| `lesson_staff` | `lesson_id FK lessons ON DELETE CASCADE`, `teacher_id FK profiles`, `assignment_kind text IN ('regular','assistant','substitute')`, PK(lesson_id,teacher_id). Accountable role is ONLY the lesson FK, never a second boolean. |
| `lesson_roster` | `lesson_id FK lessons ON DELETE CASCADE`, `student_id FK students`, `enrollment_id uuid? FK enrollments`, `created_at`, PK(lesson_id,student_id). Materialized membership, not duplicated names. |
| `attendance_records` | `lesson_id`, `student_id`, composite FK to lesson_roster ON DELETE CASCADE, PK(lesson_id,student_id), `status text IN ('present','late','absent')`, `absence_informed boolean?`, `marked_by uuid FK profiles`, `marked_at timestamptz`, `mutation_id uuid`. CHECK absence_informed IS NULL unless absent. No fourth status; no row means Not Here Yet. |
| `lesson_feedback` | `lesson_id uuid PK FK lessons`, `body text CHECK length≤1000`, `updated_by uuid FK profiles`, `updated_at`, `revision bigint DEFAULT 1`. Empty string permitted; feedback optional and never parent-visible. |
| `lesson_submissions` | `id`, `lesson_id FK lessons`, `register_revision bigint`, `feedback_revision bigint`, `submitted_by uuid FK profiles`, `submitted_at timestamptz`, `mutation_id uuid`, UNIQUE(lesson_id), UNIQUE(submitted_by,mutation_id). No implicit submission on end/push/open. |
| `mutation_receipts` | `actor_id uuid FK profiles`, `mutation_id uuid`, `operation text`, `lesson_id uuid FK lessons`, `request_hash text`, `result jsonb`, `created_at`, PK(actor_id,mutation_id). Store hash and bounded result, never request bodies/names/feedback. |
| `audit_events` | `id`, `actor_id uuid? FK profiles`, `lesson_id uuid? FK lessons`, `event_code text`, `occurred_at timestamptz`, `details jsonb DEFAULT '{}'`. Allowlisted details: revision, counts, reason_code, prompt kind; no full-row snapshots, text, names, tokens, IPs. Index(lesson_id,occurred_at), index(occurred_at). |

Indexes: lessons(accountable_teacher_id,scheduled_start_at), lessons(scheduled_start_at),
lessons(overdue_at) WHERE cancelled_at IS NULL; lesson_staff(teacher_id,lesson_id);
lesson_roster(student_id,lesson_id); attendance_records(marked_by); receipts(created_at).
A deferred constraint trigger checks every lesson has exactly one accountable,
active `teacher` and a corresponding lesson_staff row at transaction commit.
The non-NULL FK prevents zero leads; one column prevents two leads. Both staffing
mutations and profile deactivation/role changes must preserve this invariant.
Reassign outstanding lessons before deactivating a teacher; historical leads may
remain inactive only for submitted/cancelled lessons. Check this exception explicitly.

Prompt tables (all device material is service-only, including for administrators):
| Table | Columns and constraints |
|---|---|
| `prompt_policy` | `id boolean PK CHECK(id)`, `heads_up_minutes int DEFAULT -5`, `attendance_minutes int DEFAULT 0`, `follow_up_minutes int DEFAULT 15`, `final_minutes int DEFAULT 60`, `quiet_start time DEFAULT '22:00'`, `quiet_end time DEFAULT '07:00'`, `quiet_resume time DEFAULT '09:00'`, `overdue_grace_minutes int DEFAULT 15`, `max_snoozes int DEFAULT 3`, `updated_at`. Validate ordered offsets, heads-up≥-30, final≤180, grace 1..60; quiet_start>quiet_end, quiet_resume≥quiet_end and <quiet_start; max_snoozes 0..3. |
| `teacher_devices` | `id`, `user_id FK profiles`, `installation_id uuid`, `token text`, `environment text IN ('sandbox','production')`, `last_seen_at timestamptz`, `revoked_at timestamptz?`, `created_at`. Token lowercase hex, even length 32..512; UNIQUE(environment,token), UNIQUE(user_id,installation_id,environment). Index(user_id,last_seen_at DESC) WHERE revoked_at IS NULL. |
| `notification_plans` | `id`, `lesson_id FK lessons`, `kind text IN ('heads_up','attendance','follow_up','final','simulation')`, `revision bigint`, `recipient_id uuid FK profiles`, `due_at timestamptz`, `status text IN ('pending','completed','cancelled')`, `cancel_reason text?`, `created_at`, `updated_at`, UNIQUE(lesson_id,kind). Index(due_at) WHERE status='pending'. |
| `notification_outbox` | `id`, `plan_id FK notification_plans`, `plan_revision bigint`, `device_id uuid? FK teacher_devices`, `recipient_id uuid FK profiles`, `status text IN ('pending','claimed','sent','failed','cancelled')`, `available_at timestamptz`, `attempt_count int DEFAULT 0 CHECK 0..3`, `lease_token uuid?`, `lease_until timestamptz?`, `accepted_at timestamptz?`, `last_error_code text?`, `created_at`, `updated_at`. UNIQUE NULLS NOT DISTINCT(plan_id,plan_revision,device_id). Index(available_at,id) WHERE status IN ('pending','claimed'). Claimed requires lease fields. |
| `notification_deliveries` | `id`, `outbox_id FK notification_outbox`, `attempt_no int CHECK 1..3`, `lease_token uuid`, `transport text IN ('apns','dry_run','none')`, `outcome text IN ('accepted','retry','permanent_failure','no_devices','suppressed','unknown')`, `error_code text?`, `provider_id uuid?`, `attempted_at timestamptz`, UNIQUE(outbox_id,attempt_no). Index(attempted_at). No payload/token logging. |

## 4. Calendar, roster, and lesson state

`generate_lessons(p_from date,p_until date) RETURNS jsonb` is service/admin-only;
inclusive bounded range ≤92 days, result `{created,updated,cancelled,unchanged}` integers.
Generate 42 days ahead initially and daily; never depend on an app opening a class.
Each active weekly rule produces matching ISO weekdays within term/effective range.
Start = `(occurrence_date + local_start) AT TIME ZONE 'Asia/Singapore'`; end adds duration.
Natural identity `(rule_id,occurrence_date)` survives rescheduling. No unique class/day:
two rules can create two different lessons on the same day. Reject overlapping times
for the same class among noncancelled lessons, under a class advisory lock.

Insert roster from active students/enrollments covering occurrence_date inclusively;
insert default teacher as accountable + regular staff, then plan prompts. Holiday or
closure creates a cancelled occurrence for explanation, with no prompts. Centre-wide
and class exceptions both apply; public_holiday wins over centre_closed on collision.
Regeneration locks lesson rows; only future, not-started, unsubmitted lessons may be
updated. Schedule overrides preserve times; staffing overrides preserve assignments.
Never erase attendance/feedback/cancellation or replace lesson UUIDs. Refresh roster
only before scheduled start with no work; any roster change increments register_revision.
Removed rule/date or new closure cancels untouched future occurrences; never deletes.
Manual cancellations remain cancelled; removing a closure does not resurrect a row.
Historical/worked conflicts are returned unchanged and audited for admin review.

Admin `edit_lesson` handles rescheduling in place (same UUID, original occurrence_date),
sets schedule_overridden, checks class conflicts, and replans atomically. It is allowed
only before scheduled start and without attendance, feedback, or submission. Enrollment
membership for an explicit reschedule uses the NEW Singapore start date; refresh roster
and increment revision. Generator never overwrites it. Replacement lessons after work
has begun require a later reviewed workflow, not deletion or silent history rewriting.
Admin cancellation is allowed before submission, retains existing work, revokes prompts,
and locks further edits. No uncancel/reopen operation in this prototype.

`lesson_state(p_lesson_id uuid,p_now timestamptz) RETURNS text` is a read helper with
the same access checks as lesson reads. State is DERIVED in the following priority:
1. `cancelled_at IS NOT NULL` → `cancelled`.
2. submission exists → `submitted`.
3. `p_now >= overdue_at` → `overdue`.
4. `p_now >= scheduled_end_at` OR ended_at exists → `awaiting_attendance`.
5. `p_now >= scheduled_start_at` OR started_at exists → `in_progress`.
6. otherwise → `scheduled`.
No mutable status column, no automatic absent marks, no inferred child departure.
Scheduled → in_progress → awaiting_attendance → submitted OR overdue → submitted;
scheduled/in_progress/awaiting_attendance/overdue may become cancelled by admin.
Snooze postpones prompts/deadline, not scheduled end or derived awaiting_attendance.
Submission is permitted from scheduled_start_at onward, including before E if finished.
`ended_at` is optional actual closure evidence and never blocks post-lesson review.
Prototype does not expose start/end controls; scheduler works even when both are NULL.

All lesson writes serialize on `lessons ... FOR UPDATE`, including roster, staffing,
attendance, feedback, submission, cancellation, and prompt plan changes. Lock order:
lesson → plan → outbox → device; sort lesson UUIDs for multi-lesson operations.
After submission, attendance/feedback/roster are immutable even for admin. Corrections
need a future explicit audited reopen/review workflow; don't fake a current submission
after changes. Teachers can complete overdue work up to 7 Singapore dates after start;
admin can complete older work. No attendance before scheduled start or on cancellations.

## 5. Prompt timing and queue protocol

E means scheduled_end_at, not ended_at or the last attendance write. Defaults:
| Kind | Raw due | Meaning |
|---|---|---|
| heads_up | E−5 minutes | Wrap up soon |
| attendance | E | Take attendance |
| follow_up | E+15 minutes | Still outstanding |
| final | E+60 minutes | Last automatic reminder |
| overdue | effective final due +15 minutes | Derived state/admin visibility, no extra push |

`defer_quiet(p_at timestamptz) RETURNS timestamptz`: convert to Singapore local time.
Quiet interval is [22:00,24:00) ∪ [00:00,07:00); defer to 09:00 on the next local date
for ≥22:00, or 09:00 on that date for <07:00. 07:00 and 21:59 are allowed; 22:00 isn't.
No prompt is dropped because of quiet hours. For stages ordered above, calculate
`due[0]=defer_quiet(raw[0])`, then `due[i]=defer_quiet(max(raw[i],due[i−1]+5min))`.
This keeps four deferred stages spaced at least five minutes apart. Example E=21:00:
20:55,21:00,21:15,next-day 09:00; overdue next-day 09:15. E=20:00 final is 21:00.

`plan_prompts(p_lesson_id uuid) RETURNS jsonb` service/admin-only, `{planned:int}`.
Under lesson lock, upsert the four logical stages, unique lesson/kind. No devices yet.
Skip Study Space, cancelled/submitted lessons, inactive classes, or inactive recipient.
Feature OFF prevents dispatch; planning may still populate rows for later inspection.
Unchanged plan revision is a strict no-op: preserve due times, pacing and queue state.
Recompute unsent stages when times, staffing, policy, or snooze changes. Increment
lesson.plan_revision on those changes; cancel old pending/claimed outbox rows, replace
pending plan revision/recipient/due times. Completed stages never re-open/resend.
For partially accepted stages, do not rematerialize a device already accepted for that
logical plan and recipient in ANY revision; new recipient/device may receive it.
Policy edits replan all eligible unsubmitted lessons in the same admin operation.
Overdue_at is effective final due + grace, independent of worker success/no devices.

`snooze_prompt` is only accountable teacher/admin, minutes MUST equal 10; max three
accepted requests per lesson. Requires unsubmitted/noncancelled lesson and now≥E−5.
At least one pending stage must exist; otherwise return `TP_NO_PENDING_PROMPT`.
Set snoozed_until=max(now,current snoozed_until)+10min, capped at E+60min; if the cap
would not advance time, reject `TP_SNOOZE_LIMIT`. Defer pending stages to at least
snoozed_until, preserve order/gaps/quiet hours, replan, update overdue_at. Do not create
a fifth normal reminder, change actual times, mark attendance, or submit the lesson.
Repeated mutation ID is a replay, not another ten-minute extension. UI calls this
“Remind me in 10”; “Still teaching” may explain the same action, not a second RPC.

Substitute change replaces accountable FK, removes old lead's staff row unless admin
explicitly retains it as assistant, inserts substitute row, and replans atomically.
Previous lead loses prompt-route/write access immediately; already delivered pushes
cannot be recalled. New lead gets only pending stages; today's list exposes all work.
Cancellation/submission atomically cancels pending plans and pending/claimed outbox,
clears leases. Completion on one device stops new delivery attempts on every device.

Worker SQL (DEFINER, service_role EXECUTE only; no authenticated/anon/PUBLIC):
```text
scheduler_tick(p_now timestamptz, p_limit int DEFAULT 50) -> SETOF claim rows
prepare_prompt_delivery(p_outbox_id uuid,p_lease_token uuid,p_now timestamptz) -> jsonb|null
mark_prompt_sent(p_outbox_id uuid,p_lease_token uuid,p_provider_id uuid,
                 p_transport text,p_now timestamptz) -> boolean
mark_prompt_failed(p_outbox_id uuid,p_lease_token uuid,p_error_code text,
                   p_retryable boolean,p_invalidate_device boolean,p_now timestamptz) -> boolean
```
`p_now` is REQUIRED for deterministic worker tests; only trusted callers can supply it.
Production adapters would pass server time, never a request-body/client clock.
Claim row: `{outbox_id,plan_id,lesson_id,kind,recipient_id,device_id,plan_revision,
lease_token,lease_until,attempt_no}`; UUIDs/timestamps as strings, device nullable,
plan_revision decimal string, attempt_no integer. No names, roster, or device token.

Each tick: check teacher_prompts; revalidate pending plans; materialize due plan rows
for recipient's newest five nonrevoked devices seen within 90 days; snapshot those
device IDs once for that plan revision. UNIQUE prevents tick/retry duplication.
With zero devices insert one NULL-device terminal failed row and `no_devices` log,
transport none, attempt_no=1; complete plan. Do not retry each tick or fake acceptance.
Next reminder can use newly registered devices. Limit 1..100; process deterministic
due/id order, lock eligible lesson rows with SKIP LOCKED before plan/outbox rows.
Claim available outbox rows with FOR UPDATE SKIP LOCKED, lease 120 seconds, fresh
lease_token, increment attempt_count. Commit claim before network I/O; no network
while holding a database transaction. Expired leases are retryable unknown outcomes.

For a delayed worker, do not emit a burst of all missed stages: at most one stage per
lesson per tick; defer later pending stages to at least p_now+5min successively through
quiet hours. Never move overdue_at later due solely to worker delay, retries, or no
devices. On every claim/retry/prepare, apply quiet hours again to actual send time;
if quiet, release current lease to pending at deferred time, decrement its unused
attempt_count and clear lease fields; no delivery log is written for an unused attempt.
This also covers a tick starting just before 22:00 and preparation after 22:00.

Prepare locks lesson/plan/outbox, verifies current lease + unexpired time + recipient
still accountable + matching revision/device ownership + flags + not done/cancelled.
It returns NULL and cancels/suppresses stale work; otherwise returns delivery input
below with token only to service. No new claim may begin after submission commits.
There is an unavoidable race between final DB check and APNs acceptance: a request
already in flight may arrive after submission/substitution. Document this limitation.
Mark functions match lease_token, not merely row ID; stale completions return false.
An accepted row is sent, logs accepted, never retried. Complete plan when all its
current-revision outbox rows are terminal. Cancelled plans never become completed.

Retries: network/timeout/429/5xx retry at p_now+1min after attempt 1, +5min after 2,
then terminal failed after 3; defer retry through quiet hours. Expired attempts get
an `unknown` log before re-claim; timeout-after-acceptance may duplicate delivery.
Permanent 4xx fail without retry; 410/BadDeviceToken revoke only the device involved.
Token refresh between claim and response must not revoke a newer registration:
prepare captures token version via last_seen_at; invalidation compares that version.
For this comparison, store `device_seen_at timestamptz?` on outbox at prepare time.
No response text, token, or provider error body in logs; normalize error_code.
Use stable `outbox_id` as APNs request ID across retry. Collapse IDs reduce duplicates;
APNs is best effort, not an exactly-once or read-receipt system.

Cron: 0004 includes a guarded DO block inspecting pg_extension for pg_cron. Only if
installed, create idempotent job `teacher-prompts-plan`, every minute, invoking
`refresh_prompt_schedule()` (service-only, plans/generates; DOES NOT claim/discard
deliveries). If absent, do nothing. Local runner explicitly invokes worker tick.
`refresh_prompt_schedule() RETURNS void` generates Singapore today..today+42 and plans
eligible lessons; recent overdue rows persist. Worker invocation uses its own timer
locally. Future hosted pg_net/Edge wakeup needs separate reviewed installation,
dedicated invocation secret and flag gate; never silently make external HTTP in SQL.

## 6. Dispatcher, transport, and payload boundary

Runtime-neutral `_shared/prompt-dispatch.ts` exports these exact TypeScript names:
```ts
type Claim = { outbox_id: string; plan_id: string; lesson_id: string;
  kind: 'heads_up'|'attendance'|'follow_up'|'final'; recipient_id: string;
  device_id: string|null; plan_revision: string; lease_token: string;
  lease_until: string; attempt_no: number };
type Delivery = { outbox_id: string; lesson_id: string; kind: Claim['kind'];
  token: string; environment: 'sandbox'|'production'; collapse_id: string;
  thread_id: string; expires_at: string; mode: 'dry_run'|'apns' };
type SendResult = { accepted: true; provider_id: string; transport: 'dry_run'|'apns' }
  | { accepted: false; error_code: string; retryable: boolean; invalidate_device: boolean };
interface PromptDb {
  claim(now: string, limit: number): Promise<Claim[]>;
  prepare(claim: Claim, now: string): Promise<Delivery|null>;
  sent(claim: Claim, result: Extract<SendResult,{accepted:true}>, now: string): Promise<boolean>;
  failed(claim: Claim, result: Extract<SendResult,{accepted:false}>, now: string): Promise<boolean>;
}
interface PromptSender { send(delivery: Delivery): Promise<SendResult> }
dispatchDuePrompts(args: { db: PromptDb; sender: PromptSender;
  now: () => string; limit?: number }): Promise<{
  claimed: number; accepted: number; failed: number; suppressed: number }>;
```
Export all types; use the injected clock again before EACH prepare and completion.
Adapter methods map exactly to worker RPCs. Exceptions become sanitized retryable
transport errors; DB errors propagate as failed invocation, never successful zero work.
Core has no Deno.*, process.env, filesystem, global timers, or direct database client.
Importing it must not start a worker or network request. Batch concurrency ≤5.
DryRunSender returns accepted with provider_id=outbox_id; shared `db.sent` records
transport dry_run in notification_deliveries. No separate uncoordinated log table.

`prompt-payload.ts` exports `buildPromptPayload(lessonId,kind)` and
`lessonPath(lessonId)`; validates UUID, imports only prompt-strings.ts. Payload:
```json
{"aps":{"alert":{"title":"TAVA","body":"Please review your lesson."},
"sound":"default","category":"TAVA_TEACHER_PROMPT",
"thread-id":"teacher-lesson:<lesson_uuid>"},
"v":1,"type":"teacher_prompt","lesson_id":"<lesson_uuid>","kind":"attendance"}
```
Bodies by kind: heads_up “Your lesson ends soon.”; attendance “Please take attendance.”;
follow_up “Please review your lesson.”; final “Your lesson is waiting for review.”
No student/teacher/class names, class short labels, status counts, feedback, tokens,
or auth URLs. Generic text avoids exposing children's affiliations on lock screens.
Only lesson UUID is allowed in URL/payload identity; it conveys no authorization.
APNs collapse-id=`tp:<lesson_uuid>` (one per lesson, ≤64 bytes); thread-id as above;
apns-id=outbox_id; push-type=alert; priority=10; topic supplied by adapter configuration.
Expiration = earlier of next pending stage due and now+1h, or now+1h for final.
No badge number in push (avoids stale multi-device counts); app recomputes badge from
outstanding accountable lessons through my_lessons_today including its backlog field.

ApnsSender lives separately and uses actual HTTP/2 with token auth (ES256 .p8, kid,
iss, iat; refresh before 50 minutes); only allow Apple's sandbox/production APNs hosts
selected from device.environment. Implement with a verified HTTP/2 transport such as
`node:http2` in the Deno adapter, with injectable transport/clock for tests; do not
assume ordinary fetch provides HTTP/2. Bound request to 10 seconds. No real invocation
in any pass, no real key loading. Tests exercise extracted signing/request/response
helpers with test keys; never invoke ApnsSender.send. 403 errors do not delete tokens.

Deno `index.ts`: POST only, bounded empty JSON body (≤1KiB), constant-time check of
dedicated `x-teacher-prompt-secret`, reject Authorization header, no caller-supplied
recipient/time/token/mode. Default mode dry_run; runtime refuses apns in demo mode.
All passes run dry_run only. Future real mode requires both flags, non-demo database,
explicit server configuration, credentials, and human authorization outside this work.
Do not alter existing supabase/config.toml or notify-parent; document future setup.
Local `local.ts` uses `pg` + assigned loopback DB, rejects any other URL, imports pure
dispatcher with DryRunSender, runs once with `--once` or each 60s with `--watch`.
Accept `--now <ISO>` only with `--once` and demo_enabled; default injected clock is real.
Local worker calls refresh_prompt_schedule before each tick. All worker connections
SET LOCAL ROLE service_role; never reuse the web request pool.
B owns functions/package.json + bun.lock including pg/types; local.ts must resolve
dependencies without C's node_modules. E installs both packages with frozen lockfiles.
SQL prepare returns mode=dry_run for demo, otherwise apns (requiring both flags).
Sender MUST reject incompatible mode; Deno's default dry-run cannot silently send real
traffic when a non-demo DB returns apns. Only four normal prompt kinds are claimable.

## 7. RPC contract for UI and administration

All listed UI RPCs are SECURITY DEFINER with `SET search_path = pg_catalog, public`;
schema-qualify relations/helpers, revoke PUBLIC/anon/service_role EXECUTE, grant only
authenticated, unless explicitly service/admin above. Check active DB profile, flag
teacher_prompts, and per-lesson authority inside every call; no JWT role shortcuts.
Helper functions used by RLS are pinned DEFINER predicates, fail closed on missing
profile, and expose only boolean decisions. No invoker recursion through profile RLS.
Read helpers return no row details to unauthorized actors; missing and denied lesson
both use `TP_NOT_AVAILABLE`. Every write derives actor/time; no actor argument.

All RPCs below return ONE jsonb value, never an array wrapper from PostgREST. Success
objects described below; exceptions use SQLSTATE 42501 permission, 22023 input,
P0001 domain conflict with MESSAGE set to one stable TP_* code. UI maps codes to
strings; never display SQL/provider messages. `TP_DISABLED`, `TP_NOT_AVAILABLE`,
`TP_CONFLICT`, `TP_INCOMPLETE`, `TP_LOCKED`, `TP_TOO_EARLY`, `TP_TOO_OLD`,
`TP_SNOOZE_LIMIT`, `TP_NO_PENDING_PROMPT`, `TP_MUTATION_REUSED`, `TP_INVALID_INPUT`.

Shared `LessonSummary` JSON keys (all present, nullable explicitly):
```text
lesson_id, class_id, class_label, scheduled_start_at, scheduled_end_at,
state, accountable_teacher_id, accountable_teacher_label, is_accountable,
register_revision, roster_count:int, marked_count:int, submitted_at:string|null,
next_prompt_at:string|null, snoozed_until:string|null, overdue_at:string,
can_edit:boolean, can_submit:boolean, can_snooze:boolean
```
class_label/display names are authenticated UI fields, never URL/push/log fields.
`can_*` are hints only; RPCs recheck. Study Space excluded at source from every list,
summary, prompt, admin report, and lesson_for_prompt. Do not create attendance_summary
in this prototype; any future view with that name MUST be security_invoker and exclude it.

Exact signatures and response shapes:
```text
my_lessons_today(p_date date DEFAULT NULL)
  -> {server_now:string,date:string,lessons:LessonSummary[],
      outstanding_count:int,backlog:LessonSummary[]}
lesson_for_prompt(p_lesson_id uuid)
  -> {server_now:string,lesson:LessonSummary,
      roster:[{student_id,display_name,status:string|null,absence_informed:boolean|null,
               marked_at:string|null}],feedback:{body:string,revision:string},
      submission:{id,submitted_at,submitted_by,register_revision}|null}
mark_attendance(p_lesson_id uuid,p_student_id uuid,p_status text,
                p_absence_informed boolean,p_observed_marked_at timestamptz,
                p_expected_revision bigint,p_mutation_id uuid)
  -> {lesson_id,student_id,status:string|null,absence_informed:boolean|null,
      marked_at:string|null,register_revision:string,replayed:boolean}
mark_all_present(p_lesson_id uuid,p_expected_revision bigint,p_mutation_id uuid)
  -> {lesson_id,changed_count:int,register_revision:string,replayed:boolean}
save_feedback(p_lesson_id uuid,p_body text,p_expected_feedback_revision bigint,
              p_mutation_id uuid)
  -> {lesson_id,feedback_revision:string,replayed:boolean}
submit_lesson(p_lesson_id uuid,p_expected_revision bigint,
              p_expected_feedback_revision bigint,p_mutation_id uuid)
  -> {lesson_id,submission_id,submitted_at,register_revision:string,replayed:boolean}
snooze_prompt(p_lesson_id uuid,p_minutes int,p_mutation_id uuid)
  -> {lesson_id,snoozed_until,next_prompt_at,overdue_at,replayed:boolean}
admin_missing_submissions(p_from date,p_until date)
  -> {server_now,from:string,until:string,lessons:[LessonSummary &
      {delivery_state:string,last_attempt_at:string|null}]}
simulate_prompt_now(p_lesson_id uuid,p_mutation_id uuid)
  -> {lesson_id,outbox_id,transport:'dry_run',kind:'attendance',path:string,replayed:boolean}
register_device(p_installation_id uuid,p_token text,p_environment text)
  -> {device_id,last_seen_at,environment}
revoke_device(p_device_id uuid)
  -> {revoked:boolean}
edit_lesson(p_lesson_id uuid,p_start_at timestamptz,p_end_at timestamptz)
  -> LessonSummary
assign_lesson_teacher(p_lesson_id uuid,p_teacher_id uuid,p_keep_previous_as_assistant boolean)
  -> LessonSummary
cancel_lesson(p_lesson_id uuid)
  -> LessonSummary
```

my_lessons_today uses actual Singapore today when date NULL, supports selected dates
for demo calendar. Teachers see ONLY accountable lessons; admin sees all. Include
cancelled/submitted cards for today, sorted start/id. Backlog = unsubmitted/noncancelled
earlier Singapore dates relative to p_date (teacher last 7 days; admin last 92);
outstanding_count counts unsubmitted/noncancelled, started-by-now items in lessons +
backlog. App badge calls default date; older teacher work moves to admin follow-up.
lesson_for_prompt is accountable/admin only, including historical read-only detail;
an assistant's general RLS read does not grant access to this accountable-review route.
Absent feedback returns `{body:"",revision:"0"}`. Roster sorted display_name/student_id.
admin_missing_submissions is admin-only, date range inclusive ≤92 days based on
scheduled Singapore start date; include only end≤now, unsubmitted/noncancelled, non-Study
Space. delivery_state IN ('not_attempted','accepted','failed','no_devices','pending'):
pending current work first, else latest terminal attempt; accepted means provider
acceptance (or dry run), never delivery/read. UI explicitly labels dry-run demo state.

Attendance and feedback edits: accountable/admin only in this prototype. Always
take lesson lock, require exact expected revision, and compare observed_marked_at
using IS NOT DISTINCT FROM, including NULL for observed empty. Preserve timestamp
precision from response; new marked_at must exceed prior marked_at (at least 1µs).
p_status NULL clears the row, never writes a placeholder;
non-absent companion field must be NULL. Bump register_revision on actual row changes,
including clear; mark_all_present changes only unmarked roster rows and increments
revision once per batch, preserving explicit absent/late marks. Never infer absence.
Feedback has independent CAS revision; trim, bound to 1000, reject NRIC/FIN-like
`[STFGM][0-9]{7}[A-Z]` case-insensitively. No full feedback in audit/logs. UI stand-in
guidance: “Lesson notes only. Leave out personal details.” Detection is not a privacy guarantee.

Submission locks lesson, checks both revisions, requires every roster member marked,
allows zero-member roster only for admin, and inserts immutable submission + audit
in one transaction; feedback may be blank. Reject before scheduled start. Cancel all
prompts in the same transaction. Opening a push or saving notes never counts as done.
Mutation RPCs require UUID keys, lock `(actor,mutation_id)` before lesson, hash canonical
operation/lesson/arguments, check receipt after CURRENT authorization, and return prior
success with replayed=true on exact replay even if now submitted. Reuse with different
arguments fails TP_MUTATION_REUSED. No receipt for failed transaction; receipt result
has no names/text. Consistent lock order is mutation advisory lock → lesson → queue.
Distinct stale mutations fail CAS; they cannot overwrite newer server records.
All prototype writes are online-only. Native future queues must remain actor-bound,
clear on sign-out, and preserve revisions/observations; no offline submission/snooze.

simulate_prompt_now requires demo_enabled, teacher_prompts, and accountable/admin;
creates/advances simulation plan revision, a sent NULL-device outbox row, and accepted
dry_run delivery in one transaction. Does not change normal timing/state or require
teacher_prompt_push. Reject cancelled/submitted/Study Space. Returns path from UUID;
UI builds generic notification using shared payload module, never sends a network push.
Rate limit: one new simulation per actor/lesson/minute; exact replay exempt.
register_device requires active teacher/admin + teacher_prompts; validate token/env,
lock token and user to enforce five active devices; revoke oldest on sixth. Same owner
refreshes installation/token; foreign owner conflict is denied, even if token revoked.
No token takeover; shared-installation ownership transfer is outside prototype scope.
revoke_device is self-only, idempotent; on sign-out call best effort BEFORE auth ends,
clear local token/queued actions synchronously regardless of RPC success. Never log token.
Admin edit/assign/cancel require admin, teacher_prompts, and lesson lock; repeat cancel
returns existing summary. Cannot alter submitted lessons. No ordinary direct table DML.

## 8. RLS and grants matrix

All authenticated direct writes are denied by grants AND policy; mutations go through
self-authorizing RPCs. Table SELECT grants are limited by RLS and column grants where
needed. Parent, anon, missing profile, inactive profile: no application table access,
no task RPC authority. service_role is backend-only, not a web/browser identity.

| Tables | Admin direct read | Active teacher direct read | Writes |
|---|---|---|---|
| profiles | All | Self only; accountable label shaped by RPC | Trusted admin provisioning only |
| students | All | Only students in a lesson_roster for their current lesson_staff membership | Admin provisioning only |
| classes, terms, timetable_rules, calendar_exceptions | All | Classes/rules related to own assigned lessons; terms/exceptions only relevant to those classes | Admin provisioning/calendar service |
| lessons, lesson_staff, lesson_roster, attendance_records, lesson_feedback, lesson_submissions | All | Assigned lesson_staff membership, including accountable; student scope follows roster | Guarded RPCs; assistants read-only |
| enrollments | All | Only enrollment rows referenced by own assigned lesson_roster | Admin provisioning only |
| feature_flags | All | Both public feature values | Owner/service configuration only |
| prompt_policy | All | None (RPC exposes due times) | Owner/service; replan transaction required |
| teacher_devices, notification_plans, notification_outbox, notification_deliveries | None | None | Service/guarded RPC only; admin sees shaped delivery status |
| runtime_settings, mutation_receipts | None | None | Owner/service/guarded RPC only |
| audit_events | All, sanitized | None | Trigger/RPC/service only |

`is_admin()`, `is_teacher()`, `can_read_lesson(uuid)`, `can_review_lesson(uuid)` are
boolean helpers; review means admin or active accountable teacher, read also includes
current lesson_staff. Check DB profile activation on every call. No direct role/policy
mutation by teachers. Reassignment removes former lead's roster access unless explicitly
retained as assistant; then read-only access remains but prompt route still denies.
Internal helpers are not public callable mutation shortcuts. Audit function EXECUTE
only to owning functions/service. Teacher identity from request claims cannot choose
an admin role string; RLS tests must prove spoofed metadata is ignored.

## 9. Web prototype and auth-preserving routes

Use Next 16.4.3, React/React DOM 19.3.0, Tailwind 4, Bun 1.3.14 as checked in web/.
Read installed Next guides before coding; do not copy outdated middleware conventions.
Use `pg` server-only; do not import Supabase SDK or existing live app config. UI copy,
aria labels, errors, notification demo labels, empty states, and metadata titles live
only in `lib/strings.ts`; imported push text remains in B's single prompt-strings.ts.
No red/orange/rose/amber styles, destructive red defaults, or warning emoji that render
red/orange. Use slate/blue/teal/violet with text/icons in addition to colour. No child
names in logs/URLs. No analytics or third-party scripts. Mobile-first 44px tap targets.

Required screens: `/demo` identity selector; `/` today's lesson cards + backlog badge
and date chooser; `/t/lesson/<uuid>` register, optional notes, snooze, submit; `/admin`
date-filtered missing submissions and dry-run delivery status. Lesson cards show short
class label, times, accountable teacher, progress/state. Prototype notification preview
has “Take attendance” and “Remind me in 10”; first navigates, second explicit mutation.
Submitted/cancelled cards show read-only outcome. Missing rows visibly “Not Here Yet”.
No auto-marking on submit; show remaining count and allow explicit mark-all-present
confirmation. Keep explicit absent/informed choices; bulk action never overwrites them.
Admin schedule/substitute/cancel controls call fixed RPCs; no arbitrary SQL action UI.

Environment: `TEACHER_PROMPTS_DATABASE_URL` must match the assigned loopback URL with
user postgres, no password, no query parameters; `TEACHER_PROMPTS_DEMO=1` required.
No fallback DATABASE_URL, .env loader, or inherited Supabase config. Bind to 127.0.0.1.
Validate URL before pool creation; require matching TEACHER_PROMPTS_DB_NAME supplied
by runner from --db. Worker uses these same two environment variables.
Every domain read/write obtains one pool client, BEGIN, SET LOCAL ROLE authenticated,
then parameterized `SELECT set_config('request.jwt.claims',$1,true)` with JSON containing
only `{sub:<allowlisted demo UUID>,role:'authenticated'}`; COMMIT/ROLLBACK; release in
finally. Never interpolate role/UUID into SQL or run domain queries as postgres.
Identity bootstrap uses the fixed UUID/label manifest in §11, without a DB query;
the app also verifies demo_enabled under service_role before listening. Test pool isolation.

Server validates HttpOnly SameSite=Lax demo identity cookie against seeded UUID allowlist;
local insecure cookie allowed only over loopback HTTP, Secure for any eventual preview.
This intentionally lets the local demonstrator choose an admin; it is NOT real auth.
Server actions enforce same-origin and re-read identity per call. Clear cached roster,
notes, pending mutations, and refresh after identity switch. Never trust client role.
Queries in lib/queries, mutations in app/actions; no client DB access, no-store data,
neutral explicit errors, no swallowed failure-as-empty. Disable submit while save pending;
fetch fresh detail on conflict, keep unsaved draft in memory only and show stale warning.

Universal link: `https://<approved-host>/t/lesson/<lowercase-uuid>`; custom scheme:
`tava://teacher/lesson/<lowercase-uuid>`. No signed/bearer tokens, student IDs, or query
parameters. Production host is unresolved; local web uses http://127.0.0.1:3100.
Parse scheme/host/path exactly; reject userinfo, fragments, query, encoded separators,
extra segments, malformed UUID, external next URL, and protocol-relative redirects.
Unsigned route is a locator, never authorization. UUID opaque doesn't replace checks.

Web unsigned visitor to a valid lesson path redirects to `/demo?next=<encoded-relative-path>`.
Validate next against only `/t/lesson/<uuid>` at BOTH capture and resume; store pending
route in HttpOnly cookie with 24h TTL. After selection resolve lesson_for_prompt under
chosen identity; success consumes route, denial shows “This lesson is not available.”
with choose-account/back actions; no roster/class data on denial. Keep pending route
on network failure or wrong identity for explicit retry; never redirect to a default
dashboard before trying it. Explicit sign-out clears stored route; a new external link
while signed out creates a new pending route. No external request on a link GET.

## 10. iOS sketch (not linked into the app)

Swift Package core imports Foundation only; `swift test --package-path
docs/teacher-prompts/ios` runs on Linux/macOS. UIKit/UserNotifications sketch files live
outside package Sources, guarded for platform availability; no Xcode/project edits.
All native stand-in text in PromptStrings.swift, not scattered literals.
Pure router accepts URL/payload, stores `PendingRoute(lessonID,receivedAt,action)` with
24h TTL through an injected persistence protocol, and accepts auth/profile/flag/lock
events. States: idle, awaitingSignIn, awaitingUnlock, resolving, ready, unavailable.
Do not consume pending route until authorized resolution succeeds. Deduplicate repeated
notification response; latest distinct user-opened link replaces previous pending link.
Auth restoration/profile loading/biometric unlock must finish before resolving. Recheck
RPC authority on every open; cached role or notification recipient is not proof.
Signed-out link survives process restart/login. Sign-out/account change clears sensitive
screen and actor-bound actions. Preserve an unbound incoming navigation locator during
login; NEVER replay a snooze action from account A under account B. Require fresh tap.

Category `TAVA_TEACHER_PROMPT`; action IDs `TAKE_ATTENDANCE`, `SNOOZE_10`.
Both foreground + authenticationRequired so lock-screen actions cannot silently mutate.
Default notification tap equals TAKE_ATTENDANCE. SNOOZE_10 opens authenticated lesson,
shows confirmation, then calls snooze_prompt with fresh UUID; no offline/background
queue. If session expires, keep navigation intent but require fresh snooze confirmation.
Registration waits for active teacher/admin + flags + user opt-in, supplies installation
UUID and environment from build entitlement, and calls register_device after token
callback. Demo sketch injects fake registrar and never registers with APNs in tests.
No code path may call old parent-only register_device_token for a teacher.
Permission denied/network failure shows today's list; foreground refresh recomputes
outstanding badge. Push is a convenience; my-lessons/backlog is the source of truth.
README includes paste-ready Android/Web port handoff blocks using existing template,
and explicitly marks APNs/device/associated-domain QA unrun, requiring a later release.

## 11. Demo fixtures and repeatable local run

Seed `demo_week.sql` only on assigned local database after shim/migrations; repeatable
upserts with fixed UUIDs, no deletion of arbitrary data. Refuse if non-demo profiles or
students exist. Seed toggles runtime_settings.demo_enabled and teacher_prompts ON;
teacher_prompt_push remains OFF. Dry run ignores push flag ONLY in demo mode.
Fixed UUID namespace: `10000000-0000-4000-8000-000000000001` admin; same prefix suffix
000000000011..014 teachers; 000000000099 parent denial fixture. Student prefix 20000000,
suffix 000000000001..030; class prefix 30000000 suffix 1..4 padded to 12 digits.
Staff labels “Demo Admin”, “Demo Teacher A/B/C/D”; children “Demo Student 01”..“30”.
Teachers A/B/C regular, D substitutes for B on Thursday; remove B from that lesson.
Fake sandbox hex tokens only; never APNs-valid captured tokens. Parent has no token.

Canonical week is Friday 2027-01-01 through Thursday 2027-01-07, term Jan 1–Mar 31:
- English: Monday 19:00–21:00, teacher A, students 01..10; Jan 4 unsubmitted, overdue.
- Mathematics: Thursday 19:00–21:00, B replaced by D, students 11..20; Jan 7 overrun,
  one recorded snooze at 21:00, mixed present/late/absent/unmarked rows, optional draft.
- Reading: Friday 19:00–20:30, C, students 21..25; Jan 1 cancelled by public_holiday.
- Science: Saturday 10:00–12:00, C, students 26..30; Jan 2 fully marked/submitted,
  feedback optional; one informed absence. Seed does not claim real school schedules.
Generate following weeks too, demonstrating scheduled state. Include one assistant
on English for read-only RLS tests and one Study Space fixture ONLY in tests (not reports).
Canonical evaluation instant for SQL fixtures: 2027-01-07T13:05:00Z (21:05 SGT).
Seed state setup uses owner privileges, not fabricated client timestamps in UI RPCs.

`demo_shift_to_today() RETURNS jsonb` is owner/service-only, demo_enabled required;
installed in seed, NOT production migrations. Return `{anchor_date,shift_days}`.
On first call shift the entire generated demo calendar by Singapore(today)−2027-01-07,
including term/rule/enrollment/closure dates, occurrence dates, scheduled/actual times,
attendance/feedback/submission timestamps, snooze and deadline; use stored original
anchor metadata in seed-created `demo_seed_state(id boolean PK,anchor_date date)`
with no authenticated grants and RLS. Later calls shift by today−stored anchor,
so repeated calls on same day are no-ops; reset requires explicit fresh DB seed.
Recompute weekly ISO weekdays after shift to match shifted anchor, keeping relative
week structure; closure is now visibly a shifted demo holiday, not a real holiday claim.
Cancel old pending/claimed outbox and replan shifted lessons; preserve accepted history.
Thus Math always occurs today and previous submitted/overdue work remains inspectable.
Overrun demo timestamps remain relative to 21:00; before then snooze is a scheduled
fixture detail, not a claim that a real teacher has acted today. UI offers simulate
now independently of scheduled due time; tests use explicit canonical clock for tick.

Runner usage: `scripts/teacher-prompts-local.sh --db <assigned_db> [--reset] [--fixed-week]`.
Require explicit DB name matching `[a-z][a-z0-9_]{0,62}`, reject postgres/template0/template1;
hard-code host localhost/port 55432/user postgres; never source .env. Default preserves
existing initialized assigned DB; reset is explicit, only named throwaway DB. Missing
DB is created with given local binaries. Apply shim + migrations + seed on new/reset,
call demo_shift_to_today unless fixed-week, install from bun.lock, start dry-run worker
and web at 127.0.0.1:3100, trap exit to stop children. No cron extension installation.
Validate schema version/files before reusing DB; don't blindly rerun forward migrations.
Pass URL through process environment, don't print it or inherit other DB credentials.
`--check` runs SQL/unit tests without starting web; E documents commands for Playwright.
Web scripts: `dev` (port 3100), `build`, `start`, `lint`, `test` (bun test),
`test:e2e` (Playwright). Worker tests: `bun test supabase/v2/functions/tests` from root;
local worker: `bun supabase/v2/functions/teacher-prompt-dispatch/local.ts --watch`.
Runner dependencies documented, never auto-install global services or read secrets.

## 12. Verification contracts

SQL files start `\set ON_ERROR_STOP on`, use BEGIN/ROLLBACK and DO-block assertions
raising on mismatch, print named PASS assertions. No pgTAP; deterministic fixture UUIDs.
Run each with psql -X -v ON_ERROR_STOP=1 on ONLY assigned URL. Test true roles/claims,
not solely superuser calls. Tests must restore flags/claims; concurrency test owns its
fixtures, uses two independent transactions, bounded lock/statement timeouts.

| File | Required cases |
|---|---|
| schema_test.sql | Fresh replay; constraints/FKs/indexes; exactly one lead; missing profile fail-closed; both flags OFF before seed; RLS and function grants; no pg_cron dependency. |
| calendar_test.sql | Jan weekly dates; term/effective boundaries; closure cancellation; double generation no duplicates; two same-day nonoverlapping lessons; overlap rejected; edits/substitutes/work retained; reschedule identity/roster refresh; removed rule; no implicit resurrection. |
| rls_test.sql | Admin, lead, assistant, unrelated teacher, substitute, replaced teacher, parent, anon, inactive/missing profile; direct DML denied; staff metadata spoof denied; token/outbox hidden; enumeration neutral; Study Space excluded in every shaped query. |
| attendance_test.sql | Three statuses, absent companion, NULL clear, observed-empty race, CAS stale update/delete, exact replay, changed-argument/actor/lesson replay rejection, mark-all preserves late/absent, future/old/cancelled/submitted guards. |
| submission_test.sql | Completeness; optional feedback; independent feedback CAS; length/NRIC guard; zero roster admin rule; submission differs from ended_at; immutable after submit; replay; atomic suppression; correction cannot leave stale review. |
| scheduler_test.sql | All four defaults; E=21 final at 09:00; 06:59/07:00/21:59/22:00 + UTC date crossover; stage spacing; snooze replay/cap; substitute/edited times; cancellation; double tick; leases/reclaim/stale ack; no devices; retries; disabled flags; quiet prepare; delayed-worker pacing; overdue independent of delivery. |
| devices_test.sql | Teacher/admin registration, parent denied, token shape/env, same-owner rotation, foreign ownership refusal, cap five, revoke idempotency, 410 version guard, no token disclosure. |
| demo_test.sql | 30 fake students/four classes; canonical cancellation/submitted/overdue/substitute; shift idempotency, today exists, all dates aligned, no real holiday claim after shift, demo-only simulate and dry-run logs. |
| concurrency_test.py | Competing ticks claim disjoint rows; attendance vs submit serializes and rejects stale revision; clear vs update CAS; substitute/cancel vs prepare suppress stale claims; old lease ack cannot win. |
| functions/tests/dispatch.test.ts | Mock DB/sender, twice-run no resend, partial multi-device failure, prepare NULL suppression, time advances into quiet hours, timeout/expired lease, dry-run logging, no network imports. |
| functions/tests/payload.test.ts | Exact allowlisted keys/category/path; no names/class labels/token; malformed UUID denied; all strings centralized. |
| functions/tests/apns-sender.test.ts | Pure HTTP/2 request/signing/classification helpers: ES256 test key, environments, expiration/collapse, 200/410/400/403/429/5xx/timeouts; never invoke ApnsSender.send or contact Apple. |
| web tests/identity.test.ts + rpc.test.ts | Cookie allowlist/next validation, request isolation/rollback, server-side authorization/errors, no unsafe URL, strings/style scan. |
| e2e/teacher-flow.spec.ts | Fresh DB → switch substitute → today → generic simulation → lesson → mark roster → optional feedback → submit → completed/read-only; no further pending prompts; no missing admin row. |
| e2e/authorization.spec.ts | Unsigned lesson link survives selector/login; wrong teacher neutral; account switch clears data; admin filters; forged lesson/student ID/direct server action denied; Study Space absent. |
| e2e/reminders.spec.ts | Snooze reflects ten minutes and stays incomplete; dry-run preview only; admin replacement/cancel updates access/queue; query/save failure shown; no-device/outstanding list works. |
| PromptRouterTests.swift | Both URL forms, strict validation, cold launch, login/profile delay, biometric gate, denial/retry, expiry, duplicate tap, account switch, sign-out, snooze requires fresh confirmation. |

Playwright uses local app + assigned DB, mobile Chromium and desktop admin; external
network requests fail. Owner-only test setup gives today's Math start=max(SGT midnight,
now−2h), end=now+1min, and replans, so editing/snoozing works at any test hour. Other
write tests use server-now-relative fixtures; scheduler tests use explicit canonical p_now.
No test adds client-controlled time to UI RPCs or contacts APNs.
Per-owner final: changed paths, commands, exact pass/fail/skip counts, blockers. Mark
tests awaiting another pass as unrun, not passed. Architect only checks document scope,
interfaces, line count, whitespace; it does not claim implementation tests ran.

## 13. Documentation, cutover, and open decisions

E's README explains teacher/admin walk-through, timeline, status semantics and source
of truth; diagrams mirror this contract. strings.md lists each surface's string keys,
stand-in values, and Edmund approval column (pending); source files remain authoritative.
preview-deploy.md describes future isolated fake-data preview, never production: public
hosting is blocked until demo identity switching is protected and local-only pg access
is replaced by an explicitly approved isolated backend. No deployment in these passes.
Record unrun APNs/native/real-login QA and no production evidence prominently.

Cutover is a later human-approved operation, NOT an action authorized here:
1. Inventory old client/RPC dependencies, retention/consent/archive obligations, and
   decide which existing capabilities must be ported. V2 prototype is not yet a full
   replacement for parent portal, kiosk, station, dismissals, PDPA export/erasure/storage.
2. Complete those parity/security/privacy workflows before any real-child cutover;
   explicitly map old tutor→teacher, session→lesson, auth identities, and enrollment.
   No automatic import of old personal data or silent deletion of legally retained data.
3. Rehearse fresh DB replay, migration order, RLS, fake fixtures, schema/client compatibility,
   recovery and independent review; never install local shim or demo seed in production.
4. Provision fresh Singapore-region backend/Auth intentionally; keep flags OFF; configure
   timetable/terms/closures/accountable teachers; verify counts/security before clients.
5. Update all dependent clients/endpoints, clear old sessions/actor queues safely, require
   login/device re-registration; old binaries must fail closed, not write old schema.
6. Human pilot/phone permissions/APNs/links/receipt failures/quiet-hours QA, then deliberate
   shared flag enablement. Push failure cannot block roster access or submission.
7. Freeze old writes only at approved switchover; retain an approved encrypted archive and
   recovery window. Rollback uses retained old environment plus reconciliation plan;
   once old DB is dropped rollback is not available. Drop only after explicit final
   authorization and retention sign-off. Never dual-write attendance blindly.

Privacy gates: DPO decides staff notice/push processor terms, feedback purpose and
retention, access/correction/erasure across roster/feedback/submission/audit. Proposed
delivery-log retention 30 days and revoked-device purge 30 days are OPEN decisions,
not legal requirements or automatic prototype jobs. Do not assume old draft seven-year
attendance retention applies to notification logs. No real children until gates close.

Questions for Edmund/TAVA (defaults above remain binding until contract revision):
- Is exactly one lead/substitute the right person to confirm, and can assistants stay read-only?
- Are four prompts useful, or should heads-up/follow-up be reduced after trying the demo?
- Are 22:00–07:00 quiet hours with 09:00 deferred reminders and three snoozes acceptable?
- Who follows up overdue work, and should older-than-seven-day teacher editing be allowed?
- Is optional 1000-character lesson-only feedback useful; who reads and acts on it?
- Who maintains timetable/closures, approves reschedules, and assigns substitutes?
- What is the approved universal-link host, and will all teachers have supported iPhones?
- What existing parent/kiosk/station/privacy capabilities are mandatory at fresh-DB launch?
- What retention/archive rules, staff notices, and real-device pilot acceptance will be signed off?
- Edmund: approve final strings and the calendar/workflow before any release or destructive cutover.
