-- 024_wipe_operational_data.sql
--
-- Pre-launch data wipe. Superadmin-only RPC that clears all operational +
-- roster data before go-live, keeping accounts, config, and the Study Space
-- class row. Invoked from the web "Danger" page (superadmin-gated there too).
--
-- Conventions follow 011/023: SECURITY DEFINER pins search_path; granted to
-- authenticated and guarded internally (matches the accepted pattern for
-- admin-facing RPCs — the guard, not the GRANT, is the gate).

CREATE OR REPLACE FUNCTION wipe_operational_data(confirmation TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_email       TEXT;
    v_counts      JSONB := '{}'::jsonb;
    v_n           BIGINT;
    -- ponytail: mirrors the app-layer superadmin default in web/lib/superadmin.ts.
    -- The superadmin gate is email-based only; there is no is_superadmin() helper
    -- or profiles column, so re-derive the same check server-side here.
    c_superadmin  CONSTANT TEXT := 'edmund@thegoodcompanysg.dev';
BEGIN
    SELECT lower(email) INTO v_email FROM auth.users WHERE id = auth.uid();
    IF v_email IS DISTINCT FROM c_superadmin THEN
        RAISE EXCEPTION 'not authorized';
    END IF;

    IF confirmation IS DISTINCT FROM 'WIPE ALL DATA' THEN
        RAISE EXCEPTION 'confirmation mismatch';
    END IF;

    -- Don't record the wipe itself in audit_log (tx-local); we scrub the old
    -- snapshots below anyway.
    PERFORM set_config('app.suppress_audit', 'on', true);

    -- The only DELETE-blocking guard on any wiped table: attendance rows for
    -- ended sessions raise TA001. Disable for the wipe; a rollback (ALTER is
    -- transactional) restores it on any error before COMMIT.
    ALTER TABLE attendance_records DISABLE TRIGGER enforce_attendance_on_open_session;

    -- FK-safe order (children first). Counts captured before cascades can act.
    DELETE FROM dismissals;              GET DIAGNOSTICS v_n = ROW_COUNT; v_counts := v_counts || jsonb_build_object('dismissals', v_n);
    DELETE FROM attendance_records;      GET DIAGNOSTICS v_n = ROW_COUNT; v_counts := v_counts || jsonb_build_object('attendance_records', v_n);
    DELETE FROM sessions;                GET DIAGNOSTICS v_n = ROW_COUNT; v_counts := v_counts || jsonb_build_object('sessions', v_n);
    DELETE FROM student_results;         GET DIAGNOSTICS v_n = ROW_COUNT; v_counts := v_counts || jsonb_build_object('student_results', v_n);
    DELETE FROM correction_requests;     GET DIAGNOSTICS v_n = ROW_COUNT; v_counts := v_counts || jsonb_build_object('correction_requests', v_n);
    DELETE FROM data_disclosures;        GET DIAGNOSTICS v_n = ROW_COUNT; v_counts := v_counts || jsonb_build_object('data_disclosures', v_n);
    DELETE FROM consent_records;         GET DIAGNOSTICS v_n = ROW_COUNT; v_counts := v_counts || jsonb_build_object('consent_records', v_n);
    DELETE FROM parent_student_links;    GET DIAGNOSTICS v_n = ROW_COUNT; v_counts := v_counts || jsonb_build_object('parent_student_links', v_n);
    DELETE FROM enrollments;             GET DIAGNOSTICS v_n = ROW_COUNT; v_counts := v_counts || jsonb_build_object('enrollments', v_n);
    DELETE FROM students;                GET DIAGNOSTICS v_n = ROW_COUNT; v_counts := v_counts || jsonb_build_object('students', v_n);
    -- Keep the Study Space class row (fixed UUID); wipe all other classes.
    DELETE FROM classes WHERE is_study_space IS NOT TRUE;
    GET DIAGNOSTICS v_n = ROW_COUNT;     v_counts := v_counts || jsonb_build_object('classes', v_n);

    ALTER TABLE attendance_records ENABLE TRIGGER enforce_attendance_on_open_session;

    -- Scrub audit snapshots for the wiped tables — the JSONB old/new_data holds
    -- student PII, so leaving these rows would defeat the wipe.
    DELETE FROM audit_log WHERE table_name IN (
        'dismissals', 'attendance_records', 'sessions', 'student_results',
        'correction_requests', 'data_disclosures', 'consent_records',
        'parent_student_links', 'enrollments', 'students', 'classes'
    );
    GET DIAGNOSTICS v_n = ROW_COUNT;     v_counts := v_counts || jsonb_build_object('audit_log', v_n);

    RETURN v_counts;
END;
$$;

GRANT EXECUTE ON FUNCTION wipe_operational_data(TEXT) TO authenticated;
REVOKE EXECUTE ON FUNCTION wipe_operational_data(TEXT) FROM PUBLIC, anon;

NOTIFY pgrst, 'reload schema';

-- Verification (DEVOPS-02): abort if this migration did not fully apply.
DO $$
BEGIN
    ASSERT (SELECT EXISTS (
        SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = 'wipe_operational_data'
          AND pg_get_function_identity_arguments(p.oid) = 'confirmation text')),
        'wipe_operational_data(text) missing after 024';
    -- At apply time auth.uid() is NULL, so the superadmin guard must fire and
    -- reject the call regardless of confirmation — proves the gate is wired.
    BEGIN
        PERFORM wipe_operational_data('WIPE ALL DATA');
        RAISE EXCEPTION 'wipe_operational_data did not reject a non-superadmin caller';
    EXCEPTION
        WHEN sqlstate 'P0001' THEN
            ASSERT SQLERRM = 'not authorized',
                'wipe_operational_data guard fired with unexpected message: ' || SQLERRM;
    END;
END $$;
