-- down/043_record_attendance_policy_grants.sql — reverse of 043.

BEGIN;

REVOKE SELECT, INSERT ON TABLE public.attendance_records FROM authenticated;

COMMIT;
