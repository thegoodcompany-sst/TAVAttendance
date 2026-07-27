-- Migration 049: record table privileges used by the trusted result-upload
-- orchestrator and its idempotency/expiry checks.

BEGIN;

GRANT SELECT ON TABLE public.result_slips TO service_role;
GRANT SELECT, UPDATE ON TABLE public.result_slip_upload_intents TO service_role;

DO $$
BEGIN
    ASSERT has_table_privilege(
        'service_role', 'public.result_slips', 'SELECT'
    ), 'service_role lacks result_slips SELECT';
    ASSERT has_table_privilege(
        'service_role', 'public.result_slip_upload_intents', 'SELECT'
    ) AND has_table_privilege(
        'service_role', 'public.result_slip_upload_intents', 'UPDATE'
    ), 'service_role lacks result-upload intent read/update privileges';
END
$$;

COMMIT;
