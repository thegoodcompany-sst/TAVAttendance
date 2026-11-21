# V2 local verification (Revision 1.1)

Run from the repository root:

```sh
supabase/v2/tests/run.sh tp_g1 UTC
supabase/v2/tests/run.sh tp_g1 America/Los_Angeles
```

The examples use G1’s assigned `tp_g1`; other passes MUST supply their own assigned
name. The runner drops and recreates only the supplied name (argument or `TP_DB`),
matching `^tp_[a-z0-9_]+$`, at most 63 characters. No default or reserved names.
All connections use localhost:55432 as postgres. It never sources configuration or credentials.
It applies the local shim, deliberately permissive global/schema function defaults,
a preexisting probe function, and the four fresh-chain migrations; tests the pre-seed
OFF flags, applies the fake seed, then runs every `*_test.sql` and the Python
concurrency test. It also runs 20 pre-connection runner guard assertions. Each SQL test rolls back. Failed commands stop immediately;
the summary counts named assertions, including concurrency assertions. The optional
second argument sets the assigned database's session-default timezone for the
entire run; tests also explicitly exercise Singapore boundaries.

Dependencies: PostgreSQL 17 client tools (`psql`, `createdb`, `dropdb`), Bash,
Python 3, and the already-running throwaway server with pgcrypto available.
No psycopg, pgTAP, pg_cron, network transport, or Supabase installation is required.
The shim and seed must never be installed in a hosted database. Historical
`supabase/migrations` files are unrelated to this fresh chain.

`concurrency_test.py tp_g1` uses separate psql processes, transaction timeouts,
and observed lock-wait barriers. It creates and removes its own fake lessons;
it does not alter the canonical seed. Run it after migrations and seed. Its
worker clock is Singapore noon yesterday; use the canonical unshifted seed.

The SQL tests cover grants/RLS, accountable staff constraints, weekly calendars,
rescheduling and roster changes, three-valued attendance, receipt replay/CAS,
feedback/submission, devices, and scheduling. Time tests exercise UTC and
America/Los_Angeles sessions as well as Singapore. Worker tests check quiet-hour
retention, obsolete-stage coalescing, token-version races, partial device acceptance,
lease expiry, retry exhaustion, and cancellation/submission suppression.

The demo seed is repeatable and preserves existing demo work. To move the fixed
January 2027 fixtures to the current Singapore date, call
`public.demo_shift_to_today()` as owner/service. This changes local demo dates,
not real holiday policy. Ordinary authenticated clients cannot call it.

No APNs request is made. Provider acceptance is not delivery or review. A request
already in flight after `prepare_prompt_delivery` can arrive after submission or
substitution; a crash after acceptance can cause a retry duplicate. Leases,
logical-stage deduplication, and the final database check limit this race but
cannot provide exactly-once external delivery.

The added regression suites cover hostile ACLs, final calendar state, inactive rule
defaults, refresh failure isolation, atomic confirmation, edit-window recovery, and
installation opt-out. Worker integration uses `TP_DB=tp_g1` and
`TEACHER_PROMPTS_RUN_INTEGRATION=1 bun --no-env-file test supabase/v2/functions/tests`.

The pg_cron-installed branch, hosted Auth/PostgREST, and web/native UI QA require
their owning passes or a later authorized test.
These local tests make no production-state or deployment claim.

Revision 1.1 G1 verification: the final sequence ran twice on `tp_g1`. Each sequence
ran `run.sh tp_g1 UTC` and `run.sh tp_g1 America/Los_Angeles`: **382 passed, 0 failed**
per invocation (345 SQL assertions, 20 runner guards, 17 concurrency assertions).
The separate concurrency command also passed **17/17** in each sequence. Dispatcher
unit + local integration passed **92/92**, with no skips, in each sequence. TypeScript,
shell syntax and owned-path whitespace checks passed. No remote database or real push
was used; hosted/native checks above remain unrun.
