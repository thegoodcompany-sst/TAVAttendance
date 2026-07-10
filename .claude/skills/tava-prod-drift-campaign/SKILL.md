---
name: tava-prod-drift-campaign
description: Use before ANY schema work against TAVA's prod Supabase, when a migration "fails on prod but works locally", or when investigating suspected schema drift. The drift crisis was RESOLVED 2026-07-09 (prod = migrations 001–017); this skill now carries the verification snapshot, the drift-prevention protocol, and the record of how the reconciliation was done.
---

# TAVA Prod Drift — resolved 2026-07-09, keep it that way

**Status:** the live Supabase project (`zgikcbsxzjgbigywxbbj`) was reconciled
with `supabase/migrations/` on **2026-07-09**. Prod now matches migrations
**001–017**. The full apply record is in HUMANS.md §14/§30.

**When NOT to use this skill:** local DB work (`supabase db reset`); writing
new migrations (use `tava-change-control`); general prod operations (use
`tava-run-and-operate`).

## The prevention protocol (now the point of this skill)

1. **Never trust files or this doc for prod state — query it** (snapshot below).
2. **Every prod write goes through MCP `apply_migration`** with the SQL preserved in a repo migration. Unrecorded ad-hoc SQL is what caused the original drift.
3. **Migration applies to prod BEFORE app code referencing it deploys** (the 2026-06-27 outage rule).
4. After function changes: `NOTIFY pgrst, 'reload schema';`
5. After schema work: `get_advisors(security)` — anything beyond the accepted WARNs (HUMANS.md Notes: self-guarding SECURITY DEFINER fns callable by `authenticated`, `rate_limit_events` no-policy, leaked-password toggle) gets a new numbered migration, not an ad-hoc fix. Worked example: migration `017_advisor_followups.sql`.
6. `supabase db push` / `db reset` against prod remain FORBIDDEN (the prod migration ledger predates the reconciliation and is still sparse; push would replay partially-existing migrations, reset destroys data).

## Prod verification snapshot (all must hold; run via MCP `execute_sql`)

```sql
SELECT reloptions FROM pg_class WHERE relname='attendance_summary';
-- {security_invoker=true}
SELECT COUNT(*) FROM attendance_summary a JOIN classes c ON c.id=a.class_id WHERE c.is_study_space;
-- 0
SELECT COUNT(*) FROM information_schema.columns WHERE (table_name='classes' AND column_name IN ('recurrence_rule','recurrence_end_date','is_study_space')) OR (table_name='attendance_records' AND column_name IN ('late_reason','client_mutation_id'));
-- 5
SELECT to_regclass('public.device_tokens');           -- not null
SELECT id, public FROM storage.buckets WHERE id='student-photos';  -- 1 row, public=false
SELECT (pg_get_functiondef(oid) LIKE '%TA001%') FROM pg_proc WHERE proname='sync_attendance';  -- t
SELECT (pg_get_functiondef(oid) LIKE '%is_study_space = FALSE%') FROM pg_proc WHERE proname='get_roster_for_date';  -- t
SELECT COALESCE(array_to_string(proconfig,','),'UNPINNED') FROM pg_proc WHERE proname IN ('handle_new_user','check_session_not_ended','link_parent_student','unlink_parent_student');
-- every row: search_path=public
SELECT policyname FROM pg_policies WHERE tablename='profiles';
-- includes "profiles: read own or admin" (NOT "any auth user can read")
```

If any line fails, drift has returned: stop, diagnose which migration's
objects are affected, and converge prod to the files with a recorded apply.

## How the 2026-07-09 reconciliation was done (for the record)

Applied in order via MCP `apply_migration`, each gate-verified before the next:

| Step | What | Why it wasn't just "apply the file" |
|---|---|---|
| `005_backfill_prod_columns` | `late_reason`, `recurrence_rule`, `recurrence_end_date` | 005 was never applied; 013/014 function bodies reference these columns and would roll back (42703-class failure at CREATE). |
| `004_security_fixes_backfill` | profiles policies, verbatim from 004 | Discovered mid-campaign: 004 was ALSO never applied — prod still had the world-readable profiles SELECT policy and the self-role-escalation UPDATE `WITH CHECK`. Found because 013's `COMMENT ON POLICY` targeted the 004 policy name. |
| `013_audit_fixes` | verbatim | — |
| `014_feature_tables` | verbatim + one prepended `DROP FUNCTION get_session_roster(uuid)` | prod had the 010 version with a narrower return type; `CREATE OR REPLACE` can't change return types (42P13). Drop + recreate in one transaction. |
| `015_reapply_after_014` | 015 verbatim (idempotent) | 015 was applied before 014, so 014 had just overwritten 015's study-space-filtered `get_roster_for_date`; re-applying 015 restored the filters. Lesson: **out-of-order applies must re-apply the later migration afterwards.** |
| `005_backfill_parent_link_fns` | `link/unlink_parent_student` verbatim from 005 | 016's SEC-16f `ALTER FUNCTION` needs them to exist. |
| `016_security_fixes` | verbatim | The payoff: leak closed, admin-minting closed. |
| `017_advisor_followups` | new migration (in repo) | Post-apply advisors showed 3 non-accepted findings: unpinned `check_session_not_ended` search_path (016 regression), and `class_punctuality` + parent-link fns executable by anon. |

Post-checks: advisors clean (accepted WARNs only), web prod 200,
`sync_attendance('[]')` returns `{synced:0, skipped:0, blocked_ended_session:0}`,
`get_roster_for_date(CURRENT_DATE)` executes.

## Lessons this campaign added to the canon

- The drift ran deeper than documented: **004 and the 005 RPCs were also unapplied**, invisible until a dependent statement failed. Prerequisite checks before each apply (query `pg_proc`/`pg_policies`/`information_schema`, not the ledger) caught everything before it burned a transaction.
- `CREATE OR REPLACE FUNCTION` cannot change a return type — plan a `DROP` in the same transaction when a signature evolves.
- When migrations were applied out of numeric order, re-apply the later one after backfilling the earlier one, or the earlier one's `CREATE OR REPLACE` silently wins.

## Provenance and maintenance

Reconciliation performed and verified 2026-07-09 (this session; record in
HUMANS.md §14/§30). Re-verify any time with the snapshot block above.
Remaining related human steps: HUMANS.md §31 (disable public signups —
dashboard), §33 (kiosk PIN device check), §17 (push keys).
