-- 034_privacy_authorization_hardening.sql
--
-- Security/PDPA audit follow-up:
--   * create a student and the required consent ledger row atomically,
--   * prevent direct student inserts and consent-ledger mutation,
--   * exclude internal Study Space records from every report/export RPC,
--   * restrict tutors' grade access to the subject they actually teach,
--   * remove the first-user metadata privilege-escalation exception, and
--   * pin SECURITY DEFINER functions to public, pg_temp.

-- Student creation is only valid together with an admin attestation.  The
-- SECURITY DEFINER wrapper makes both inserts one transaction and supplies the
-- trusted actor/notice fields server-side.
CREATE OR REPLACE FUNCTION create_student_with_consent(
    p_full_name       TEXT,
    p_date_of_birth   DATE DEFAULT NULL,
    p_school          TEXT DEFAULT NULL,
    p_year_of_study   TEXT DEFAULT NULL,
    p_notes           TEXT DEFAULT NULL,
    p_source_note     TEXT DEFAULT NULL
)
RETURNS students
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_student students;
    v_notice_version TEXT;
BEGIN
    IF NOT is_admin() THEN RAISE EXCEPTION 'not authorized'; END IF;
    IF NULLIF(BTRIM(p_full_name), '') IS NULL THEN
        RAISE EXCEPTION 'student name is required';
    END IF;

    SELECT version INTO v_notice_version
    FROM policy_documents
    WHERE doc_type = 'data_protection_notice' AND is_current
    ORDER BY published_at DESC
    LIMIT 1;

    IF v_notice_version IS NULL THEN
        RAISE EXCEPTION 'no current data protection notice is published';
    END IF;

    INSERT INTO students (full_name, date_of_birth, school, year_of_study, notes)
    VALUES (
        BTRIM(p_full_name), p_date_of_birth, NULLIF(BTRIM(p_school), ''),
        NULLIF(BTRIM(p_year_of_study), ''), NULLIF(BTRIM(p_notes), '')
    )
    RETURNING * INTO v_student;

    INSERT INTO consent_records (
        student_id, consent_type, status, method, notice_version, granted_by, source_note
    ) VALUES (
        v_student.id, 'data_collection', 'granted', 'admin_attestation',
        v_notice_version, auth.uid(), NULLIF(BTRIM(p_source_note), '')
    );

    RETURN v_student;
END;
$$;

REVOKE EXECUTE ON FUNCTION create_student_with_consent(TEXT, DATE, TEXT, TEXT, TEXT, TEXT)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION create_student_with_consent(TEXT, DATE, TEXT, TEXT, TEXT, TEXT)
    TO authenticated, service_role;

-- SECURITY DEFINER bypasses RLS for the atomic wrapper.  Direct authenticated
-- inserts are denied even though the legacy admin FOR ALL policy is permissive.
DROP POLICY IF EXISTS "students: direct insert denied" ON students;
CREATE POLICY "students: direct insert denied"
    ON students AS RESTRICTIVE FOR INSERT TO authenticated
    WITH CHECK (FALSE);

-- The ledger is append-only.  Erasure/anonymisation RPCs remain able to delete
-- rows because they are SECURITY DEFINER; ordinary admins withdraw via INSERT.
-- Explicit grants keep this working on projects created after Supabase stopped
-- exposing new tables/functions to the Data API by default.
GRANT SELECT, INSERT ON consent_records TO authenticated;
GRANT SELECT ON current_consent TO authenticated;
REVOKE UPDATE, DELETE ON consent_records FROM authenticated;
DROP POLICY IF EXISTS "consent_records: updates denied" ON consent_records;
DROP POLICY IF EXISTS "consent_records: deletes denied" ON consent_records;
CREATE POLICY "consent_records: updates denied"
    ON consent_records AS RESTRICTIVE FOR UPDATE TO authenticated
    USING (FALSE) WITH CHECK (FALSE);
CREATE POLICY "consent_records: deletes denied"
    ON consent_records AS RESTRICTIVE FOR DELETE TO authenticated
    USING (FALSE);

-- Invites and dashboard-created accounts are always least-privileged at trigger
-- time.  The service-role invite action elevates the requested role afterwards.
-- This removes the fresh-database "first signup may choose admin" exception.
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    INSERT INTO profiles (id, full_name, role)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email),
        'parent'
    )
    ON CONFLICT (id) DO NOTHING;
    RETURN NEW;
END;
$$;

-- Subject-access bundles are parent-facing disclosures.  Internal Study Space
-- attendance must never be included.
CREATE OR REPLACE FUNCTION export_student_personal_data(p_student_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE result JSONB;
BEGIN
    IF NOT is_admin() THEN RAISE EXCEPTION 'not authorized'; END IF;
    SELECT jsonb_build_object(
        'student',         (SELECT to_jsonb(s) FROM students s WHERE s.id = p_student_id),
        'enrollments',     (SELECT COALESCE(jsonb_agg(to_jsonb(e)), '[]') FROM enrollments e WHERE e.student_id = p_student_id),
        'attendance',      (SELECT COALESCE(jsonb_agg(to_jsonb(a)), '[]')
                            FROM attendance_records a
                            JOIN sessions se ON se.id = a.session_id
                            JOIN classes c ON c.id = se.class_id
                            WHERE a.student_id = p_student_id AND c.is_study_space = FALSE),
        'parents',         (SELECT COALESCE(jsonb_agg(jsonb_build_object('parent', to_jsonb(p), 'link', to_jsonb(l))), '[]') FROM parent_student_links l JOIN profiles p ON p.id = l.parent_id WHERE l.student_id = p_student_id),
        'consent',         (SELECT COALESCE(jsonb_agg(to_jsonb(c)), '[]') FROM consent_records c WHERE c.student_id = p_student_id),
        'result_slips',    (SELECT COALESCE(jsonb_agg(to_jsonb(r)), '[]') FROM result_slips r WHERE r.student_id = p_student_id),
        'student_results', (SELECT COALESCE(jsonb_agg(to_jsonb(sr)), '[]') FROM student_results sr WHERE sr.student_id = p_student_id),
        'dismissals',      (SELECT COALESCE(jsonb_agg(to_jsonb(d)), '[]') FROM dismissals d WHERE d.student_id = p_student_id),
        'awards',          (SELECT COALESCE(jsonb_agg(to_jsonb(w)), '[]') FROM awards w WHERE w.student_id = p_student_id),
        'generated_at',    NOW()
    ) INTO result;
    INSERT INTO data_disclosures (student_id, disclosed_to, disclosure_type, disclosed_by, detail)
    VALUES (p_student_id, 'Subject access request', 'subject_access_export', auth.uid(),
            jsonb_build_object('via', 'export_student_personal_data'));
    RETURN result;
END;
$$;

-- Punctuality is a report, so reject the internal Study Space class even for an
-- admin who knows its fixed UUID.
CREATE OR REPLACE FUNCTION class_punctuality(
    p_class_id UUID, p_from DATE, p_to DATE
)
RETURNS TABLE (
    present_count BIGINT, late_count BIGINT, absent_count BIGINT,
    excused_count BIGINT, total_count BIGINT, on_time_rate NUMERIC
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT (is_admin() OR tutor_owns_class(p_class_id))
       OR NOT EXISTS (
            SELECT 1 FROM classes c
            WHERE c.id = p_class_id AND c.is_study_space = FALSE
       ) THEN
        RAISE EXCEPTION 'not authorized';
    END IF;

    RETURN QUERY
    SELECT
        COUNT(*) FILTER (WHERE ar.status = 'present'),
        COUNT(*) FILTER (WHERE ar.status = 'late'),
        COUNT(*) FILTER (WHERE ar.status = 'absent'),
        COUNT(*) FILTER (WHERE ar.status = 'excused'),
        COUNT(*),
        CASE WHEN COUNT(*) = 0 THEN NULL
             ELSE ROUND(COUNT(*) FILTER (WHERE ar.status = 'present')::NUMERIC / COUNT(*), 4)
        END
    FROM attendance_records ar
    JOIN sessions s ON s.id = ar.session_id
    WHERE s.class_id = p_class_id
      AND s.session_date BETWEEN p_from AND p_to;
END;
$$;

-- A tutor may manage only the grade subject represented by one of their active
-- assigned classes (free-text class subjects are normalised like the clients).
DROP POLICY IF EXISTS "student_results: tutor manages enrolled students" ON student_results;
CREATE POLICY "student_results: tutor manages enrolled students"
    ON student_results FOR ALL TO authenticated
    USING (
        is_tutor() AND EXISTS (
            SELECT 1
            FROM enrollments e
            JOIN classes c ON c.id = e.class_id
            JOIN class_tutor_assignments cta ON cta.class_id = e.class_id
            WHERE e.student_id = student_results.student_id
              AND e.is_active = TRUE AND c.is_active = TRUE
              AND cta.tutor_id = auth.uid()
              AND cta.assigned_from <= CURRENT_DATE
              AND (cta.assigned_until IS NULL OR cta.assigned_until >= CURRENT_DATE)
              AND ((student_results.subject = 'Math' AND LOWER(BTRIM(c.subject)) LIKE 'math%')
                OR (student_results.subject = 'English' AND LOWER(BTRIM(c.subject)) LIKE 'eng%'))
        )
    )
    WITH CHECK (
        is_tutor() AND EXISTS (
            SELECT 1
            FROM enrollments e
            JOIN classes c ON c.id = e.class_id
            JOIN class_tutor_assignments cta ON cta.class_id = e.class_id
            WHERE e.student_id = student_results.student_id
              AND e.is_active = TRUE AND c.is_active = TRUE
              AND cta.tutor_id = auth.uid()
              AND cta.assigned_from <= CURRENT_DATE
              AND (cta.assigned_until IS NULL OR cta.assigned_until >= CURRENT_DATE)
              AND ((student_results.subject = 'Math' AND LOWER(BTRIM(c.subject)) LIKE 'math%')
                OR (student_results.subject = 'English' AND LOWER(BTRIM(c.subject)) LIKE 'eng%'))
        )
    );

-- Bring every currently-live SECURITY DEFINER function up to the repository's
-- pinned-search-path rule.  (Trigger/invoker functions are intentionally absent.)
ALTER FUNCTION audit_trigger_func() SET search_path = public, pg_temp;
ALTER FUNCTION get_my_role() SET search_path = public, pg_temp;
ALTER FUNCTION is_admin() SET search_path = public, pg_temp;
ALTER FUNCTION is_tutor() SET search_path = public, pg_temp;
ALTER FUNCTION is_parent() SET search_path = public, pg_temp;
ALTER FUNCTION tutor_owns_class(UUID) SET search_path = public, pg_temp;
ALTER FUNCTION parent_owns_student(UUID) SET search_path = public, pg_temp;
ALTER FUNCTION link_parent_student(UUID, UUID) SET search_path = public, pg_temp;
ALTER FUNCTION unlink_parent_student(UUID, UUID) SET search_path = public, pg_temp;
ALTER FUNCTION _anonymise_student(UUID) SET search_path = public, pg_temp;
ALTER FUNCTION anonymise_student(UUID) SET search_path = public, pg_temp;
ALTER FUNCTION erase_student(UUID) SET search_path = public, pg_temp;
ALTER FUNCTION purge_expired_personal_data() SET search_path = public, pg_temp;
ALTER FUNCTION wipe_operational_data(TEXT) SET search_path = public, pg_temp;
ALTER FUNCTION is_feature_enabled(TEXT) SET search_path = public, pg_temp;
ALTER FUNCTION mark_safely_home(UUID) SET search_path = public, pg_temp;
ALTER FUNCTION notify_parent_on_attendance() SET search_path = public, pg_temp;
ALTER FUNCTION notify_parent_on_dismissal() SET search_path = public, pg_temp;

NOTIFY pgrst, 'reload schema';

-- Fail the migration if a security-critical contract was not installed.
DO $$
BEGIN
    ASSERT NOT has_function_privilege('anon',
        'create_student_with_consent(text,date,text,text,text,text)', 'EXECUTE'),
        'anon can execute create_student_with_consent';
    ASSERT has_function_privilege('authenticated',
        'create_student_with_consent(text,date,text,text,text,text)', 'EXECUTE'),
        'authenticated cannot execute create_student_with_consent';
    ASSERT NOT has_table_privilege('authenticated', 'consent_records', 'UPDATE'),
        'authenticated can update the consent ledger';
    ASSERT NOT has_table_privilege('authenticated', 'consent_records', 'DELETE'),
        'authenticated can delete from the consent ledger';
    ASSERT POSITION(
        'c.is_study_space = false'
        IN LOWER(pg_get_functiondef('export_student_personal_data(uuid)'::regprocedure))
    ) > 0,
        'subject-access export still includes Study Space attendance';
    ASSERT pg_get_functiondef('handle_new_user()'::regprocedure)
        NOT LIKE '%is_bootstrap%',
        'handle_new_user still contains the bootstrap privilege exception';
    ASSERT (
        SELECT LOWER(qual) LIKE '%assigned_from%'
           AND LOWER(with_check) LIKE '%assigned_from%'
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'student_results'
          AND policyname = 'student_results: tutor manages enrolled students'
    ), 'future tutor assignments can manage grades before their start date';
END $$;
