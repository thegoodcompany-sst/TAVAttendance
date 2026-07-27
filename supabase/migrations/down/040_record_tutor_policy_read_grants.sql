-- down/040_record_tutor_policy_read_grants.sql — reverse of 040.

BEGIN;

REVOKE SELECT ON TABLE public.enrollments FROM authenticated;
REVOKE SELECT ON TABLE public.class_tutor_assignments FROM authenticated;

COMMIT;
