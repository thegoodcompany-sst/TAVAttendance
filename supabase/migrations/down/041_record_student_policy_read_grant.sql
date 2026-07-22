-- down/041_record_student_policy_read_grant.sql — reverse of 041.

BEGIN;

REVOKE SELECT ON TABLE public.students FROM authenticated;

COMMIT;
