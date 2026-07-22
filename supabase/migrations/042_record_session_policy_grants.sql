-- Migration 042: record the existing production privileges needed to reach
-- authenticated session RLS policies during a clean migration replay.

BEGIN;

GRANT SELECT, UPDATE ON TABLE public.sessions TO authenticated;

-- Verification (DEVOPS-02): authenticated can reach the RLS boundary, while
-- the table remains protected by row-level policies.
DO $$
BEGIN
    ASSERT has_table_privilege(
        'authenticated', 'public.sessions', 'SELECT'
    ), 'authenticated lacks sessions SELECT privilege';
    ASSERT has_table_privilege(
        'authenticated', 'public.sessions', 'UPDATE'
    ), 'authenticated lacks sessions UPDATE privilege';
    ASSERT (
        SELECT relrowsecurity
        FROM pg_class
        WHERE oid = 'public.sessions'::REGCLASS
    ), 'sessions RLS is disabled';
END
$$;

COMMIT;
