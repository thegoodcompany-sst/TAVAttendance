-- Reverses 018_restore_substitute_policies.sql (returns prod to the pre-018
-- drifted state: no substitute-tutor policies).

DROP POLICY IF EXISTS "substitute_can_read_session"    ON sessions;
DROP POLICY IF EXISTS "substitute_can_mark_attendance" ON attendance_records;
