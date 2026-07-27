-- down/049_record_result_upload_service_grants.sql — reverse of 049.

BEGIN;

REVOKE SELECT ON TABLE public.result_slips FROM service_role;
REVOKE SELECT, UPDATE ON TABLE public.result_slip_upload_intents FROM service_role;

COMMIT;
