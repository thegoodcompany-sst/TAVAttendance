# Teacher prompts web prototype

Local fake-data demo of the contract in `docs/teacher-prompts/CONTRACT.md`. This folder owns the Next app, its tests, and its screenshot workflow. No live app or historical migration is changed.

From this directory:

```sh
BUN_INSTALL_CACHE_DIR=/tmp/tp-c-bun-cache bun install --frozen-lockfile
bun scripts/reset.ts
bun run build
bun run start
```

Open http://127.0.0.1:3100. Choose Demo Teacher D, tap “Send me a ping now” on today's Mathematics card, and tap the notification to open the register; choose Demo Admin for the missing-submissions view and schedule/teacher/cancel controls. Copy a lesson link, sign out, and open the link to try identity selection and resumption. A wrong identity keeps the pending route for another attempt.

`reset.ts` is **test-only**: it creates/rebuilds only `tp_c` on localhost:55432 using the new shim, four migrations, and fake seed. It shifts the fixtures to today and puts Mathematics just before its end so attendance and snooze can be tried at any hour. It advances the plan revision and replans. This fixture adjustment is never part of UI RPCs. `createdb`/`psql` must be on PATH. The provided native binary directory contains the server binaries, but not `createdb`.

The schema and payload files are owned by other passes. Setup fails until the complete SQL chain and seed are available. This app imports the dispatcher's pure `buildPromptPayload` module; there is no sending transport in the web bundle.

```sh
bun run lint
bun run typecheck
bun run test
bun run test:e2e
bun run screenshots
bun run build
```

Unit tests run with Vitest, per Pass C's explicit brief. Browser tests use installed Chrome, one worker, real role-scoped RPCs, against a production build (no development error overlays), and a fresh `tp_c` fixture for each scenario. They block non-loopback browser requests. The database must be initialized before Playwright starts its web server. Do not run the browser and screenshot suites concurrently: both reset `tp_c`.

Screenshots go to `/workspace/tav-teacher-prompts/screens/`. Each is 390×844 in both light and dark: identity, today, lesson, notification, snoozed state, attendance confirmation, register, notes, submit, done, missing submissions, denied access, cancelled lesson, admin controls, empty state, and query failure. The screenshots script resets the database between themes and restores a fresh playable demo after successful capture.

Application database access is server-only through `pg`. Each request obtains its own pooled connection, begins a transaction, sets the `authenticated` role and transaction-local allowlisted subject, then commits/rolls back and releases. Writes use only fixed RPCs; the database derives authority and timestamps. No browser-supplied role, actor, or time is accepted. All copy is in `lib/strings.ts`, with push copy imported from the dispatcher's `prompt-strings.ts`.

Environment precedence is `TEACHER_PROMPTS_DATABASE_URL`, then `DATABASE_URL`, then `postgresql://postgres@localhost:55432/tp_c`. The contract's runner variables are accepted; a supplied `TEACHER_PROMPTS_DB_NAME` must match the URL. Local connections require port 55432, user postgres, no password or query parameters. `dev` and `start` verify `runtime_settings.demo_enabled` as `service_role` before listening. The application then uses only authenticated role transactions. Neither startup nor requests enable flags.

A non-loopback URL is rejected unless `TP_ALLOW_REMOTE_PREVIEW_DB=1` is explicitly supplied. This only implements the requested future-preview guard; **no remote connection or preview deployment was performed**. Demo identity switching is intentionally not authentication and must not be publicly exposed. No `.env` file is supplied or read by our scripts.

Contract differences mandated by this pass: `DATABASE_URL` support/default and the opt-in remote-preview guard replace §9's exclusive environment rule; `bun run test` runs Vitest rather than §11's `bun test`. The installed Bun runtime is 1.4.4; the manifest retains the contract's 1.3.14 package-manager declaration. No runtime downgrade was attempted. Root release documents and SQL remain outside this pass's ownership.

Submission means register review, not dismissal. All-present fills only unmarked students; late/absent records are preserved. Saving notes does not submit. Conflicts fetch current data and preserve the unsaved draft in memory. Notification previews are generic and simulated through `simulate_prompt_now`; the UI never sends APNs or web push. Snooze shows the database's next reminder time, including quiet-hour deferral. Actual login, physical devices, real push delivery, and production QA are outside this demo.

Verified locally on 2026-11-14: frozen-lockfile install, lint, typecheck, and production build passed; Vitest **37 passed / 0 failed / 0 skipped**; Playwright **13 passed / 0 failed / 0 skipped**; screenshot scenarios **2 passed / 0 failed / 0 skipped**, producing **32 PNGs**, each 390×844. The intentional query-failure scenarios log only `TP_QUERY_FAILED` or `TP_DISABLED` and verify the neutral error screen. Final captures were visually checked in both themes. No real login, device/APNs, remote database, or production checks were run. No commits or pushes were made.
