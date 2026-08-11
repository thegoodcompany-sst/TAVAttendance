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
- **Drift**: production's actual schema differing from the reviewed migration
  replay. Historical drift was repaired; current absence/presence is measured,
  never assumed.
- **Flag**: a row in the `feature_flags` table gating an unshipped feature (ships OFF).
- **HUMANS.md**: the repo-root checklist of actions only a human can do (dashboard toggles, legal sign-off, device testing). If your change needs one, add a numbered item there.

## The non-negotiables (each with its incident)

| Rule | Why (the incident) |
|---|---|
| **Never edit an existing migration file. Every schema change is a NEW numbered migration** (with a paired reverse script at `down/NNN_name.sql`). | Production's historical ledger is sparse. Editing an old file destroys reproducibility and evidence. |
| **Migration applies to prod BEFORE web code referencing new columns deploys.** | 2026-06-27 outage: web deployed `queries.ts` filtering `classes.is_study_space` before migration 015 was applied → PostgREST 400 → the whole authenticated dashboard showed "This page couldn't load". |
| **Never assume a repo migration is applied to prod. Verify against the live DB.** | Migration 007 (`security_invoker` on `attendance_summary`) sat in the repo unapplied for weeks — any authed user could read every student's attendance until 2026-06-10. Migration 005 was never applied at all, which later blocked 013/014. |
| **`CREATE OR REPLACE VIEW` resets view options — re-state `WITH (security_invoker = true)` every time you touch `attendance_summary`.** | Migration 015 recreated the view without it and silently reintroduced the RLS bypass; migration 016 (SEC-16a) fixed it. |
| **Feature work ships behind a flag, OFF.** Flag flips are a separate, human-verified step (HUMANS.md §16/§26). | Study-space rows must never exist before every reporting surface excludes them. |
| **Any new report / report-card / parent-facing query MUST filter `classes.is_study_space = FALSE`.** | Study-space attendance is internal-only by product decision (see AGENTS.md invariant). SEC-16d fixed a parent policy that missed this. |
| **Never commit credentials.** Keys live in gitignored `iOS/Config.xcconfig`, `Android/secrets.properties`, `web/.env.local`. | The anon key leaked into git history once (accepted risk, but the `.githooks/pre-commit` scanner now blocks recurrences — enable with `git config core.hooksPath .githooks`). |
| **iOS project is XcodeGen-managed — never hand-edit `TAVAttendance.xcodeproj`; edit `iOS/project.yml` and run `xcodegen generate`.** | Hand edits get silently destroyed on the next generate. |
| **Cross-platform parity: an iOS feature isn't done until you output Android + Web port handoff blocks** (template in `Android/PORTING_NOTES.md`). Do NOT auto-spawn porting agents. | Each port is a separate review cycle by design. |

## Change classification → what gates it

| Change type | Gate |
|---|---|
| Schema (new table/column/function/policy) | New numbered migration + reverse script in `supabase/migrations/down/` (NOT beside the forward files — the CLI would apply it as a forward migration); verify locally with `supabase db reset`; prod application follows `tava-prod-drift-campaign` protocol; update `supabase/migrations/README.md` table. |
| Prod SQL of any kind | Exact reviewed committed migration through the authorised production mechanism; no ad-hoc dashboard SQL. After function changes run `NOTIFY pgrst, 'reload schema';`, then drift/security checks. |
| Web deploy | `bun install --frozen-lockfile`, high-severity audit, tests, lint/build, remote drift/security gates, then the `deploy` runbook. |
| iOS change | Builds with the exact command in `tava-validation-and-qa`; manual checklist for touched flows; port handoff blocks emitted. |
| Feature-flag flip | Human step. All platforms must be ready first (a flag is global across iOS/Android/web). Record in HUMANS.md. |
| Anything needing dashboard/legal/device access | Stop. Add a numbered checklist item to HUMANS.md and list it at the end of your response. |
| Docs of record (AGENTS.md, NEXT_BUILD_CHANGES.md, HUMANS.md, PORTING_NOTES) | See `tava-docs-and-writing`. |

## Ordering rule for any change touching both schema and app code

1. Write + locally verify the migration.
2. Apply to prod (or a Supabase dev branch first if risky — HUMANS.md §14 recommends this).
3. Verify in prod (the migration's own verification query — see campaign skill).
4. THEN deploy/ship app code that references the new objects.
5. THEN (separately, human-gated) flip the flag.

Never reorder 2 and 4. That exact inversion took prod down.

## Provenance and maintenance

Audited 2026-08-11. Migration and flag state remain environment-specific; do
not embed a current highest migration number here.
- Migration list: `ls supabase/migrations/`
- Open human gates: `rg '^### ☐' HUMANS.md`
- Flag keys: `SELECT key, enabled FROM feature_flags ORDER BY key;`
- Pre-commit hook active? `git config core.hooksPath` → should print `.githooks`
