# Teacher prompts web prototype

Local fake-data Next app following `docs/teacher-prompts/CONTRACT.md`, with the explicitly requested G2 review fixes. No live application or SQL is owned here. All commands below use only the assigned throwaway database; no commit, push or deployment.

From this directory, with Postgres on localhost:55432 and `createdb`/`psql` on PATH:

```sh
export TP_DB=tp_g2 TEACHER_PROMPTS_DEMO=1
bun --no-env-file scripts/reset.ts
bun --no-env-file run build
bun --no-env-file run start
```

Open http://127.0.0.1:3100 and choose Demo Teacher D. Simulate a notification on today's Mathematics card. Completion is three taps from the banner: **Take attendance → All present → Confirm and submit**. The accessible sheet summarises the resulting present count and existing late/absent count. It calls `confirm_all_present_and_submit` once with both observed revisions and a fresh mutation UUID. Existing late/absent rows remain intact. Unsaved notes disable this path until saved. Individual marking and **Mark present without submitting** remain available. Ordinary Submit never silently marks missing rows.

Both attendance and cancellation sheets receive focus, keep Tab inside, cancel on Escape while idle, and return focus to the opener when it still exists. A failed/conflicting mutation stays visible inside the sheet. Submission records review, not dismissal.

Choose Demo Admin for missing submissions and schedule/teacher/cancel controls. Signed-out lesson links retain the destination through account selection; wrong accounts see a neutral denial and can retry. Reads and writes use authenticated transactions with allowlisted subject claims, fixed RPC names, and database authorization. Query errors remain explicit. Copy is centralized in `lib/strings.ts`; generic push text comes from the dispatcher's strings module. There is no sending transport in this app.

## Database and preview boundaries

`TEACHER_PROMPTS_DEMO=1` is required. Supply **TP_DB explicitly**, or a `DATABASE_URL` whose database name matches `^tp_[a-z0-9_]+$` (at most 63 characters). There is no default database. Local URLs require localhost/127.0.0.1, port 55432, user postgres, no password, query or fragment. Runner compatibility accepts `TEACHER_PROMPTS_DATABASE_URL` with TP_DB; a supplied `TEACHER_PROMPTS_DB_NAME` must also agree. Conflicting URLs/assignments fail closed. Driver fields are explicit so inherited PG* credentials/options are ignored.

The future remote-preview configuration validates only when **all three** are present: `TP_ALLOW_REMOTE_PREVIEW_DB=1`, `TEACHER_PROMPTS_DEMO=1`, and nonempty `TP_PREVIEW_ACCESS_CODE`. It requires certificate-verified TLS. This mode was tested with fake configuration and mocks only; no remote connection or deployment was made. Every page/handler/action is gated before the identity switcher. `/preview` is the code-entry exception; it issues an expiring HMAC-signed HttpOnly SameSite=Lax cookie, Secure for remote preview. Direct server actions and data reads recheck access. Setting a code locally enables the same gate for offline browser testing. Identity switching is still demo access, not real authentication.

Startup, layout rendering and each data operation verify `runtime_settings.demo_enabled` under service_role before exposing content; neither enables flags. No credential file is supplied/read by these scripts. Use `--no-env-file` for Bun. The app must remain on fake data.

## Repeatable verification

```sh
export TP_DB=tp_g2 TEACHER_PROMPTS_DEMO=1
bun --no-env-file run lint
bun --no-env-file run typecheck
bun --no-env-file run test
bun --no-env-file run test:e2e
bun --no-env-file run screenshots
```

All owner helpers require TP_DB. `scripts/reset.ts` rebuilds only that local database with the shim, every sorted v2 migration, and fake seed. It shifts dates to today and adjusts today's Mathematics fixture to end at the next five-minute boundary, starting about two hours earlier (clamped to Singapore midnight so the test fixture stays on today's list). Earlier submitted/overdue examples remain inspectable. All timestamps in UI mutations still come from the server.

**SQL-owner follow-up:** `demo_shift_to_today()` itself still preserves the canonical 19:00–21:00 schedule. The natural near-now times above are a web test/play helper only. Updating the shared runner's shift function, including the lesson-start/date behavior across midnight, requires a seed SQL change outside G2's ownership.

Vitest uses fake configuration/clients without network. Playwright runs installed Chrome against a production build, one worker, and TP_DB, with external browser requests blocked. Its local shared code is a fake test fixture, never a deployed credential. Do not run browser and screenshot suites concurrently: both reset the same assigned database. Screenshot capture removes obsolete PNGs and regenerates every light/dark view under `/workspace/tav-teacher-prompts/screens/`, then restores a playable demo.

G2 verification: lint, typecheck and production build pass; web units **82 passed / 0 failed / 0 skipped**; browser suite **20 passed / 0 failed / 0 skipped**. Screenshot scenarios **2 passed / 0 failed / 0 skipped**, regenerating **34 PNGs** after removing obsolete captures. Light/dark confirmation and preview views were visually inspected. Intentional error scenarios log `TP_QUERY_FAILED` / `TP_DISABLED` and pass. Actual login, APNs/devices, remote preview and production QA remain unrun. Root release documents are supervisor-owned.

Contract deviations explicitly requested by G2: TP_DB or validated DATABASE_URL replaces §9's exclusive environment variables; guarded future remote preview is allowed in code but never contacted here. Atomic all-present submission and installation opt-out follow the new contract revision 1.1. Vitest remains the existing `bun run test` implementation. The installed runtime is Bun 1.4.4; the manifest retains its existing package-manager declaration.
