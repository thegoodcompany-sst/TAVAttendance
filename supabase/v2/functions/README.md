# Teacher prompt dispatcher (Pass B)

Local fake-data prototype; nothing deployed. Follow
[CONTRACT.md](../../../docs/teacher-prompts/CONTRACT.md). All runnable entrypoints in
this pass send **dry run only**. No tests invoke `ApnsSender.send`, real HTTP/2,
Apple, a hosted Supabase API, or a remote database. No credentials or `.env` files
are needed. User-facing stand-in copy is in `_shared/prompt-strings.ts`.

## Files and boundaries

- `_shared/prompt-dispatch.ts`: runtime-neutral orchestration and contract types.
  Claims once, prepares immediately before each send, reads the injected clock
  again for every prepare/completion, and runs at most five jobs concurrently.
  SQL owns retries, leases, quiet hours, eligibility, flags, token versions, and
  submission suppression. A rejected stale completion counts as suppressed.
  Database failures fail the invocation and drain active jobs; sender exceptions
  become sanitized retryable `transport_error` receipts.
- `_shared/prompt-payload.ts`: exact allowlisted payload and lesson path. Only
  imports the strings module, so the web preview can import it safely.
- `_shared/dry-run-sender.ts`: accepts only `mode=dry_run`, returns the outbox UUID.
  The shared `db.sent` path records the receipt. No payload/token console logs.
- `_shared/apns-sender.ts`: ES256 WebCrypto signing, shared provider JWT cache
  refreshed at 45 minutes, request builder and bounded response classification.
  Only the request builder places a token in Apple's required device endpoint;
  neither tokens nor provider bodies enter logs or the push payload.
- `_shared/apns-http2.ts`: real `node:http2` transport for a later reviewed native
  deployment, injectable through the `ApnsFetch` interface. No HTTP/1 fallback,
  redirects, arbitrary hosts, or global-fetch assumption. Both transport and
  request helper have ten-second deadlines. Tests inject fake fetches instead.
- `_shared/prompt-db.ts`: exact worker RPC argument mapping, shared by the local
  `pg` adapter and the future hosted REST adapter. Local RPC transactions commit
  before transport starts and always use `SET LOCAL ROLE service_role`.
- `teacher-prompt-dispatch/index.ts`: injectable Deno POST handler, fixed-size
  constant-time secret digest comparison, no Authorization header, empty JSON
  only, actual streamed-body limit of 1 KiB. Default and only runnable mode is
  `dry_run`; incompatible SQL delivery mode fails closed.
- `teacher-prompt-dispatch/local.ts`: isolated local worker, once or every sixty
  seconds, with clean SIGINT/SIGTERM shutdown and count-only stdout. It calls
  `refresh_prompt_schedule` before each tick. Generation errors are audited in SQL;
  a failed refresh transaction reports only a fixed string, then dispatch proceeds.
  One bounded refresh attempt per minute provides retries without stopping the worker.
  No schema installation on startup.

Provider classifications: 410 → `unregistered` and invalidate; 400 BadDeviceToken
→ `bad_device_token` and invalidate; other 4xx → permanent `bad_request` or
`forbidden` (403 never invalidates); 429 → retryable `rate_limited`; 5xx → retryable
`server_error`; exceptions/timeouts → retryable `transport_error`/`timeout`.
SQL compares the prepared device's `last_seen_at` before revocation. Retry delays
and the three-attempt cap come from SQL, not an additional sender retry loop.

## Install and verification

Use **Bun test**. This package owns its dependencies and lockfile; no web package
installation is required. From this directory:

```sh
bun install --frozen-lockfile
bun run typecheck
```

If the home cache is read-only, prefix installation with
`BUN_INSTALL_CACHE_DIR=/tmp/tp-b-bun-cache`. From the repository root:

```sh
bun test supabase/v2/functions/tests
```

The standard run is offline and uses an in-memory adapter with the contract wire
shapes. Scheduler behavior in that double proves dispatcher orchestration, not
SQL correctness. Integration tests are skipped unless explicitly opted in.

Supply the supervisor-assigned database explicitly; G1 uses `tp_g1`. From the repo
root (the SQL runner recreates ONLY the named local database):

```sh
supabase/v2/tests/run.sh tp_g1 UTC
TP_DB=tp_g1 TEACHER_PROMPTS_RUN_INTEGRATION=1 bun --no-env-file test supabase/v2/functions/tests
```

Integration requires `TP_DB` matching `^tp_[a-z0-9_]+$` (at most 63 characters),
constructs only the exact passwordless localhost:55432 URL, and never falls back to
another pass's DB or a generic connection variable. It requires canonical unshifted
demo fixtures, creates a dedicated fake lesson, and restores plan/device state.
Run without another worker using that database. It covers actual receipts, retries,
submission suppression, quiet hours, stale leases, concurrent claims, version-safe
invalidation, flags, no devices, sanitized codes, coalesced recovery and opt-out.
The submission-race fixture inserts a submission as the local owner to test the
dispatch hook; A's role/attendance suites own user-facing submission authorization.

## Run locally

After shim/migrations/seed, from the repository root:

```sh
TEACHER_PROMPTS_DEMO=1 \
TEACHER_PROMPTS_DB_NAME=tp_g1 \
TEACHER_PROMPTS_DATABASE_URL=postgresql://postgres@localhost:55432/tp_g1 \
bun supabase/v2/functions/teacher-prompt-dispatch/local.ts --once --now 2027-01-07T13:05:00Z
```

Use `--watch` instead of `--once --now ...` for real-clock sixty-second ticks.
`--now` requires `--once`, explicit demo configuration, and database `demo_enabled`.
The URL must exactly match the runner-assigned name, localhost, port 55432, user
postgres, no password/query/fragment. No fallback to DATABASE_URL or PG credentials.
The local runner requires demo mode even with the real clock; it cannot send APNs.
This environment's `bun` command is a shell wrapper: a supervisor must signal the
actual Bun child or its process group, not only that wrapper's PID. The worker
itself exits with code 0 on both SIGINT and SIGTERM.

## Historical Pass B verification (before Revision 1.1)

- Fresh shim + four migrations + seed replay in `tp_b`: passed.
- Combined Bun run with integration enabled: **89 passed, 0 failed, 0 skipped**
  (76 unit tests and 13 Postgres integration tests).
- Frozen-lockfile installation, TypeScript check, and owned-file whitespace check:
  passed. The read-only home cache required the `/tmp` cache override above.
- Local `--once` at the canonical instant: one dry-run accepted; identical second
  invocation: zero claims. No real transport was used.
- Local `--watch` starts and exits with code 0 under SIGINT and SIGTERM when the
  signal reaches the Bun runtime; no worker error output.

## Future deployment and limits

No changes to the existing Supabase config or parent notifications were made.
A later hosted dry-run deployment would configure `SUPABASE_URL`, its service-role
credential, and a dedicated `TEACHER_PROMPT_INVOKE_SECRET` (32–512 characters), then
POST `{}` with `x-teacher-prompt-secret`. Configuration is read only when the Deno
entry is executed, never on import. No real configuration was loaded in this pass.
`TEACHER_PROMPT_MODE` defaults to `dry_run`; every other value returns unavailable.
The handler is tested in Bun with doubles; a Deno executable is not installed here.

Wiring `ApnsSender(config, http2Fetch)` into a live entrypoint is intentionally a
later human-authorized change. It requires a non-demo database, both shared flags,
explicit server mode, APNs credentials/topic, secure wakeup, and real-device review.
The implementation exists but no pass calls its real sending method.

Submission can stop a claimed delivery before prepare. An APNs request already in
flight after prepare can still arrive after submission/substitution. Timeout after
provider acceptance can duplicate a delivery; stable outbox APNs IDs and per-lesson
collapse IDs reduce duplicates but cannot promise exactly-once delivery or reading.
Real APNs, Deno runtime, device permissions, associated domains and lock-screen QA
remain unrun. No production-state or delivery-readiness claim is made.

Pass B documentation is kept here because the task forbids edits to root release
documents. No commits, pushes, branches, PRs, deployments, or remote DB calls.

## Revision 1.1 G1 verification

`TP_DB=tp_g1 TEACHER_PROMPTS_RUN_INTEGRATION=1 bun --no-env-file test supabase/v2/functions/tests`
passed twice: **92 passed, 0 failed, 0 skipped** each (77 unit + 15 local integration).
`bun --no-env-file run typecheck` passed. Both runs used only the assigned local
Postgres and dry-run/injected senders. Database regressions and exact replay commands
are recorded in [tests/README.md](../tests/README.md).
