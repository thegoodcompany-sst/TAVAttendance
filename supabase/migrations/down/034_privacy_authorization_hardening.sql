-- Reverse of 034_privacy_authorization_hardening.sql.
-- This deliberately restores the post-033 behavior, including the authorization
-- gaps fixed by 034. Use only for an emergency rollback.

DROP POLICY IF EXISTS "students: direct insert denied" ON students;
DROP POLICY IF EXISTS "consent_records: updates denied" ON consent_records;
DROP POLICY IF EXISTS "consent_records: deletes denied" ON consent_records;
GRANT UPDATE, DELETE ON consent_records TO authenticated;
DROP FUNCTION IF EXISTS create_student_with_consent(TEXT, DATE, TEXT, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    requested_role TEXT    := COALESCE(NEW.raw_user_meta_data->>'role', 'parent');
    is_bootstrap   BOOLEAN := NOT EXISTS (SELECT 1 FROM profiles);
    final_role     TEXT;
BEGIN
    IF is_bootstrap OR is_admin() THEN
        final_role := requested_role;
    ELSE
        final_role := 'parent';
    END IF;
    INSERT INTO profiles (id, full_name, role)
    VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email), final_role)
    ON CONFLICT (id) DO NOTHING;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION export_student_personal_data(p_student_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE result JSONB;
BEGIN
    IF NOT is_admin() THEN RAISE EXCEPTION 'not authorized'; END IF;
    SELECT jsonb_build_object(
        'student',         (SELECT to_jsonb(s) FROM students s WHERE s.id = p_student_id),
        'enrollments',     (SELECT COALESCE(jsonb_agg(to_jsonb(e)), '[]') FROM enrollments e WHERE e.student_id = p_student_id),
        'attendance',      (SELECT COALESCE(jsonb_agg(to_jsonb(a)), '[]') FROM attendance_records a WHERE a.student_id = p_student_id),
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
SET search_path = public
AS $$
BEGIN
    IF NOT (is_admin() OR tutor_owns_class(p_class_id)) THEN
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

DROP POLICY IF EXISTS "student_results: tutor manages enrolled students" ON student_results;
CREATE POLICY "student_results: tutor manages enrolled students"
    ON student_results FOR ALL TO authenticated
    USING (
        is_tutor() AND EXISTS (
            SELECT 1 FROM enrollments e
            JOIN class_tutor_assignments cta ON cta.class_id = e.class_id
            WHERE e.student_id = student_results.student_id
              AND e.is_active = TRUE
              AND cta.tutor_id = auth.uid()
              AND (cta.assigned_until IS NULL OR cta.assigned_until >= CURRENT_DATE)
        )
    )
    WITH CHECK (
        is_tutor() AND EXISTS (
            SELECT 1 FROM enrollments e
            JOIN class_tutor_assignments cta ON cta.class_id = e.class_id
            WHERE e.student_id = student_results.student_id
              AND e.is_active = TRUE
              AND cta.tutor_id = auth.uid()
              AND (cta.assigned_until IS NULL OR cta.assigned_until >= CURRENT_DATE)
        )
    );

ALTER FUNCTION audit_trigger_func() SET search_path = public;
ALTER FUNCTION get_my_role() SET search_path = public;
ALTER FUNCTION is_admin() SET search_path = public;
ALTER FUNCTION is_tutor() SET search_path = public;
ALTER FUNCTION is_parent() SET search_path = public;
ALTER FUNCTION tutor_owns_class(UUID) SET search_path = public;
ALTER FUNCTION parent_owns_student(UUID) SET search_path = public;
ALTER FUNCTION link_parent_student(UUID, UUID) SET search_path = public;
ALTER FUNCTION unlink_parent_student(UUID, UUID) SET search_path = public;
ALTER FUNCTION _anonymise_student(UUID) SET search_path = public;
ALTER FUNCTION anonymise_student(UUID) SET search_path = public;
ALTER FUNCTION erase_student(UUID) SET search_path = public;
ALTER FUNCTION purge_expired_personal_data() SET search_path = public;
ALTER FUNCTION wipe_operational_data(TEXT) SET search_path = public;
ALTER FUNCTION is_feature_enabled(TEXT) SET search_path = public;
ALTER FUNCTION mark_safely_home(UUID) SET search_path = public, pg_temp;
ALTER FUNCTION notify_parent_on_attendance() SET search_path = public;
ALTER FUNCTION notify_parent_on_dismissal() SET search_path = public;

NOTIFY pgrst, 'reload schema';
