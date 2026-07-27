-- Migration 039: restore the table privilege required by the superadmin-only
-- feature-flag UI. Migration 038 narrowed the RLS write policy correctly, but
-- authenticated retained only SELECT from migration 012, so PostgreSQL denied
-- UPDATE before the policy could authorize the database-managed superadmin.

BEGIN;

GRANT UPDATE ON TABLE public.feature_flags TO authenticated;

-- Verification (DEVOPS-02): the table grant must exist and RLS must remain the
-- effective superadmin boundary for authenticated callers.
DO $$
BEGIN
    ASSERT has_table_privilege(
        'authenticated', 'public.feature_flags', 'UPDATE'
    ), 'authenticated lacks feature_flags UPDATE privilege';

    ASSERT (
        SELECT LOWER(qual) LIKE '%is_superadmin%'
           AND LOWER(with_check) LIKE '%is_superadmin%'
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'feature_flags'
          AND policyname = 'feature_flags: superadmin writes'
    ), 'feature_flags update is not bounded by the superadmin RLS policy';
END
$$;

COMMIT;
