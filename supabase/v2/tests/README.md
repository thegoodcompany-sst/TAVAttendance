# Pass A local verification

Run from the repository root:

```sh
supabase/v2/tests/run.sh tp_a UTC
supabase/v2/tests/run.sh tp_a America/Los_Angeles
```

The runner drops and recreates **only** `tp_a` (or explicitly `tp_a_scratch`)
using localhost:55432 as postgres. It never sources configuration or credentials.
It applies the local shim and four fresh-chain migrations, tests the pre-seed
OFF flags, applies the fake seed, then runs every `*_test.sql` and the Python
concurrency test. Each SQL test rolls back. Failed commands stop immediately;
the summary counts named assertions, including concurrency assertions. The optional
second argument sets the assigned database's session-default timezone for the
entire run; tests also explicitly exercise Singapore boundaries.

Dependencies: PostgreSQL 17 client tools (`psql`, `createdb`, `dropdb`), Bash,
Python 3, and the already-running throwaway server with pgcrypto available.
No psycopg, pgTAP, pg_cron, network transport, or Supabase installation is required.
The shim and seed must never be installed in a hosted database. Historical
`supabase/migrations` files are unrelated to this fresh chain.

`concurrency_test.py tp_a` uses separate psql processes, transaction timeouts,
and observed lock-wait barriers. It creates and removes its own fake lessons;
it does not alter the canonical seed. Run it after migrations and seed. Its
worker clock predates the canonical fixtures so it never claims their plans.

The SQL tests cover grants/RLS, accountable staff constraints, weekly calendars,
rescheduling and roster changes, three-valued attendance, receipt replay/CAS,
feedback/submission, devices, and scheduling. Time tests exercise UTC and
America/Los_Angeles sessions as well as Singapore. Worker tests check quiet-hour
retention, delayed-stage pacing, token-version races, partial device acceptance,
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

The pg_cron-installed branch, hosted Auth/PostgREST, dispatcher integration,
and web/native UI QA require their owning passes or a later authorized test.
These local tests make no production-state or deployment claim.
