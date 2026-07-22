-- Migration 051: record the production INSERT privilege needed to reach the
-- admin-only, feature-gated awards RLS boundary.

BEGIN;

GRANT INSERT ON TABLE public.awards TO authenticated;

DO $$
BEGIN
    ASSERT has_table_privilege(
        'authenticated', 'public.awards', 'INSERT'
    ), 'authenticated lacks awards INSERT privilege';
    ASSERT (
        SELECT relrowsecurity FROM pg_class
        WHERE oid = 'public.awards'::REGCLASS
    ), 'awards RLS is disabled';
END
$$;

COMMIT;
