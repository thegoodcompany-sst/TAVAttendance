-- down/053_record_authenticated_policy_read_grant.sql — reverse of 053.

BEGIN;

REVOKE SELECT ON TABLE public.policy_documents FROM authenticated;

COMMIT;
