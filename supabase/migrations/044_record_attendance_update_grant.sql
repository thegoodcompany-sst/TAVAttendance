-- Migration 044: record the existing production UPDATE privilege needed by
-- authenticated offline attendance upserts.

BEGIN;

GRANT UPDATE ON TABLE public.attendance_records TO authenticated;

DO $$
BEGIN
    ASSERT has_table_privilege(
        'authenticated', 'public.attendance_records', 'UPDATE'
    ), 'authenticated lacks attendance_records UPDATE privilege';
    ASSERT (
        SELECT relrowsecurity
        FROM pg_class
        WHERE oid = 'public.attendance_records'::REGCLASS
    ), 'attendance_records RLS is disabled';
END
$$;

COMMIT;
