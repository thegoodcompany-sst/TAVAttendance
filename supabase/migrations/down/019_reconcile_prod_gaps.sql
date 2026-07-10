-- Reverses the real changes of 019_reconcile_prod_gaps.sql (triggers +
-- indexes). The function/view re-pins were formatting-only no-ops and have
-- nothing meaningful to reverse.

DROP TRIGGER IF EXISTS audit_profiles ON profiles;
DROP TRIGGER IF EXISTS audit_classes  ON classes;

DROP INDEX IF EXISTS idx_sessions_session_date;
DROP INDEX IF EXISTS idx_attendance_records_student_id;
DROP INDEX IF EXISTS idx_enrollments_class_id;
DROP INDEX IF EXISTS idx_enrollments_class_id_active;
