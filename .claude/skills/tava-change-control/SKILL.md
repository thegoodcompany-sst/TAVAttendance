---
name: tava-change-control
description: Use BEFORE making any change to TAVA Attendance — schema/migration changes, deploys, feature-flag flips, prod SQL, or cross-platform features. Defines what is gated, the ordering rules (migration before deploy), the non-negotiables with the incident behind each, and when to stop and hand off to a human via HUMANS.md.
---

# TAVA Change Control

How changes are classified, ordered, and gated in this repo. Every rule here
exists because breaking it already cost real time or caused a real outage.

**When NOT to use this skill:** you're only reading/diagnosing (use
`tava-debugging-playbook`), or setting up a machine (use `tava-build-and-env`).

## Jargon (defined once)

- **Prod**: the live Supabase project `zgikcbsxzjgbigywxbbj` (TAVA's real data) plus the Vercel deployment at `dash.thegoodcompanysg.dev`.
- **Migration**: a numbered SQL file in `supabase/migrations/` (`NNN_name.sql`).
- **Drift**: prod's actual schema differing from what the migration files say. This project HAS drift — see `tava-prod-drift-campaign`.
- **Flag**: a row in the `feature_flags` table gating an unshipped feature (ships OFF).
- **HUMANS.md**: the repo-root checklist of actions only a human can do (dashboard toggles, legal sign-off, device testing). If your change needs one, add a numbered item there.

## The non-negotiables (each with its incident)

| Rule | Why (the incident) |
|---|---|
| **Never edit an existing migration file. Every schema change is a NEW numbered migration** (with a paired `NNN_name.down.sql`). | Prod is behind the files and partially applied out-of-band. Editing an old file makes it impossible to know what prod actually ran. |
| **Migration applies to prod BEFORE web code referencing new columns deploys.** | 2026-06-27 outage: web deployed `queries.ts` filtering `classes.is_study_space` before migration 015 was applied → PostgREST 400 → the whole authenticated dashboard showed "This page couldn't load". |
| **Never assume a repo migration is applied to prod. Verify against the live DB.** | Migration 007 (`security_invoker` on `attendance_summary`) sat in the repo unapplied for weeks — any authed user could read every student's attendance until 2026-06-10. Migration 005 was never applied at all, which later blocked 013/014. |
| **`CREATE OR REPLACE VIEW` resets view options — re-state `WITH (security_invoker = true)` every time you touch `attendance_summary`.** | Migration 015 recreated the view without it and silently reintroduced the RLS bypass; migration 016 (SEC-16a) fixed it. |
| **Feature work ships behind a flag, OFF.** Flag flips are a separate, human-verified step (HUMANS.md §16/§26). | Study-space rows must never exist before every reporting surface excludes them. |
| **Any new report / report-card / parent-facing query MUST filter `classes.is_study_space = FALSE`.** | Study-space attendance is internal-only by product decision (see CLAUDE.md invariant). SEC-16d fixed a parent policy that missed this. |
| **Never commit credentials.** Keys live in gitignored `iOS/Config.xcconfig`, `Android/secrets.properties`, `web/.env.local`. | The anon key leaked into git history once (accepted risk, but the `.githooks/pre-commit` scanner now blocks recurrences — enable with `git config core.hooksPath .githooks`). |
| **iOS project is XcodeGen-managed — never hand-edit `TAVAttendance.xcodeproj`; edit `iOS/project.yml` and run `xcodegen generate`.** | Hand edits get silently destroyed on the next generate. |
| **Cross-platform parity: an iOS feature isn't done until you output Android + Web port handoff blocks** (template in CLAUDE.md). Do NOT auto-spawn porting agents. | Each port is a separate review cycle by design. |

## Change classification → what gates it

| Change type | Gate |
|---|---|
| Schema (new table/column/function/policy) | New numbered migration + `.down.sql`; verify locally with `supabase db reset`; prod application follows `tava-prod-drift-campaign` protocol; update `supabase/migrations/README.md` table. |
| Prod SQL of any kind | Only via Supabase MCP `apply_migration`/`execute_sql` with the exact SQL recorded (commit or HUMANS.md). After creating/altering a function: `NOTIFY pgrst, 'reload schema';` or PostgREST won't see it. |
| Web deploy | `npm run lint && npm run build` green, migration ordering satisfied, then the repo `deploy` skill (Vercel). |
| iOS change | Builds with the exact command in `tava-validation-and-qa`; manual checklist for touched flows; port handoff blocks emitted. |
| Feature-flag flip | Human step. All platforms must be ready first (a flag is global across iOS/Android/web). Record in HUMANS.md. |
| Anything needing dashboard/legal/device access | Stop. Add a numbered checklist item to HUMANS.md and list it at the end of your response. |
| Docs of record (CLAUDE.md, HUMANS.md, PORTING_NOTES) | See `tava-docs-and-writing`. |

## Ordering rule for any change touching both schema and app code

1. Write + locally verify the migration.
2. Apply to prod (or a Supabase dev branch first if risky — HUMANS.md §14 recommends this).
3. Verify in prod (the migration's own verification query — see campaign skill).
4. THEN deploy/ship app code that references the new objects.
5. THEN (separately, human-gated) flip the flag.

Never reorder 2 and 4. That exact inversion took prod down.

## Provenance and maintenance

Facts current as of 2026-07-09 (16 migrations, 4 flags, HUMANS.md items 1–34).
- Migration list: `ls supabase/migrations/`
- Open human gates: `grep '^### ☐' HUMANS.md`
- Flag keys: `grep -n "key" supabase/migrations/012_feature_flags.sql supabase/migrations/015_study_space_and_notice.sql | grep -i insert -A2` or `SELECT key, enabled FROM feature_flags;`
- Pre-commit hook active? `git config core.hooksPath` → should print `.githooks`
