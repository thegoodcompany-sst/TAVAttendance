-- Migration 050: record the production UPDATE privilege needed to reach
-- student RLS and the avatar feature/path guard.

BEGIN;

GRANT UPDATE ON TABLE public.students TO authenticated;

DO $$
BEGIN
    ASSERT has_table_privilege(
        'authenticated', 'public.students', 'UPDATE'
    ), 'authenticated lacks students UPDATE privilege';
    ASSERT (
        SELECT relrowsecurity FROM pg_class
        WHERE oid = 'public.students'::REGCLASS
    ), 'students RLS is disabled';
END
$$;

COMMIT;
