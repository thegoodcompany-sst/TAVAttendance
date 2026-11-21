# Edmund's phone preview — Jeremy's setup guide

These are instructions for a later human-run preview, **not a deployment performed
by Pass J**. Use invented fixtures and dry-run sending only. Never use TAVA's
project, credentials, Auth accounts or student data. Do not set any APNs secrets.

The implemented access-code gate now protects the demo identity selector, lesson
routes, admin routes and server actions. `/preview` accepts a code and issues an
eight-hour HMAC-signed, HttpOnly, SameSite cookie. HTTPS-forwarded requests and
remote-database mode use Secure cookies. Static framework assets remain public;
they contain no roster. Anyone admitted can select **Demo Admin**: this is a shared
fake-data preview, not real staff login. Use a randomly generated code of at least 24 characters and rotate it to
invalidate all existing preview cookies. Keep the URL and code separate.

## What you need

- The supervisor-integrated revision, Bun matching `packageManager`, the lockfiles,
  Python 3, Postgres 17 + pgcrypto, and the existing local Postgres binaries.
- A dedicated **throwaway database**. The runnable recipe below uses the assigned
  local `tp_j` at `localhost:55432`, user `postgres`, with no password. Stop all tests
  using it first. A different operator needs their own explicit `tp_` assignment.
- A terminal that can keep the app running, an installed `cloudflared` executable
  for the Cloudflare option, and a fresh preview access code. No `.env` file.
- An agreed review expiry and a private human channel for Edmund's URL/code.

The alternative hosted option needs a **new empty Supabase or Neon project**, never
TAVA's project, plus a database named `tp_…`. The current adapter checks the actual
URL database name; a default database called `postgres` or `neondb` is rejected.
Use verified TLS and new credentials scoped to that disposable backend. Its hosted
bootstrap still requires separate review; the local seed intentionally refuses
remote execution. Creating a project alone does not make it ready to run this app.

## Option A — Cloudflare link to the code-gated local preview

This option uses the tested loopback database/app adapters. The tunnel exposes only
the app; Postgres stays local. It needs no remote database, Vercel deployment or
Cloudflare Workers adapter. The tunnel itself and physical-phone flow remain
unverified by this pass. Cloudflare documents the command and temporary URL
lifetime in [Quick Tunnels](https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/).

1. From the repository root, initialize and verify the assigned disposable DB:

   ```bash
   scripts/teacher-prompts-local.sh --db tp_j --reset --fixed-week --check
   env -i PATH="$PATH" PGPASSFILE=/dev/null PGSERVICEFILE=/dev/null \
     psql -X -w -h localhost -p 55432 -U postgres -d tp_j \
     -v ON_ERROR_STOP=1 \
     -c 'BEGIN; SET LOCAL ROLE service_role; SELECT public.demo_shift_to_today(); COMMIT;'
   ```

   Keep the live runner stopped. It clears inherited environment values, so it
   does not forward your access code. The direct start below does. The shift creates
   today's three scenarios per teacher; reset again before a later fresh review.

2. Start a dedicated shell with only the intended settings; do not inherit database,
   Supabase or APNs configuration:

   ```bash
   env -i PATH="$PATH" LANG=C.UTF-8 \
     TP_DB=tp_j TEACHER_PROMPTS_DEMO=1 NEXT_TELEMETRY_DISABLED=1 \
     bash --noprofile --norc
   ```

   In that shell, enter the new code without echoing it or putting it in history,
   then install, build and start:

   ```bash
   read -r -s -p 'New preview access code: ' TP_PREVIEW_ACCESS_CODE
   export TP_PREVIEW_ACCESS_CODE
   cd /workspace/tav-tp/prototypes/teacher-prompts
   bun --no-env-file install --frozen-lockfile
   bun --no-env-file run build
   bun --no-env-file run start
   ```

   Use the clone's actual absolute path if it differs. `start` checks the database
   demo marker before listening on `127.0.0.1:3100`. No dispatcher is needed for
   “Send me a ping now”; that action records an on-demand dry-run notification.
   Do not start APNs or a hosted cron job for this review.

3. In another terminal, confirm a fresh browser at `http://127.0.0.1:3100/demo`
   receives the code gate. Wrong codes must fail; without entry, a direct lesson,
   `/admin`, or a forged demo identity must not reveal a register. Then start the
   temporary link:

   ```bash
   cloudflared tunnel --url http://127.0.0.1:3100
   ```

   Keep both processes running. Do not add an HTTP Host rewrite: same-origin server
   actions compare the browser Origin with Host. The forwarded HTTPS protocol must
   be retained so cookies are Secure. Check these properties through the generated
   HTTPS URL before sharing it. The random URL is not the access control; the
   server-checked code is. No live data belongs in this demo even behind that gate.

4. Jeremy opens `<generated HTTPS URL>/demo` in a private phone browser, checks the
   code gate and completes the checklist below. If cookies, actions or the gate
   fail, stop the tunnel and fix the forwarding boundary; do not remove the gate.
   Share only after this succeeds. Edmund opens the same URL in Safari on his phone,
   enters the separately supplied code and selects a fake teacher. His phone does
   not use `localhost`. No app installation or push permission is required.

## Environment settings and hosted alternative

All values are server-only; none use `NEXT_PUBLIC_`.

| Variable | Local phone preview | Hosted disposable database |
|---|---|---|
| `TP_DB` | `tp_j`, explicitly assigned | Exact assigned `tp_…` database name, at most 63 characters |
| `TEACHER_PROMPTS_DEMO` | `1` | `1` |
| `TP_PREVIEW_ACCESS_CODE` | Random code of at least 24 characters, required for sharing | Random code of at least 24 characters, mandatory |
| `TP_DATABASE_URL` | Omit to derive the fixed local URL, or supply matching `postgresql://postgres@localhost:55432/tp_j` | Dedicated disposable Postgres URL ending in `/<TP_DB>?sslmode=require`, entered in protected host settings |
| `TP_ALLOW_REMOTE_PREVIEW_DB` | Unset | `1`, explicit opt-in to a separately approved fake backend |
| `TP_TRUST_PREVIEW_PROXY` | Unset unless a verified proxy overwrites `X-Forwarded-For` with one client IP | Set `1` only behind that verified proxy; otherwise all clients share the conservative unknown-IP bucket |
| `NEXT_TELEMETRY_DISABLED` | `1` | `1` |

`TP_DB` is always required, must match `^tp_[a-z0-9_]+$` (at most 63
characters), and must equal the URL database name. `TP_DATABASE_URL` is the only
URL setting read by the web adapter. Generic `DATABASE_URL` and the old
`TEACHER_PROMPTS_DATABASE_URL` / `TEACHER_PROMPTS_DB_NAME` are ignored; they cannot
supply an assignment. The existing local worker/launcher still use their separate
legacy URL settings internally, always constrained to the assigned loopback DB.

Local URLs require localhost/127.0.0.1:55432, postgres, no password or URL options.
Remote mode requires all three gates: `TP_ALLOW_REMOTE_PREVIEW_DB=1`,
`TEACHER_PROMPTS_DEMO=1`, and a code with at least 24 non-padding characters.
The only remote URL query allowed is exactly `?sslmode=require`; certificate
verification stays enabled. Fragments and other driver options are refused.
The application pool is withheld until the service-role demo-marker check succeeds,
and is closed on failure; subsequent data operations recheck the marker. The local
`start` script additionally checks it before listening. The code-entry page and
rejected guesses do no database work, including during redirect rendering.
These checks do not prove that the backend contains only fake data: Jeremy must
independently verify the disposable project's identity. No local worker/test runner
accepts remote DBs. Pass J tested remote configuration and failure handling with
fake values/mocks only; no remote connection was made.

Preview attempts are checked synchronously before code comparison or database work:
five attempts per IP and 30 attempts globally per process in a 60-second window.
Repeated exhausted windows double backoff up to 15 minutes; rejected requests do
not extend an existing cooldown. After 30 idle minutes the penalty resets. Codes
are compared using constant-time fixed-size hashes and are never logged. Wrong and
throttled guesses show the same generic error; a numeric retry hint carries no code.
Unknown/untrusted addresses share one bucket. IP keys are hashed in bounded,
ephemeral memory. Only enable proxy trust after verifying the proxy replaces, rather
than appends to or forwards, the caller's `X-Forwarded-For` header with one valid IP.

This in-process limiter survives requests, not restarts or separate replicas.
**Before any multi-instance/serverless preview**, configure and verify a shared
perimeter limit for every POST route (actions can be posted to `/preview` or another
route), with both per-IP and aggregate limits no weaker than the application limits.
Do not expose alternate aliases that bypass that perimeter. A single controlled
process can use the built-in limiter; hosted multi-instance protection remains a
human setup/verification gate.

For a later **Vercel Preview**, use the supported Next.js integration documented by
[Vercel](https://vercel.com/docs/frameworks/full-stack/nextjs). The following records
configuration steps, not successful hosted validation:

1. Provision the new empty throwaway backend and obtain review of its bootstrap.
   Apply the V2 chain alone with its required Auth/role interfaces. A plain Postgres
   host needs compatible `auth.users`, `auth.uid()`, `auth.jwt()` and roles; Supabase
   has native Auth which must not be replaced with the local shim. Provide fake Auth
   identities, minimal profiles/students/calendar, demo marker and fake device rows
   through a reviewed hosted fixture loader. The runtime login needs only the
   reviewed role memberships for `authenticated` requests and the `service_role`
   demo-marker check. Verify RLS/ACLs in the actual target, including hostile defaults.
   **There is no checked-in hosted fixture loader yet. Do not run the local seed,
   remove its host guard, or upload the local shim blindly.** Use Option A until this
   prerequisite has a reviewed, executable procedure and recorded results.
2. Verify fake-data mode and flags from the disposable target:
   `demo_enabled=true`, `teacher_prompts=true`, `teacher_prompt_push=false`.
   Arrange a reviewed equivalent of today's demo setup in that hosted loader.
   Never reuse real device tokens, student data or existing TAVA credentials.
3. Create a separate Vercel project from the integrated clone. Root directory:
   `prototypes/teacher-prompts`; framework: Next.js. Include files outside that root
   so imports from `supabase/v2/functions/_shared/` resolve. Install command:
   `bun --no-env-file install --frozen-lockfile`; build command:
   `bun --no-env-file run build`. Vercel runs the framework output, not the local
   loopback `start` script. Keep configuration scoped to this disposable preview.
4. Enter the hosted column's server settings through protected host settings. Keep
   all automatic environment files absent. Do not copy live project settings, attach
   TAVA's domain, or promote this to its production deployment. Do not supply APNs
   keys or schedule the local watch worker on a request runtime.
5. Create the Preview deployment only after the bootstrap gate passes. Verify every
   generated alias redirects unauthenticated users to `/preview`, direct actions
   cannot bypass it, cookies are Secure, and wrong identities reveal no roster.
   The verified request pool/RPC checks must verify demo mode even though Vercel bypasses `start`; the shared perimeter limit above must already be active.
   Run the phone checklist before sharing the HTTPS `/demo` link and separate code.

Cloudflare **Workers** hosting of this Node/`pg` app is not established here. Option A
is a Cloudflare Tunnel to the existing app, not a claim of Workers compatibility.

## Phone review checklist

- Choose Demo Teacher A: today has an ongoing lesson ending within five minutes,
  one earlier pending review and one submitted lesson. Near midnight timings shorten
  to fit today. Choose D for existing late/absent Mathematics marks.
- On the intended lesson, simulate a generic reminder. Count **Take attendance →
  All present → Confirm and submit** as three taps from the reminder. Confirm that
  existing late/absent marks remain and the submitted register becomes read-only.
- On another unfinished lesson, use “Remind me in 10”; it stays incomplete. Notes
  remain optional. No actual phone push arrives; this is an on-screen simulation.
- Open a valid lesson URL signed out: pass the code gate, choose the correct demo
  identity and return to that lesson. A wrong teacher sees a neutral unavailable
  state. Switching identities must clear the previous roster and unsaved actions.
- As Admin, verify submitted work disappears from missing submissions, while the
  other unfinished lesson stays. Try cancellation/substitution on eligible fixtures.
- Close/reopen the phone tab and retry a submission; verify a single receipt. Check
  large controls, keyboard focus, light/dark modes and notes without real personal
  information. Record Edmund's wording and workflow feedback separately from tests.

## Tear down

At the agreed expiry Jeremy stops `cloudflared` first; its temporary URL stops
working. Stop the app, unset `TP_PREVIEW_ACCESS_CODE`, and close the dedicated shell.
After all testing using this assigned DB has stopped, delete only the throwaway DB:

```bash
env -i PATH="$PATH" PGPASSFILE=/dev/null PGSERVICEFILE=/dev/null \
  dropdb -w -h localhost -p 55432 -U postgres --if-exists tp_j
```

For a hosted alternative, remove the preview deployment/project and every alias,
stop any separately approved preview scheduler, delete the disposable backend and
revoke its dedicated credentials. Retain only sanitized results and approved
feedback. Do not touch TAVA's existing database or any other pass's assignment.
