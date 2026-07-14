-- 032_app_events_hardening.sql
--
-- Follow-up to 031: reject unrepresentable duration values before casting,
-- refresh the named cron job on replay, and strengthen verification.

CREATE OR REPLACE VIEW app_events_daily WITH (security_invoker = true) AS
SELECT
    occurred_at::date AS event_date,
    platform,
    event_type,
    name,
    COUNT(*) AS event_count,
    percentile_cont(0.5) WITHIN GROUP (
        ORDER BY CASE
            WHEN properties->>'duration_ms' ~ '^\d{1,9}(\.\d{1,3})?$'
            THEN (properties->>'duration_ms')::double precision
        END
    ) AS duration_ms_p50,
    percentile_cont(0.95) WITHIN GROUP (
        ORDER BY CASE
            WHEN properties->>'duration_ms' ~ '^\d{1,9}(\.\d{1,3})?$'
            THEN (properties->>'duration_ms')::double precision
        END
    ) AS duration_ms_p95
FROM app_events
GROUP BY occurred_at::date, platform, event_type, name;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        PERFORM cron.schedule(
            'app-events-purge',
            '35 18 * * *',
            'SELECT purge_app_events();'
        );
    END IF;
EXCEPTION WHEN OTHERS THEN
    NULL;
END;
$$;

-- Verification (DEVOPS-02): abort if this migration did not fully apply.
DO $$
BEGIN
    ASSERT (SELECT COALESCE('security_invoker=true' = ANY (c.reloptions), FALSE)
            FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'public' AND c.relname = 'app_events_daily'),
           'app_events_daily lost security_invoker after 032';
    ASSERT (SELECT pg_get_viewdef('app_events_daily'::regclass) LIKE '%{1,9}%'),
           'app_events_daily duration bound missing after 032';
    ASSERT (SELECT EXISTS (
                SELECT FROM pg_indexes
                WHERE schemaname = 'public'
                  AND tablename = 'app_events'
                  AND indexname = 'idx_app_events_occurred_at'
            )), 'app_events occurred_at index missing after 032';
    ASSERT (SELECT EXISTS (
                SELECT FROM pg_indexes
                WHERE schemaname = 'public'
                  AND tablename = 'app_events'
                  AND indexname = 'idx_app_events_type_occurred_at'
            )), 'app_events event_type index missing after 032';
    ASSERT (SELECT EXISTS (
                SELECT FROM pg_policies
                WHERE schemaname = 'public'
                  AND tablename = 'app_events'
                  AND policyname = 'app_events: authenticated insert own'
                  AND cmd = 'INSERT'
                  AND roles = ARRAY['authenticated']::name[]
                  AND with_check = '(user_id = auth.uid())'
            )), 'app_events own-insert policy incorrect after 032';
    ASSERT (SELECT EXISTS (
                SELECT FROM pg_policies
                WHERE schemaname = 'public'
                  AND tablename = 'app_events'
                  AND policyname = 'app_events: admin read'
                  AND cmd = 'SELECT'
                  AND roles = ARRAY['authenticated']::name[]
                  AND qual = 'is_admin()'
            )), 'app_events admin-read policy incorrect after 032';
    ASSERT (SELECT p.prosecdef
            FROM pg_proc p
            JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'public'
              AND p.proname = 'purge_app_events'
              AND p.pronargs = 0),
           'purge_app_events is not SECURITY DEFINER after 032';
    ASSERT (SELECT COALESCE('search_path=public, pg_temp' = ANY (p.proconfig), FALSE)
            FROM pg_proc p
            JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'public'
              AND p.proname = 'purge_app_events'
              AND p.pronargs = 0),
           'purge_app_events search_path incorrect after 032';
    ASSERT (SELECT NOT EXISTS (
                SELECT FROM pg_proc p
                CROSS JOIN LATERAL aclexplode(
                    COALESCE(p.proacl, acldefault('f', p.proowner))
                ) acl
                WHERE p.oid = 'purge_app_events()'::regprocedure
                  AND acl.grantee = 0
                  AND acl.privilege_type = 'EXECUTE'
            )), 'PUBLIC can execute purge_app_events after 032';
    ASSERT NOT has_function_privilege('anon', 'purge_app_events()', 'EXECUTE'),
           'anon can execute purge_app_events after 032';
    ASSERT NOT has_function_privilege('authenticated', 'purge_app_events()', 'EXECUTE'),
           'authenticated can execute purge_app_events after 032';

    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        ASSERT (SELECT EXISTS (
                    SELECT FROM cron.job
                    WHERE jobname = 'app-events-purge'
                      AND schedule = '35 18 * * *'
                      AND command = 'SELECT purge_app_events();'
                      AND active
                )), 'app-events-purge cron job incorrect after 032';
    END IF;
END $$;

NOTIFY pgrst, 'reload schema';
