-- Fix: attendance_summary flagged as SECURITY DEFINER by Supabase linter.
-- Views owned by a superuser run with the owner's privileges by default,
-- bypassing RLS on the underlying tables. Adding security_invoker = true
-- forces the view to execute as the querying user so RLS applies normally.

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
GROUP BY s.student_id, st.full_name, se.class_id, c.name;
