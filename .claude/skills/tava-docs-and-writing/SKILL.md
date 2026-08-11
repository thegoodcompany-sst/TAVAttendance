---
name: tava-docs-and-writing
description: Use when updating any TAVA doc of record — AGENTS.md, HUMANS.md, NEXT_BUILD_CHANGES.md, CONTRIBUTING.md, README.md, PORTING_NOTES.md, migrations README, PDPA docs — or when finishing a feature (port-handoff blocks, HUMANS.md items). Which doc owns which fact, the HUMANS.md checklist convention, house style, and honesty rules for claims.
---

# TAVA Docs and Writing

One home per fact. Before writing anything down, find which doc owns it.

**When NOT to use this skill:** writing code comments (house rule: none
unless the WHY is non-obvious; deliberate shortcuts get a `ponytail:` marker
naming the ceiling and upgrade path); writing migration/schema SQL itself
(use `tava-change-control` + `tava-supabase-reference`); applying anything to
prod (use `tava-prod-drift-campaign` / `tava-run-and-operate`).

## The docs of record and what each owns

| Doc | Owns | Update when |
|---|---|---|
| `AGENTS.md` (root) | Portable change workflow, invariants, established seams, canonical verification commands | The workflow, a cross-cutting invariant, or a canonical command changes |
| `CLAUDE.md` (root) | Stub only (`@AGENTS.md`) for tools that still open that filename | Never put agent knowledge here |
| `NEXT_BUILD_CHANGES.md` | Planned work for the next app build (staff feedback, product choices, not-yet-shipped items) | Feedback is queued, a product choice is made, or a planned item ships (then move a bullet to `RELEASE_NOTES.md` Unreleased and clear/mark here) |
| `RELEASE_NOTES.md` | Completed changes between releases (`Unreleased` ledger) | Every completed product/behaviour/schema/security/ops/test/release-process change |
| `HUMANS.md` | Numbered checklist of actions only a human can do (dashboard toggles, legal, devices, prod decisions). Key: ☐ todo · ☑ done · ◐ in progress | Your change creates/completes a human step. Never silently drop an item — mark ☑ with a dated verification note |
| `README.md` | What the product does, stack, layout, roadmap | Features ship or roadmap changes |
| `CONTRIBUTING.md` | Local setup for all platforms, storage buckets, ops/monitoring | Setup steps change |
| `docs/KIOSK_ATTENDANCE.md` | Detailed kiosk/attendance status and interaction semantics | Kiosk or attendance behaviour changes |
| `Android/PORTING_NOTES.md` | Authoritative iOS→Android file mapping, conventions, and handoff template | New screens/services appear on either side |
| `supabase/migrations/README.md` | Migration table + down-migration convention | EVERY new migration adds a row |
| `docs/API.md` | Backend↔iOS integration contract with working Swift snippets | RPCs/queries the apps call change |
| `docs/pdpa/*` | Governance docs (notice, retention, breach plan, implementation contract) | Legal/DPO input; notice edits also need in-app re-publish (see `tava-pdpa-reference`) |
| `{iOS,Android,supabase,web}/AGENTS.md` | Subsystem editing seams, constraints, and local verification | A subsystem's established workflow changes |
| `docs/superpowers/{plans,specs}/` | Dated feature plans/design specs (`YYYY-MM-DD-name.md`) | Non-trivial feature design work |
| `.claude/skills/*` | This library | See maintenance sections in each skill |

Root `CLAUDE.md` is just `@AGENTS.md` — never duplicate content into it. Same
pattern as `web/CLAUDE.md` → `web/AGENTS.md`.

## The HUMANS.md convention (load-bearing)

When work hits something requiring a human (org authority, dashboard access,
legal judgement, physical device):

1. Add a numbered `### ☐ N. Title` item under the right section (A PDPA-legal, B operational, D migrations/flags, H security…), with exact commands/SQL the human should run and how to verify.
2. ALSO list it at the end of your response to the user.
3. Completing one: flip to ☑, keep the item, add the date + how it was verified (see §8, §15 for the pattern).

## House style

- Terse, factual, tables over prose. Documents state what IS, with the incident/why in one line—not essays.
- Do not copy facts merely because they may be useful. Link to the owning source.
- Avoid volatile counters such as “migrations through NNN”; derive them from the
  filesystem or query the environment.
- Date-stamp volatile facts (`Verified 2026-07-02:`); convert relative dates to absolute.
- Commands are copy-pasteable and include the working directory.
- British/Singapore spelling is fine (centre, organisation) — match the file you're editing.
- Commit messages: conventional-ish prefixes are common (`fix:`, `feat(web):`, `docs:`) but human-sounding; no robotic templates, no Co-Authored-By trailers.

## Honesty rules (no oversell)

- Unshipped = labelled: "built, behind the `X` flag" / "scaffolded" / "schema only". README's feature-status wording is the pattern.
- Compliance claims: the ceiling is "technical controls in place; legal formalisation pending" while HUMANS.md §A has open items.
- Never claim a migration is "applied" without naming the environment and date (prod vs local matters more here than anywhere).
- A doc that contradicts AGENTS.md is wrong until proven otherwise — AGENTS.md is the agent-facing source of truth; fix the discrepancy rather than picking silently.

## The port-handoff ritual (iOS features)

After any iOS feature, before "done": emit **"📋 Android port handoff"** and
**"📋 Web port handoff"** blocks per the template in `Android/PORTING_NOTES.md`:
feature summary, iOS files changed with
purpose, target files (mapping in PORTING_NOTES.md), new Supabase objects,
sample test. The user pastes these into fresh sessions — **never auto-spawn
the porting agent**.

## Provenance and maintenance

Audited 2026-08-11 after separating the portable operating contract from
domain and task-specific runbooks.
- Doc inventory: `ls *.md docs docs/pdpa`
- Open human items: `rg -c '^### ☐' HUMANS.md`
- Next-build queue: `NEXT_BUILD_CHANGES.md`
- Handoff template: `rg -n 'Paste-ready port handoff template' Android/PORTING_NOTES.md`
