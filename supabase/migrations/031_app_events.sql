-- 031_app_events.sql
--
-- Supabase-native product analytics and operational telemetry. Capture is dark
-- until the analytics feature flag is enabled on all clients.

CREATE TABLE app_events (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    user_id     UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    role        TEXT,
    platform    TEXT NOT NULL CONSTRAINT app_events_platform_check
                CHECK (platform IN ('ios', 'android', 'web')),
    app_version TEXT,
    session_id  TEXT NOT NULL,
    event_type  TEXT NOT NULL CONSTRAINT app_events_event_type_check
                CHECK (event_type IN ('screen_view', 'tap', 'error', 'crash', 'ops', 'latency')),
    name        TEXT NOT NULL,
    properties  JSONB NOT NULL DEFAULT '{}'::jsonb,
    device      TEXT
);

CREATE INDEX idx_app_events_occurred_at
    ON app_events (occurred_at DESC);
CREATE INDEX idx_app_events_type_occurred_at
    ON app_events (event_type, occurred_at DESC);

ALTER TABLE app_events ENABLE ROW LEVEL SECURITY;

GRANT INSERT, SELECT ON app_events TO authenticated;
REVOKE UPDATE, DELETE ON app_events FROM authenticated;

CREATE POLICY "app_events: authenticated insert own"
    ON app_events FOR INSERT TO authenticated
    WITH CHECK (user_id = auth.uid());

CREATE POLICY "app_events: admin read"
    ON app_events FOR SELECT TO authenticated
    USING (is_admin());

CREATE VIEW app_events_daily WITH (security_invoker = true) AS
SELECT
    occurred_at::date AS event_date,
    platform,
    event_type,
    name,
    COUNT(*) AS event_count,
    percentile_cont(0.5) WITHIN GROUP (
        ORDER BY CASE
            WHEN properties->>'duration_ms' ~ '^\d+(\.\d+)?$'
            THEN (properties->>'duration_ms')::double precision
        END
    ) AS duration_ms_p50,
    percentile_cont(0.95) WITHIN GROUP (
        ORDER BY CASE
            WHEN properties->>'duration_ms' ~ '^\d+(\.\d+)?$'
            THEN (properties->>'duration_ms')::double precision
        END
    ) AS duration_ms_p95
FROM app_events
GROUP BY occurred_at::date, platform, event_type, name;

GRANT SELECT ON app_events_daily TO authenticated;

CREATE FUNCTION purge_app_events()
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    deleted_count BIGINT;
BEGIN
    DELETE FROM app_events
    WHERE occurred_at < NOW() - INTERVAL '90 days';

    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$;

REVOKE EXECUTE ON FUNCTION purge_app_events() FROM PUBLIC, anon, authenticated;

DO $$
BEGIN
    CREATE EXTENSION IF NOT EXISTS pg_cron;
EXCEPTION WHEN OTHERS THEN
    NULL;
END;
$$;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'app-events-purge') THEN
            PERFORM cron.schedule(
                'app-events-purge',
                '35 18 * * *',
                'SELECT purge_app_events();'
            );
        END IF;
    END IF;
EXCEPTION WHEN OTHERS THEN
    NULL;
END;
$$;

INSERT INTO feature_flags (key, enabled, description)
VALUES (
    'analytics',
    FALSE,
    'Supabase-native staff analytics, operational telemetry, and health reporting.'
)
ON CONFLICT (key) DO NOTHING;

NOTIFY pgrst, 'reload schema';

-- Verification (DEVOPS-02): abort if this migration did not fully apply.
DO $$
BEGIN
    ASSERT to_regclass('public.app_events') IS NOT NULL,
           'app_events missing after 031';
    ASSERT to_regclass('public.app_events_daily') IS NOT NULL,
           'app_events_daily missing after 031';
    ASSERT (SELECT relrowsecurity FROM pg_class WHERE oid = 'app_events'::regclass),
           'app_events RLS disabled after 031';
    ASSERT (SELECT COUNT(*) = 2 FROM pg_policies
            WHERE schemaname = 'public' AND tablename = 'app_events'),
           'app_events policies missing after 031';
    ASSERT has_table_privilege('authenticated', 'app_events', 'INSERT'),
           'authenticated cannot insert app_events after 031';
    ASSERT has_table_privilege('authenticated', 'app_events', 'SELECT'),
           'authenticated cannot select app_events after 031';
    ASSERT NOT has_table_privilege('authenticated', 'app_events', 'UPDATE'),
           'authenticated can update app_events after 031';
    ASSERT NOT has_table_privilege('authenticated', 'app_events', 'DELETE'),
           'authenticated can delete app_events after 031';
    ASSERT (SELECT COALESCE('security_invoker=true' = ANY (c.reloptions), FALSE)
            FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'public' AND c.relname = 'app_events_daily'),
           'app_events_daily lost security_invoker after 031';
    ASSERT (SELECT EXISTS (
                SELECT FROM pg_constraint
                WHERE conrelid = 'app_events'::regclass
                  AND conname = 'app_events_platform_check'
            )), 'app_events platform constraint missing after 031';
    ASSERT (SELECT EXISTS (
                SELECT FROM pg_constraint
                WHERE conrelid = 'app_events'::regclass
                  AND conname = 'app_events_event_type_check'
            )), 'app_events event type constraint missing after 031';
    ASSERT (SELECT NOT has_function_privilege(
                'authenticated', 'purge_app_events()', 'EXECUTE'
            )), 'authenticated can execute purge_app_events after 031';
    ASSERT (SELECT EXISTS (
                SELECT FROM feature_flags
                WHERE key = 'analytics' AND enabled = FALSE
            )), 'analytics flag missing or enabled after 031';
END $$;
