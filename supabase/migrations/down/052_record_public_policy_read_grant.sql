-- down/052_record_public_policy_read_grant.sql — reverse of 052.

BEGIN;

REVOKE SELECT ON TABLE public.policy_documents FROM anon;

COMMIT;
