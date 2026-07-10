---
name: tava-docs-and-writing
description: Use when updating any TAVA doc of record — CLAUDE.md, HUMANS.md, CONTRIBUTING.md, README.md, PORTING_NOTES.md, migrations README, PDPA docs — or when finishing a feature (port-handoff blocks, HUMANS.md items). Which doc owns which fact, the HUMANS.md checklist convention, house style, and honesty rules for claims.
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
| `CLAUDE.md` (root) | Agent knowledge NOT derivable from code: invariants, operational rules, test procedures, build commands, port-handoff template | You learn something non-obvious the hard way, or an invariant changes |
| `HUMANS.md` | Numbered checklist of actions only a human can do (dashboard toggles, legal, devices, prod decisions). Key: ☐ todo · ☑ done · ◐ in progress | Your change creates/completes a human step. Never silently drop an item — mark ☑ with a dated verification note |
| `README.md` | What the product does, stack, layout, roadmap | Features ship or roadmap changes |
| `CONTRIBUTING.md` | Local setup for all platforms, storage buckets, ops/monitoring | Setup steps change |
| `Android/PORTING_NOTES.md` | Authoritative iOS→Android file mapping + porting conventions | New screens/services appear on either side |
| `supabase/migrations/README.md` | Migration table + down-migration convention | EVERY new migration adds a row (015/016 rows added 2026-07-09) |
| `docs/API.md` | Backend↔iOS integration contract with working Swift snippets | RPCs/queries the apps call change |
| `docs/pdpa/*` | Governance docs (notice, retention, breach plan, implementation contract) | Legal/DPO input; notice edits also need in-app re-publish (see `tava-pdpa-reference`) |
| `web/AGENTS.md` | Pinned-Next.js warning | Next.js version changes |
| `docs/superpowers/{plans,specs}/` | Dated feature plans/design specs (`YYYY-MM-DD-name.md`) | Non-trivial feature design work |
| `.claude/skills/*` | This library | See maintenance sections in each skill |

Root `AGENTS.md` is just `@CLAUDE.md` — never duplicate content into it.

## The HUMANS.md convention (load-bearing)

When work hits something requiring a human (org authority, dashboard access,
legal judgement, physical device):

1. Add a numbered `### ☐ N. Title` item under the right section (A PDPA-legal, B operational, D migrations/flags, H security…), with exact commands/SQL the human should run and how to verify.
2. ALSO list it at the end of your response to the user.
3. Completing one: flip to ☑, keep the item, add the date + how it was verified (see §8, §15 for the pattern).

## House style

- Terse, factual, tables over prose. Documents state what IS, with the incident/why in one line — not essays.
- Date-stamp volatile facts (`Verified 2026-07-02:`); convert relative dates to absolute.
- Commands are copy-pasteable and include the working directory.
- British/Singapore spelling is fine (centre, organisation) — match the file you're editing.
- Commit messages: conventional-ish prefixes are common (`fix:`, `feat(web):`, `docs:`) but human-sounding; no robotic templates, no Co-Authored-By trailers.

## Honesty rules (no oversell)

- Unshipped = labelled: "built, behind the `X` flag" / "scaffolded" / "schema only". README's feature-status wording is the pattern.
- Compliance claims: the ceiling is "technical controls in place; legal formalisation pending" while HUMANS.md §A has open items.
- Never claim a migration is "applied" without naming the environment and date (prod vs local matters more here than anywhere).
- A doc that contradicts CLAUDE.md is wrong until proven otherwise — CLAUDE.md is the agent-facing source of truth; fix the discrepancy rather than picking silently.

## The port-handoff ritual (iOS features)

After any iOS feature, before "done": emit **"📋 Android port handoff"** and
**"📋 Web port handoff"** blocks per the template in CLAUDE.md
(§Cross-platform parity workflow): feature summary, iOS files changed with
purpose, target files (mapping in PORTING_NOTES.md), new Supabase objects,
sample test. The user pastes these into fresh sessions — **never auto-spawn
the porting agent**.

## Provenance and maintenance

Current as of 2026-07-09.
- Doc inventory: `ls *.md docs docs/pdpa`
- Open human items: `grep -c '^### ☐' HUMANS.md`
- Handoff template unchanged: `grep -n 'Paste-ready prompt template' CLAUDE.md`
