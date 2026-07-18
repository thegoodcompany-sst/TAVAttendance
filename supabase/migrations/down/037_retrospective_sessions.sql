DROP FUNCTION IF EXISTS mark_retrospective_attendance(UUID, UUID, TEXT);
DROP FUNCTION IF EXISTS get_retrospective_session_roster(UUID);
DROP FUNCTION IF EXISTS update_retrospective_session(UUID, TEXT, TEXT, UUID);
DROP FUNCTION IF EXISTS create_retrospective_session(UUID, DATE, TEXT, TEXT, UUID);
DROP TRIGGER IF EXISTS enforce_retrospective_session_changes ON sessions;
DROP FUNCTION IF EXISTS check_retrospective_session_changes();

CREATE OR REPLACE FUNCTION check_session_not_ended()
RETURNS TRIGGER LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_session_id UUID := COALESCE(NEW.session_id, OLD.session_id);
BEGIN
    IF EXISTS (
        SELECT 1 FROM sessions
        WHERE id = v_session_id AND ended_at IS NOT NULL
    ) THEN
        RAISE EXCEPTION 'Cannot modify attendance for ended session %', v_session_id
            USING ERRCODE = 'TA001';
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$;

DELETE FROM feature_flags WHERE key = 'retrospective_sessions';
NOTIFY pgrst, 'reload schema';
