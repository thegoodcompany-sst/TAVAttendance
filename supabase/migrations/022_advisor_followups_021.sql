-- 022_advisor_followups_021.sql
--
-- Advisor cleanup for 021 (same pattern as 017):
-- 1. notify_parent_on_attendance() is a trigger function — PostgREST can't
--    actually run it (returns trigger), but revoke EXECUTE anyway so the
--    security advisors stay clean and intent is explicit.
-- 2. Re-register the pg_net extension in the `extensions` schema instead of
--    `public` (its API lives in the `net` schema either way; plpgsql resolves
--    net.http_post at runtime, so the recreate is safe for the 021 trigger).

REVOKE EXECUTE ON FUNCTION notify_parent_on_attendance() FROM PUBLIC, anon, authenticated;

DROP EXTENSION IF EXISTS pg_net;
CREATE EXTENSION pg_net SCHEMA extensions;

-- Verification (DEVOPS-02): abort if this migration did not fully apply.
DO $$
BEGIN
    ASSERT (SELECT NOT has_function_privilege('anon', 'notify_parent_on_attendance()', 'EXECUTE')),
           'anon can still execute notify_parent_on_attendance after 022';
    ASSERT (SELECT NOT has_function_privilege('authenticated', 'notify_parent_on_attendance()', 'EXECUTE')),
           'authenticated can still execute notify_parent_on_attendance after 022';
    ASSERT (SELECT n.nspname = 'extensions' FROM pg_extension e
            JOIN pg_namespace n ON n.oid = e.extnamespace WHERE e.extname = 'pg_net'),
           'pg_net not in extensions schema after 022';
    -- the 021 trigger must still be armed after the extension recreate
    ASSERT (SELECT EXISTS (SELECT FROM pg_trigger WHERE tgname = 'trg_notify_parent')),
           'trg_notify_parent lost after 022';
END $$;
