-- Down migration for 014_feature_tables.sql
DROP FUNCTION IF EXISTS get_roster_for_date(DATE);

-- Restore get_session_roster to the 010_audit_fixes.sql version (without avatar_url).
CREATE OR REPLACE FUNCTION get_session_roster(p_session_id UUID)
RETURNS TABLE (
    student_id      UUID,
    full_name       TEXT,
    attendance_id   UUID,
    status          TEXT,
    marked_at       TIMESTAMPTZ,
    notes           TEXT,
    late_reason     TEXT
) LANGUAGE SQL STABLE
SET search_path = public
AS $$
    SELECT
        st.id, st.full_name, ar.id, ar.status, ar.marked_at, ar.notes, ar.late_reason
    FROM sessions se
    JOIN enrollments e  ON e.class_id  = se.class_id AND e.is_active = TRUE
    JOIN students    st ON st.id       = e.student_id AND st.is_active = TRUE
    LEFT JOIN attendance_records ar ON ar.session_id = se.id AND ar.student_id = st.id
    WHERE se.id = p_session_id
    ORDER BY st.full_name;
$$;
GRANT EXECUTE ON FUNCTION get_session_roster(UUID) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION get_session_roster(UUID) FROM PUBLIC, anon;

DROP POLICY IF EXISTS "device_tokens: owner manages own" ON device_tokens;
DROP TABLE IF EXISTS device_tokens;

DROP POLICY IF EXISTS "student-photos: admin all" ON storage.objects;
DROP POLICY IF EXISTS "student-photos: auth read" ON storage.objects;
DELETE FROM storage.buckets WHERE id = 'student-photos';

ALTER TABLE students DROP COLUMN IF EXISTS avatar_url;
