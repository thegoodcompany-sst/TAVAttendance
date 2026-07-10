-- down/021_notify_parent_trigger.sql — reverse of 021.
-- Leaves the pg_net extension installed (harmless; other consumers may exist).

DROP TRIGGER IF EXISTS trg_notify_parent ON attendance_records;
DROP FUNCTION IF EXISTS notify_parent_on_attendance();
