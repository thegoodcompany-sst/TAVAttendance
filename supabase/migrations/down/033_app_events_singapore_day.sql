-- down/033_app_events_singapore_day.sql — reverse of 033.

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

NOTIFY pgrst, 'reload schema';
