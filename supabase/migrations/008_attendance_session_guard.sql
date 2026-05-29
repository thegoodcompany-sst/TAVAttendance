-- Prevent direct attendance writes once a session has been ended.
-- The sync_attendance RPC is SECURITY DEFINER and bypasses row-level triggers
-- when invoked as postgres; direct client writes are blocked.

CREATE OR REPLACE FUNCTION check_session_not_ended()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM sessions
    WHERE id = NEW.session_id AND ended_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Cannot modify attendance for ended session %', NEW.session_id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER enforce_attendance_on_open_session
BEFORE INSERT OR UPDATE ON attendance_records
FOR EACH ROW EXECUTE FUNCTION check_session_not_ended();
