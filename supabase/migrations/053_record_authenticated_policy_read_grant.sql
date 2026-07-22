-- Migration 053: record the authenticated privilege needed to reach the
-- current-policy RLS boundary.

BEGIN;

GRANT SELECT ON TABLE public.policy_documents TO authenticated;

DO $$
BEGIN
    ASSERT has_table_privilege(
        'authenticated', 'public.policy_documents', 'SELECT'
    ), 'authenticated lacks policy_documents SELECT privilege';
    ASSERT (
        SELECT relrowsecurity FROM pg_class
        WHERE oid = 'public.policy_documents'::REGCLASS
    ), 'policy_documents RLS is disabled';
END
$$;

COMMIT;
