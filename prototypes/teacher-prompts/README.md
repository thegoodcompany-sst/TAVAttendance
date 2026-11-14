# Teacher prompts web prototype

Local fake-data Next app following `docs/teacher-prompts/CONTRACT.md`, with the supervisor-requested Pass J review fixes. The new V2 calendar correction is covered by the shared SQL suite. All commands below use only the assigned throwaway database; no commit, push or deployment.

From this directory, with Postgres on localhost:55432 and `createdb`/`psql` on PATH:

```sh
export TP_DB=tp_j TEACHER_PROMPTS_DEMO=1
bun --no-env-file scripts/reset.ts
bun --no-env-file run build
bun --no-env-file run start
```

Open http://127.0.0.1:3100 and choose Demo Teacher D. Simulate a notification on today's Mathematics card. Completion is three taps from the banner: **Take attendance → All present → Confirm and submit**. The accessible sheet summarises the resulting present count and existing late/absent count. It calls `confirm_all_present_and_submit` once with both observed revisions and a fresh mutation UUID. Existing late/absent rows remain intact. Unsaved notes disable this path until saved. Individual marking and **Mark present without submitting** remain available. Ordinary Submit never silently marks missing rows.

Both attendance and cancellation sheets receive focus, keep Tab inside, cancel on Escape while idle, and return focus to the opener when it still exists. A failed/conflicting mutation stays visible inside the sheet. Submission records review, not dismissal.

Choose Demo Admin for missing submissions and schedule/teacher/cancel controls. Signed-out lesson links retain the destination through account selection; wrong accounts see a neutral denial and can retry. Reads and writes use authenticated transactions with allowlisted subject claims, fixed RPC names, and database authorization. Query errors remain explicit. Copy is centralized in `lib/strings.ts`; generic push text comes from the dispatcher's strings module. There is no sending transport in this app.

## Database and preview boundaries

`TEACHER_PROMPTS_DEMO=1` and **TP_DB are always required**. The assignment must match `^tp_[a-z0-9_]+$` and fit 63 characters. The optional **TP_DATABASE_URL** must name that exact database; otherwise the fixed localhost:55432/postgres URL is derived from TP_DB. No generic `DATABASE_URL` or legacy web URL settings are read. Local URLs require localhost/127.0.0.1, port 55432, user postgres, no password, query or fragment. Explicit driver fields ignore inherited PG* configuration.

Remote preview requires `TP_ALLOW_REMOTE_PREVIEW_DB=1`, `TEACHER_PROMPTS_DEMO=1`, a randomly generated `TP_PREVIEW_ACCESS_CODE` of at least 24 characters, and URL query exactly `?sslmode=require`. TLS certificate verification is enabled. A configured local access code has the same minimum length. The pool is unavailable to request code until its service-role `runtime_settings.demo_enabled` check passes; failures close the pool. Startup and every data operation also check the marker. No flags are enabled by those checks.

The code gate protects routes and actions before identity selection and issues expiring HMAC-signed HttpOnly SameSite=Lax cookies, Secure for HTTPS/remote mode. Before any DB work, attempts are limited per IP (five) and globally (30) per process per minute, with increasing backoff up to 15 minutes. Fixed-size code hashes use constant-time comparison; wrong/throttled guesses share generic copy and never log the code. The code page/layout performs no DB lookup. `TP_TRUST_PREVIEW_PROXY=1` trusts a single validated `X-Forwarded-For` IP only behind a proxy verified to overwrite the header; otherwise all clients share an unknown-IP bucket. A distributed perimeter limiter is required before multiple instances/serverless hosting. See [preview-deploy.md](../../docs/teacher-prompts/preview-deploy.md) for exact settings and hosting gates.

Remote guards were exercised with fake configuration and mocks only. No remote connection/deployment occurred. Identity switching remains fake-data demo access. No credential files are supplied/read; use `--no-env-file` for Bun and keep Next environment files absent.

## Repeatable verification

```sh
export TP_DB=tp_j TEACHER_PROMPTS_DEMO=1
bun --no-env-file run lint
bun --no-env-file run typecheck
bun --no-env-file run test
bun --no-env-file run test:e2e
bun --no-env-file run screenshots
```

All owner helpers require TP_DB. `scripts/reset.ts` rebuilds only that local database with the shim, every sorted v2 migration, and fake seed. It shifts dates to today and adjusts today's Mathematics fixture to end at the next five-minute boundary, starting about two hours earlier (clamped to Singapore midnight so the test fixture stays on today's list). Earlier submitted/overdue examples remain inspectable. All timestamps in UI mutations still come from the server.

Vitest uses fake configuration/clients without network. Playwright runs installed Chrome against a production build, one worker, and TP_DB, with external browser requests blocked. Its local shared code is a fake test fixture, never a deployed credential. Do not run browser and screenshot suites concurrently: both reset the same assigned database. Screenshot capture removes obsolete PNGs and regenerates every light/dark view under `/workspace/tav-teacher-prompts/screens/`, then restores a playable demo.

Pass J verification is recorded in the [shared Verification section](../../docs/teacher-prompts/README.md#verification) and `/workspace/tav-teacher-prompts/RESULTS.md`, including both complete loops and regenerated screenshots. Actual login, APNs/devices, remote preview and production QA remain unrun. Root release documents are supervisor-owned.

Supervisor-approved deviations from CONTRACT §9: use TP_DB plus TP_DATABASE_URL, retain the gated remote preview mode, and permit a DB-free access-code page so guesses cannot perform database work. No remote use is authorized in this pass. Vitest remains the existing `bun run test` implementation.
