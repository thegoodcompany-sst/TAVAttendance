-- Static contract for study-space exclusion on the money view and parent summary.
-- Runs against a locally reset DB (same style as other supabase/tests).
-- Prefer this when Docker is up; web/lib/study-space-invariant.test.ts covers
-- the migration source when the DB is unavailable.
--
-- Run: psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/study_space_exclusion_contract_test.sql

BEGIN;

DO $$
DECLARE
    v_view_def TEXT;
    v_fn_def   TEXT;
BEGIN
    SELECT pg_get_viewdef('public.attendance_summary'::regclass, true)
    INTO v_view_def;
    ASSERT v_view_def IS NOT NULL, 'attendance_summary view missing';
    ASSERT POSITION('is_study_space' IN v_view_def) > 0,
           'attendance_summary must filter is_study_space';
    ASSERT v_view_def ~* 'is_study_space\s*=\s*false'
           OR v_view_def ~* 'is_study_space\s*=\s*FALSE'
           OR v_view_def ~* 'NOT\s+.*is_study_space',
           'attendance_summary study-space filter missing: ' || v_view_def;

    SELECT pg_get_functiondef('public.get_parent_attendance_summary(uuid)'::regprocedure)
    INTO v_fn_def;
    ASSERT v_fn_def IS NOT NULL, 'get_parent_attendance_summary missing';
    ASSERT v_fn_def ~* 'is_study_space\s*=\s*false'
           OR v_fn_def ~* 'is_study_space\s*=\s*FALSE',
           'parent attendance summary must exclude study space';

    ASSERT (
        SELECT COALESCE('security_invoker=true' = ANY (c.reloptions), FALSE)
        FROM pg_class c
        WHERE c.relname = 'attendance_summary'
          AND c.relnamespace = 'public'::regnamespace
    ), 'attendance_summary must use security_invoker';

    RAISE NOTICE 'study_space_exclusion_contract_test: all assertions passed';
END $$;

ROLLBACK;
