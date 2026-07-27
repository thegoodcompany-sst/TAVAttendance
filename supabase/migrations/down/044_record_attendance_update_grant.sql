-- down/044_record_attendance_update_grant.sql — reverse of 044.

BEGIN;

REVOKE UPDATE ON TABLE public.attendance_records FROM authenticated;

COMMIT;
