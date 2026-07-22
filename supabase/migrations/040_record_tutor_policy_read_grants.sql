-- Migration 040: record the table privileges required by tutor-facing RLS
-- policy subqueries. Production already had these grants out of band, but a
-- clean migration replay did not, so evaluating the students policy failed
-- before RLS could filter enrollment and assignment rows.

BEGIN;

GRANT SELECT ON TABLE public.enrollments TO authenticated;
GRANT SELECT ON TABLE public.class_tutor_assignments TO authenticated;

-- Verification (DEVOPS-02): table privileges permit policy evaluation while
-- each relation remains protected by RLS.
DO $$
BEGIN
    ASSERT has_table_privilege(
        'authenticated', 'public.enrollments', 'SELECT'
    ), 'authenticated lacks enrollments SELECT privilege';
    ASSERT has_table_privilege(
        'authenticated', 'public.class_tutor_assignments', 'SELECT'
    ), 'authenticated lacks class_tutor_assignments SELECT privilege';
    ASSERT (
        SELECT relrowsecurity
        FROM pg_class
        WHERE oid = 'public.enrollments'::REGCLASS
    ), 'enrollments RLS is disabled';
    ASSERT (
        SELECT relrowsecurity
        FROM pg_class
        WHERE oid = 'public.class_tutor_assignments'::REGCLASS
    ), 'class_tutor_assignments RLS is disabled';
END
$$;

COMMIT;
