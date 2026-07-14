-- 033_app_events_singapore_day.sql
--
-- TAVA operates in Singapore, so daily analytics must use the centre's calendar
-- day rather than UTC around midnight.

CREATE OR REPLACE VIEW app_events_daily WITH (security_invoker = true) AS
SELECT
    (occurred_at AT TIME ZONE 'Asia/Singapore')::date AS event_date,
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
GROUP BY (occurred_at AT TIME ZONE 'Asia/Singapore')::date, platform, event_type, name;

-- Verification (DEVOPS-02): abort if this migration did not fully apply.
DO $$
BEGIN
    ASSERT (SELECT COALESCE('security_invoker=true' = ANY (c.reloptions), FALSE)
            FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'public' AND c.relname = 'app_events_daily'),
           'app_events_daily lost security_invoker after 033';
    ASSERT (SELECT pg_get_viewdef('app_events_daily'::regclass) LIKE '%Asia/Singapore%'),
           'app_events_daily is not grouped in Singapore time after 033';
END $$;

NOTIFY pgrst, 'reload schema';
