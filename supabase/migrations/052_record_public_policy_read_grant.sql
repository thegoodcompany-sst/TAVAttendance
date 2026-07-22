-- Migration 052: record the production anon privilege needed to reach the
-- public current-policy RLS boundary.

BEGIN;

GRANT SELECT ON TABLE public.policy_documents TO anon;

DO $$
BEGIN
    ASSERT has_table_privilege(
        'anon', 'public.policy_documents', 'SELECT'
    ), 'anon lacks policy_documents SELECT privilege';
    ASSERT (
        SELECT relrowsecurity FROM pg_class
        WHERE oid = 'public.policy_documents'::REGCLASS
    ), 'policy_documents RLS is disabled';
END
$$;

COMMIT;
