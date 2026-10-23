-- Restore the pre-062 attendance guard and clear helper.

CREATE OR REPLACE FUNCTION public.check_session_not_ended()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    v_session_id UUID := COALESCE(NEW.session_id, OLD.session_id);
    v_session_date DATE;
    v_ended_at TIMESTAMPTZ;
    v_today DATE := (NOW() AT TIME ZONE 'Asia/Singapore')::DATE;
    v_retrospective BOOLEAN := COALESCE(
        current_setting('app.retrospective_attendance_write', TRUE), 'off'
    ) = 'on';
    v_offline BOOLEAN := COALESCE(
        current_setting('app.attendance_offline_sync', TRUE), 'off'
    ) = 'on';
    v_clear BOOLEAN := COALESCE(
        current_setting('app.attendance_clear', TRUE), 'off'
    ) = 'on';
BEGIN
    IF COALESCE(current_setting('app.suppress_audit', TRUE), 'off') = 'on' THEN
        RETURN COALESCE(NEW, OLD);
    END IF;
    IF TG_OP = 'DELETE' AND NOT v_clear THEN
        RAISE EXCEPTION 'attendance rows cannot be deleted directly'
            USING ERRCODE = '42501';
    END IF;

    SELECT session_date, ended_at INTO v_session_date, v_ended_at
    FROM sessions WHERE id = v_session_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'attendance session does not exist'
            USING ERRCODE = '23503';
    END IF;
    IF v_ended_at IS NOT NULL AND NOT v_retrospective THEN
        RAISE EXCEPTION 'Cannot modify attendance for ended session %', v_session_id
            USING ERRCODE = 'TA001';
    END IF;
    IF v_session_date > v_today THEN
        RAISE EXCEPTION 'future attendance is not allowed'
            USING ERRCODE = '23514';
    END IF;
    IF v_session_date < v_today AND NOT v_retrospective THEN
        IF NOT v_offline OR v_session_date < v_today - 7 THEN
            RAISE EXCEPTION 'historical attendance requires the dedicated workflow'
                USING ERRCODE = '42501';
        END IF;
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE OR REPLACE FUNCTION public.apply_attendance_clear(
    p_session_id UUID,
    p_student_id UUID,
    p_client_mutation_id TEXT,
    p_check_observed BOOLEAN,
    p_observed_marked_at TIMESTAMPTZ
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_session sessions%ROWTYPE;
    v_class classes%ROWTYPE;
    v_today DATE := (NOW() AT TIME ZONE 'Asia/Singapore')::DATE;
    v_actor UUID := auth.uid();
    v_mutation_id TEXT := NULLIF(BTRIM(p_client_mutation_id), '');
    v_offline BOOLEAN := COALESCE(
        current_setting('app.attendance_offline_sync', TRUE), 'off'
    ) = 'on';
    v_retrospective BOOLEAN := COALESCE(
        current_setting('app.retrospective_attendance_write', TRUE), 'off'
    ) = 'on';
BEGIN
    IF v_actor IS NULL OR (NOT is_admin() AND NOT is_tutor()) THEN
        RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
    END IF;
    IF v_mutation_id IS NULL OR char_length(v_mutation_id) > 128 THEN
        RAISE EXCEPTION 'invalid attendance mutation identifier'
            USING ERRCODE = '23514';
    END IF;

    -- Reuse the transaction-local mutation-receipt capability established by
    -- sync_attendance. The date-window branch continues to use v_offline,
    -- captured before this internal capability is enabled.
    PERFORM set_config('app.attendance_offline_sync', 'on', TRUE);
    PERFORM pg_advisory_xact_lock(hashtextextended(v_mutation_id, 1));
    IF attendance_mutation_is_replay(
        v_mutation_id, p_session_id, p_student_id
    ) THEN
        RETURN TRUE;
    END IF;

    SELECT * INTO v_session FROM sessions WHERE id = p_session_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'attendance session does not exist'
            USING ERRCODE = '23503';
    END IF;
    SELECT * INTO v_class FROM classes WHERE id = v_session.class_id;

    IF NOT (
        is_admin()
        OR (is_tutor() AND tutor_owns_class(v_session.class_id))
        OR substitute_covers_session(p_session_id)
    ) THEN
        RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
    END IF;
    IF v_class.is_study_space THEN
        IF NOT is_admin()
           OR NOT is_feature_enabled('study_space_tracking')
           OR NOT EXISTS (
                SELECT 1 FROM students
                WHERE id = p_student_id AND is_active = TRUE
           ) THEN
            RAISE EXCEPTION 'invalid Study Space attendance'
                USING ERRCODE = '23514';
        END IF;
    ELSIF NOT student_is_enrolled_for_session(p_session_id, p_student_id) THEN
        RAISE EXCEPTION 'student was not enrolled for this session'
            USING ERRCODE = '23514';
    END IF;

    IF v_retrospective THEN
        IF NOT is_feature_enabled('retrospective_sessions')
           OR v_class.is_study_space
           OR v_session.session_date >= v_today THEN
            RAISE EXCEPTION 'session is not eligible for retrospective editing'
                USING ERRCODE = '42501';
        END IF;
    ELSIF v_offline THEN
        IF v_session.ended_at IS NOT NULL
           OR v_session.session_date < v_today - 7
           OR v_session.session_date > v_today THEN
            RAISE EXCEPTION 'offline attendance clear is outside the allowed window'
                USING ERRCODE = 'TA001';
        END IF;
    ELSIF v_session.ended_at IS NOT NULL
       OR v_session.session_date <> v_today THEN
        RAISE EXCEPTION 'attendance clear requires today''s open session'
            USING ERRCODE = '42501';
    END IF;

    PERFORM set_config('app.attendance_clear', 'on', TRUE);
    IF p_check_observed AND p_observed_marked_at IS NULL THEN
        -- An observed-empty clear is a no-op. Never delete a concurrent insert.
        IF EXISTS (
            SELECT 1 FROM attendance_records
            WHERE session_id = p_session_id AND student_id = p_student_id
        ) THEN
            RETURN FALSE;
        END IF;
    ELSE
        DELETE FROM attendance_records
        WHERE session_id = p_session_id AND student_id = p_student_id
          AND (NOT p_check_observed OR marked_at = p_observed_marked_at);
        IF p_check_observed AND NOT FOUND THEN
            RETURN FALSE;
        END IF;
    END IF;

    INSERT INTO attendance_mutation_receipts (
        mutation_id, session_id, student_id, actor_id, accepted_at
    ) VALUES (
        v_mutation_id, p_session_id, p_student_id, v_actor, clock_timestamp()
    );
    RETURN TRUE;
END;
$$;

NOTIFY pgrst, 'reload schema';
