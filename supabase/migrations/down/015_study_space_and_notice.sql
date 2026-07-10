-- Down migration for 015_study_space_and_notice.sql

-- B — restore Data Protection Notice v1.0 as current, drop v1.1.
DELETE FROM policy_documents WHERE doc_type = 'data_protection_notice' AND version = '1.1';
UPDATE policy_documents
   SET is_current = TRUE
 WHERE doc_type = 'data_protection_notice' AND version = '1.0';

-- A — drop the Study Space roster RPC.
DROP FUNCTION IF EXISTS get_study_space_roster(UUID);

-- Restore get_roster_for_date to the 014 version (no study-space filter).
CREATE OR REPLACE FUNCTION get_roster_for_date(p_date DATE)
RETURNS TABLE (
    student_id  UUID,
    full_name   TEXT,
    class_names TEXT[],
    status      TEXT,
    marked_at   TIMESTAMPTZ
)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path = public
AS $$
    WITH roster AS (
        SELECT
            st.id        AS student_id,
            st.full_name AS full_name,
            c.name       AS class_name,
            ar.status    AS status,
            ar.marked_at AS marked_at,
            CASE ar.status
                WHEN 'late'    THEN 4
                WHEN 'present' THEN 3
                WHEN 'absent'  THEN 2
                WHEN 'excused' THEN 1
                ELSE 0
            END          AS rank
        FROM sessions se
        JOIN classes c     ON c.id = se.class_id
        JOIN enrollments e ON e.class_id = se.class_id AND e.is_active = TRUE
        JOIN students st   ON st.id = e.student_id AND st.is_active = TRUE
        LEFT JOIN attendance_records ar
               ON ar.session_id = se.id AND ar.student_id = st.id
        WHERE se.session_date = p_date
    ),
    agg AS (
        SELECT student_id, full_name,
               array_agg(DISTINCT class_name ORDER BY class_name) AS class_names
        FROM roster
        GROUP BY student_id, full_name
    ),
    winner AS (
        SELECT DISTINCT ON (student_id) student_id, status, marked_at
        FROM roster
        ORDER BY student_id, rank DESC, marked_at DESC NULLS LAST
    )
    SELECT a.student_id, a.full_name, a.class_names, w.status, w.marked_at
    FROM agg a
    JOIN winner w USING (student_id)
    ORDER BY a.full_name;
$$;
GRANT EXECUTE ON FUNCTION get_roster_for_date(DATE) TO authenticated, service_role;

-- Restore attendance_summary to its pre-015 (post-010) state: security_invoker
-- ON and active-row filter, but no study-space filter. NOT the bare 003 version,
-- which would strip security_invoker and reopen an RLS bypass on rollback.
CREATE OR REPLACE VIEW attendance_summary
WITH (security_invoker = true)
AS
SELECT
    s.student_id,
    st.full_name                                                     AS student_name,
    se.class_id,
    c.name                                                           AS class_name,
    COUNT(*)                                                         AS total_sessions,
    COUNT(*) FILTER (WHERE s.status = 'present')                    AS present_count,
    COUNT(*) FILTER (WHERE s.status = 'late')                       AS late_count,
    COUNT(*) FILTER (WHERE s.status = 'absent')                     AS absent_count,
    COUNT(*) FILTER (WHERE s.status = 'excused')                    AS excused_count,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE s.status IN ('present','late','excused'))
        / NULLIF(COUNT(*), 0),
        1
    )                                                                AS attendance_pct
FROM attendance_records s
JOIN students st  ON st.id = s.student_id
JOIN sessions se  ON se.id = s.session_id
JOIN classes  c   ON c.id  = se.class_id
WHERE st.is_active = TRUE
  AND c.is_active  = TRUE
GROUP BY s.student_id, st.full_name, se.class_id, c.name;

-- Remove the feature flag and the singleton Study Space class, then drop the column.
DELETE FROM feature_flags WHERE key = 'study_space_tracking';
DELETE FROM classes WHERE id = '57000000-0000-0000-0000-000000000001';
ALTER TABLE classes DROP COLUMN IF EXISTS is_study_space;
