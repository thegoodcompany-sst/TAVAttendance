---
name: tava-run-and-operate
description: Use when running TAVA apps, deploying the web dashboard, operating the prod Supabase project (applying SQL, checking advisors, cron jobs, logs), inviting users, or doing kiosk operational setup. Command anatomy, what lands where, and the prod-touch protocol.
---

# TAVA Run and Operate

Day-to-day operation: running each client, deploying, and touching prod
safely.

**When NOT to use this skill:** first-time machine setup (use
`tava-build-and-env`); schema reconciliation on prod (use
`tava-prod-drift-campaign`); deciding whether a change is allowed (use
`tava-change-control`).

## Running the clients

| Platform | Command | Notes |
|---|---|---|
| iOS kiosk/teacher | `open iOS/TAVAttendance.xcodeproj`, run on iPad simulator or device | Kiosk (Sign-In tab) must be signed in as an **admin** account — tutor RLS breaks the global kiosk. |
| Android | `cd Android && ./gradlew installDebug` | Needs a device/emulator; JDK 17/21 (see build skill). |
| Web (local) | `cd web && npm run dev` | http://localhost:3000 |
| Local backend | `supabase start` | Studio at http://127.0.0.1:54323 |

## Deploying the web dashboard

Use the repo's dedicated **`deploy` skill** (`.claude/skills/deploy/`) — it
covers the Vercel project link, the four required prod env vars, the deploy
command, and the Supabase redirect-URL requirement. Short form:

```bash
cd web && vercel env ls production   # verify vars first
vercel deploy --prod --yes           # aliases to https://dash.thegoodcompanysg.dev
```

**Ordering rule:** any migration the new code depends on applies to prod
FIRST (change-control non-negotiable; violating it caused a full dashboard
outage).

There is no deploy step for iOS/Android yet (no App Store/Play pipeline —
installs are direct via Xcode/gradle).

## Touching prod (Supabase project `zgikcbsxzjgbigywxbbj`)

Prerequisite: the **Supabase MCP server** must be connected and authenticated
in your session (it exposes `execute_sql`, `apply_migration`, `get_advisors`).
No MCP = no prod access; fall back to asking the human to run SQL in the
dashboard's SQL editor and paste results.

- **Read-only diagnostics**: Supabase MCP `execute_sql` — freely, this is how you verify instead of guessing.
- **Schema/data writes**: MCP `apply_migration` with the exact SQL preserved (in a repo migration or a HUMANS.md note). Never fire-and-forget SQL — unrecorded out-of-band changes are how the drift crisis started.
- After creating/replacing functions: `NOTIFY pgrst, 'reload schema';`
- After ANY schema work: check Dashboard → **Advisors** (security + performance). Accepted WARNs are listed in HUMANS.md Notes (RLS helper functions, `rate_limit_events` no-policy) — don't "fix" those.
- Dashboard-only settings (auth toggles, leaked-password protection, log drains) cannot be set via SQL/MCP → HUMANS.md item + tell the user.

## Standing operational facts

- **Retention purge**: pg_cron `pdpa-daily-purge` daily 18:20 → `purge_expired_personal_data()` (returns counts; safe manually). If missing after a restore: re-run `011_pdpa_compliance.sql` or reschedule manually.
- **Kiosk session pre-creation**: opening the kiosk creates today's session rows for every class meeting today (intentional).
- **Business hours reality**: tuition Mon (Math) + Thu (English/Reading); drop-in study space Mon–Fri afternoons. Kiosk on other days correctly shows "No Classes Today".
- **Logs**: web runtime → Vercel project logs; API/Postgres → Supabase Dashboard → Logs. Blank client screens often hide a logged PostgREST 400.

## User management (no in-repo admin UI for accounts)

Invite via web dashboard (invite server action, rate-limited) or Supabase
Dashboard → Authentication → Invite User with metadata:
`{ "full_name": "Wayne Tan", "role": "tutor" }` (roles: `admin`, `tutor`,
`parent`; `handle_new_user` creates the `profiles` row; post-016 privileged
roles can't be minted from metadata — the web action assigns via service
role). Link parents to children:

```sql
INSERT INTO parent_student_links (parent_id, student_id)
VALUES ('<parent_auth_uuid>', '<student_uuid>');
```

Keep prod public signup OFF (dashboard; HUMANS.md §31).

## Kiosk operational setup (new iPad)

1. Install the app, sign in as an **admin** account.
2. Gear → Kiosk Settings → Set PIN → Lock Kiosk Now (no PIN = permanently admin mode, fine for demos only).
3. Admin unlock does not survive app restarts (deliberate).

## Output/artifact conventions

- Attendance exports: CSV via the iOS Export tab (`web/lib/csv.ts` serves web-side export helpers).
- Result slips / student photos land in the private Storage buckets, path `<student_id>/<file>`, fetched via short-lived signed URLs.
- Anything a human must do → numbered checklist item in `HUMANS.md` + listed at the end of your response.

## Provenance and maintenance

Current as of 2026-07-09.
- Deploy skill still present: `ls .claude/skills/deploy/SKILL.md`
- Cron job: `SELECT jobname, schedule, active FROM cron.job;`
- Prod URL healthy: `curl -s -o /dev/null -w "%{http_code}\n" https://dash.thegoodcompanysg.dev/login` (expect 200)
