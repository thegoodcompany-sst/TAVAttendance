-- down/050_record_student_update_grant.sql — reverse of 050.

BEGIN;

REVOKE UPDATE ON TABLE public.students FROM authenticated;

COMMIT;
