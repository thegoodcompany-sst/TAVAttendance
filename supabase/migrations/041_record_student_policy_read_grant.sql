-- Migration 041: record the existing production SELECT privilege needed to
-- evaluate tutor-facing student RLS policies during a clean migration replay.

BEGIN;

GRANT SELECT ON TABLE public.students TO authenticated;

-- Verification (DEVOPS-02): authenticated can reach the RLS boundary, while
-- the table remains protected by row-level policies.
DO $$
BEGIN
    ASSERT has_table_privilege(
        'authenticated', 'public.students', 'SELECT'
    ), 'authenticated lacks students SELECT privilege';
    ASSERT (
        SELECT relrowsecurity
        FROM pg_class
        WHERE oid = 'public.students'::REGCLASS
    ), 'students RLS is disabled';
END
$$;

COMMIT;
