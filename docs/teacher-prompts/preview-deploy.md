# Edmund's phone preview — fake data, dry-run push

For Jeremy. These are future steps, not actions performed or authorized by this
pass. Do not point any preview at TAVA's existing backend, reuse credentials,
import student data, send real pushes, or enable public demo-admin access.

**The current prototype cannot be deployed unchanged to Vercel or Cloudflare.**
The contract requires an assigned loopback-only database guard, its listener
binds to `127.0.0.1`, and its demo identity selector intentionally lets a local
reviewer choose Admin. Any in-progress `TP_ALLOW_REMOTE_PREVIEW_DB` opt-in is not
a protected preview adapter and is not authorization to connect a remote backend. A hosted preview needs a separately reviewed isolated
backend adapter and access boundary. Keep these checks; do not weaken the local
URL guard merely to make a deployment work.

## First prove the local preview

Use only the database assigned to this pass (`tp_e`); another operator must obtain
an assignment before using a different name. Required files must be integrated.

```bash
scripts/teacher-prompts-local.sh --db tp_e --reset --fixed-week --check
scripts/teacher-prompts-local.sh --db tp_e --reset
```

Open `http://127.0.0.1:3100/demo`. Verify Teacher D can review the substituted lesson,
Teacher B cannot, Admin sees outstanding work, and simulated reminders never contact
APNs. Before the seeded lesson's start, the register is intentionally not editable;
use the E2E fixture for a time-independent completion test. Save the test counts
and source revision for the preview reviewer.

A phone's `localhost` is the phone, not this computer. A phone link therefore needs
an explicit private forwarding or hosted preview setup. Neither a public tunnel nor
binding to all interfaces alone provides an access boundary. The repository runner
continues to bind loopback and provides no tunnel/deployment command.

## Gate A — implement the protected preview adapter

These are concrete implementation prerequisites for a later authorized change;
this pass does not own or implement them. Stop here until each is reviewed.

1. Add an explicit preview mode separate from the local runner. Require a
   single allowlisted throwaway backend identifier/host, TLS and a dedicated
   restricted connection identity. No fallback to generic `DATABASE_URL`, live
   Supabase config or inherited environment. Keep the local adapter's strict
   loopback validation unchanged.
2. Provision only invented fixtures in the isolated backend. For a plain Postgres
   preview, adapt the local Auth shim deliberately for the isolated environment;
   do not upload a local-only shim blindly. For a fresh throwaway Supabase project,
   use its native Auth schema and a separately reviewed fake-account provisioner;
   the local seed may assume shim-owned Auth rows and is not a hosted provisioning
   script. Apply the separate V2 schema only after reviewing that compatibility.
3. Put authenticated preview access in front of **every route, asset/API surface and
   server action**, including `/demo`, `/admin`, lesson URLs and alternate hostnames.
   Allow only Jeremy and Edmund; use a host access service or an application gate
   with server-side session verification. Do not rely on an obscure URL, robots.txt,
   or a client-side password. Verify unauthenticated requests cannot choose Admin.
4. Use Secure, HttpOnly, SameSite cookies, exact HTTPS origins and no-store pages.
   Keep route validation and DB authorization on every request. A gateway login
   grants entry to the fake demo; it does not replace lesson-level DB checks.
5. Separate owner-only fixture/bootstrap access from runtime web access. Runtime
   DB role must be able to enter `authenticated` with scoped claims, not act as a
   table owner/BYPASSRLS identity for domain queries. Any startup demo-marker check
   needs a narrowly reviewed interface. Keep worker service access separate.
6. Force `demo_enabled=true`, `teacher_prompts=true`, `teacher_prompt_push=false`.
   Force only `DryRunSender`; reject non-demo backends and real APNs mode at startup.
   Provide **no APNs key, token-signing configuration or parent sender configuration**.
   A visible simulated notification is enough for Edmund's phone review.
7. Choose whether hosted simulation is on-demand only. Vercel request runtimes must
   not be assumed to run `local.ts --watch` forever. A separately protected preview
   scheduler can be added later if automatic dry-run stages are needed. Cloudflare
   would require an explicitly tested Next/runtime/database adapter; this guide
   does not claim that the current Node/pg app can run there unchanged.
8. Add preview tests for gateway bypasses, forged identities/actions, TLS/origin
   validation, wrong database, non-demo backend, token leakage and attempted real
   push. Re-run role/RLS and mobile-browser flow tests. Record the results.

## Gate B — Vercel preview recipe after Gate A is merged

These steps intentionally stop rather than invent commands for an adapter that
does not yet exist. The maintainer must add that adapter's exact bootstrap command,
server-only setting names and deployment tests to this document before execution.
No current hosting plan, access-control availability or pricing is assumed here;
Jeremy must verify those in the selected host before proceeding.

1. Create a new, empty **preview-only** hosting project, separate from TAVA's live
   project/team configuration. Do not import live environment settings or attach a
   live domain. Use the supervisor-integrated source revision, not another pass's
   incomplete working files. No commit/push/PR is performed as part of this guide.
2. Set project root to `prototypes/teacher-prompts`, framework Next.js and the Bun
   version matching `packageManager`. Install with `bun install --frozen-lockfile`;
   build with `bun run build`. Keep the sibling
   `supabase/v2/functions/_shared/` files available because the prototype imports
   the pure push payload module; verify the host build includes those files.
   If the host cannot build with this repository layout, fix the build packaging
   in the preview change rather than copy stale payload code.
3. Attach only the Gate A throwaway backend via the approved preview adapter's
   server-only environment configuration. Enter new throwaway credentials through
   the host's protected settings, never browser/public variables, source or this
   document. Scope settings only to this preview project/environment. Do not use
   `TEACHER_PROMPTS_DATABASE_URL` to bypass the local adapter's guard.
4. Before publishing, enable the tested preview access gate for all deployment
   URLs, including generated aliases. Disable indexing/analytics and require
   HTTPS. Confirm both Jeremy and Edmund can pass the gate on their phones.
5. Provision the empty backend with the Gate A hosted bootstrap, reviewed V2
   migrations and invented fixtures. Check the demo marker and OFF real-push flag.
   Keep any dry-run worker disabled until the web smoke test passes; if needed,
   start it only through the dedicated reviewed preview scheduler.
6. Create one preview deployment using the host's **Preview** deployment path;
   do not promote it to Production or change TAVA's domain. Inspect build/runtime
   logs for errors without logging credentials, device material or child data.
7. From a signed-out browser, test the protected root, `/demo`, `/admin`, a direct
   lesson URL and direct server actions. Stop/share nothing if any bypass works.
   From an allowed phone, select the demo teacher and complete the flow below.
8. Give Edmund the protected preview `/demo` URL and its expiry through the agreed
   human channel. Do not put passwords/tokens/names in URLs. The agent does not
   send messages or publish links as part of this task.

A current copy-paste hosted deployment command is **unfinished pending Gate A**.
Running the local app on Vercel now should fail its database guard; that failure is
expected and must not be worked around by enabling production access.

## Phone review checklist

- Show the persistent fake-data/dry-run explanation and current demo identity.
- Choose Teacher D and open today's Mathematics lesson; check text and tap targets.
- Simulate a generic reminder. “Take attendance” opens its lesson. “Remind me in
  10” is an explicit authenticated mutation, stays incomplete and respects limits.
- Open a valid lesson URL signed out: after allowed preview entry and identity
  selection, return to that lesson. Wrong identity shows no roster or class data.
- Mark remaining students deliberately; bulk present preserves existing late and
  absent entries. Leave feedback blank or use a short invented lesson note.
- Submit once; reload/retry; confirm a single receipt and read-only register.
  Switch to Admin and verify the missing-submission row is gone.
- Exercise cancelled/submitted lessons, substitute change and failed/no-device
  delivery. Use the outstanding list when simulated push is unavailable.
- Recheck after account change that previous roster, notes and pending actions
  are cleared. Do not interpret this as real login/APNs/universal-link device QA.

## Close the preview

Jeremy records Edmund's wording/workflow feedback, disables the preview scheduler,
revokes access, removes preview deployment/aliases and deletes the throwaway backend
when review is complete. Delete its dedicated credentials and any fake fixture
exports per the agreed preview expiry. No old/live database is touched. Keep only
sanitized test evidence and approved design feedback in the repository.
