-- down/031_app_events.sql — reverse of 031.

DO $$
DECLARE
    app_events_job_id BIGINT;
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        SELECT jobid INTO app_events_job_id
        FROM cron.job
        WHERE jobname = 'app-events-purge'
        LIMIT 1;

        IF app_events_job_id IS NOT NULL THEN
            PERFORM cron.unschedule(app_events_job_id);
        END IF;
    END IF;
EXCEPTION WHEN OTHERS THEN
    NULL;
END;
$$;

DELETE FROM feature_flags WHERE key = 'analytics';
DROP VIEW IF EXISTS app_events_daily;
DROP FUNCTION IF EXISTS purge_app_events();
DROP TABLE IF EXISTS app_events;

NOTIFY pgrst, 'reload schema';
