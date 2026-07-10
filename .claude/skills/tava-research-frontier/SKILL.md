---
name: tava-research-frontier
description: Use when asked "what should we build next", planning a new TAVA feature or roadmap phase, or looking for high-leverage improvements — the ranked open problems (Phase 2/3 roadmap, ops autonomy, product innovation), each with why it's unstarted, the asset already in the repo, the first three concrete steps, and a falsifiable done-milestone. Also carries the methodology for turning an idea into a shipped feature here.
---

# TAVA Research Frontier

Where this project can advance, ranked by leverage. Every entry names the
asset that already exists in the repo (most "new" features here are 60%
built — schema and RLS shipped early by design) and a **falsifiable
milestone**: a check that fails until the work is real.

**When NOT to use this skill:** executing a chosen feature — that routes
through `tava-change-control`. (The drift campaign closed 2026-07-09, so the
frontier below is unblocked.)

## The idea lifecycle (methodology, condensed)

1. **Check the graveyard first**: `tava-failure-archaeology` dead-ends + HUMANS.md — is this settled?
2. **Spec before code** for anything non-trivial: dated doc in `docs/superpowers/specs/` (the superadmin feature-flags spec is the worked example — spec → plan → small reviewed commits).
3. **Schema first, flag-gated, OFF**: new migration + `.down.sql`; every platform gates on the flag; ship dark.
4. **Predict the numbers before running**: write the acceptance query/checklist BEFORE building (see milestones below), then build until it passes.
5. **Ship or retire explicitly**: flag flips via HUMANS.md, or the idea gets a dead-end entry in the archaeology skill — never a silent stall. (The unwired `PdpaPanel` is the cautionary tale of skipping this step.)

## Tier 1 — Roadmap excellence (built or half-built; finish them)

### 1. Parent portal (flag `parent_portal`)
- **Asset:** iOS `ParentDashboardView` + web `/parent` built; RLS read policies shipped in `002_rls.sql`; `parent_student_links` live.
- **Why unstarted:** no parent accounts exist yet; Android screen pending; consent/notice must be live first (PDPA).
- **First three steps:** (1) port the parent screen to Android per PORTING_NOTES; (2) create one real parent account + link, verify RLS shows exactly one child; (3) run the study-space-exclusion query as that parent.
- **Milestone:** a parent account logs in on all three platforms and sees exactly their child's non-study-space attendance — and `SELECT` as that parent returns 0 rows for any other student.

### 2. Analytics dashboard (admin)
- **Asset:** `attendance_summary` view live and queryable; web already has recharts as a dependency.
- **First three steps:** (1) design one screen around attendance % per class/student; (2) `getAttendanceSummary()` in `web/lib/queries.ts` (filter `is_study_space = FALSE` — invariant); (3) trend query grouped by week.
- **Milestone:** an admin answers "which student's attendance dropped this month?" from the dashboard alone, and the numbers match a hand-run SQL check.

### 3. Dismissal & safety loop (Phase 3)
- **Asset:** `dismissals` table LIVE (kiosk marks them today); `device_tokens` + `notify-parent` edge function scaffolded.
- **Why unstarted:** push credentials (HUMANS.md §17) and prod migration 014.
- **First three steps:** (1) finish the APNs/FCM sender in `supabase/functions/notify-parent/index.ts`; (2) trigger on dismissal insert; (3) "safely home" confirmation writes back.
- **Milestone:** dismissing a test student delivers a push to a linked parent device < 30s, and the confirmation round-trip lands in the DB.

### 4. Remaining shelf, in rough order
QR/NFC sign-in (kiosk tap-to-sign already abstracts marking — add a scan
entry point); teacher session notes (`sessions.notes` column exists, needs
one RosterView field); awards (`awards` table + `attendance_summary` inputs);
food polls (tables exist); result-slip flow (table+bucket exist; blocked on
§9 storage-cleanup decision).

## Tier 2 — Ops autonomy (make the drift class of failure impossible)

### 5. Drift detector
- **Why SOTA fails here:** the migration ledger lies; humans forget out-of-band applies.
- **Asset:** the campaign skill's Phase-0 queries are already a hand-run drift detector.
- **First three steps:** (1) script that diffs `information_schema` of prod vs a `supabase db reset` local into a report; (2) run it in CI weekly / before web deploys; (3) fail the deploy when web code references a column prod lacks (grep queries.ts columns vs the report).
- **Milestone:** reintroducing the 2026-06-27 outage conditions (deploy code referencing a column prod lacks) is CAUGHT by CI before deploy.

### 6. Self-verifying migrations
- **Asset:** 016's header lists its own verification queries; the campaign formalised gates.
- **First step trio:** (1) convention — every migration ends with `DO $$ ... ASSERT ... $$` blocks; (2) retrofit 016's gate; (3) document in migrations README.
- **Milestone:** an intentionally-broken migration aborts itself on a dev branch with a named assertion instead of half-applying.

### 7. Advisor watch
- (1) MCP `get_advisors` on a schedule → diff against the accepted-WARN list in HUMANS.md Notes → surface only NEW findings. **Milestone:** seeded regression (a view without `security_invoker`) is reported within one cycle.

## Tier 3 — Product innovation (novel for a tuition centre; validate demand first)

- **Absence early-warning:** `attendance_summary` + trend = flag students sliding before parents notice. Milestone: backtested on existing data, the rule flags a real historical decliner earlier than the term report would have.
- **Multi-centre tenancy:** everything is single-centre today (one Supabase project = one centre — the cheapest tenancy model; a second centre = a second project + shared codebase, before any schema-level tenancy work).
- **Attendance-to-outcome linkage:** once `result_slips` is live, correlate attendance % with score movement. Requires PDPA purpose-check first (`tava-pdpa-reference` rule 2).

Label discipline: everything in Tier 3 is **candidate** work — no demand
validated, nothing promised. Don't present these as roadmap.

## Provenance and maintenance

Current as of 2026-07-09. Sources: README Roadmap, HUMANS.md, schema stubs.
- Shelf still accurate? `grep -n 'Phase 2\|Phase 3' README.md`
- Flag states: `SELECT key, enabled FROM feature_flags;`
- Drift campaign closed 2026-07-09 → Tier 2 #5 (drift detector) is now the top ops item.
