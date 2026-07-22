-- Migration 043: record the existing production privileges needed to reach
-- authenticated attendance RLS policies during a clean migration replay.

BEGIN;

GRANT SELECT, INSERT ON TABLE public.attendance_records TO authenticated;

-- Verification (DEVOPS-02): authenticated can reach the RLS boundary, while
-- the table remains protected by row-level policies.
DO $$
BEGIN
    ASSERT has_table_privilege(
        'authenticated', 'public.attendance_records', 'SELECT'
    ), 'authenticated lacks attendance_records SELECT privilege';
    ASSERT has_table_privilege(
        'authenticated', 'public.attendance_records', 'INSERT'
    ), 'authenticated lacks attendance_records INSERT privilege';
    ASSERT (
        SELECT relrowsecurity
        FROM pg_class
        WHERE oid = 'public.attendance_records'::REGCLASS
    ), 'attendance_records RLS is disabled';
END
$$;

COMMIT;
