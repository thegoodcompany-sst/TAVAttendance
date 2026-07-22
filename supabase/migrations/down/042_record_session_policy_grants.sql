-- down/042_record_session_policy_grants.sql — reverse of 042.

BEGIN;

REVOKE SELECT, UPDATE ON TABLE public.sessions FROM authenticated;

COMMIT;
