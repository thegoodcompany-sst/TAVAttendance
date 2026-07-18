-- ============================================================
-- 037 — Retrospective session management
-- ============================================================
-- Feature-flagged staff workflow for creating and correcting sessions before
-- today. Historical attendance uses a dedicated RPC so the ordinary ended-
-- session guard and offline queue remain unchanged.

INSERT INTO feature_flags (key, enabled, description)
VALUES (
    'retrospective_sessions',
    FALSE,
    'Create past class sessions and correct their details and attendance.'
)
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION check_session_not_ended()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    v_session_id UUID := COALESCE(NEW.session_id, OLD.session_id);
BEGIN
    IF EXISTS (
        SELECT 1 FROM sessions
        WHERE id = v_session_id AND ended_at IS NOT NULL
    ) AND COALESCE(current_setting('app.retrospective_attendance_write', TRUE), 'off') <> 'on' THEN
        RAISE EXCEPTION 'Cannot modify attendance for ended session %', v_session_id
            USING ERRCODE = 'TA001';
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE FUNCTION check_retrospective_session_changes()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    v_today DATE := (NOW() AT TIME ZONE 'Asia/Singapore')::DATE;
BEGIN
    IF TG_OP = 'INSERT' AND NEW.session_date < v_today
       AND COALESCE(current_setting('app.retrospective_session_create', TRUE), 'off') <> 'on' THEN
        RAISE EXCEPTION 'past sessions must be created through create_retrospective_session';
    END IF;
    IF TG_OP = 'UPDATE' AND OLD.session_date < v_today
       AND (NEW.class_id IS DISTINCT FROM OLD.class_id
            OR NEW.session_date IS DISTINCT FROM OLD.session_date) THEN
        RAISE EXCEPTION 'historical session class and date are immutable';
    END IF;
    IF TG_OP = 'DELETE' AND OLD.session_date < v_today THEN
        RAISE EXCEPTION 'historical sessions cannot be deleted';
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER enforce_retrospective_session_changes
BEFORE INSERT OR UPDATE OR DELETE ON sessions
FOR EACH ROW EXECUTE FUNCTION check_retrospective_session_changes();

CREATE FUNCTION create_retrospective_session(
    class_id UUID,
    session_date DATE,
    topic TEXT DEFAULT NULL,
    notes TEXT DEFAULT NULL,
    sub_tutor_id UUID DEFAULT NULL
)
RETURNS sessions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_class classes%ROWTYPE;
    v_session sessions%ROWTYPE;
    v_today DATE := (NOW() AT TIME ZONE 'Asia/Singapore')::DATE;
BEGIN
    IF NOT is_feature_enabled('retrospective_sessions') THEN
        RAISE EXCEPTION 'retrospective sessions are disabled';
    END IF;

    SELECT * INTO v_class FROM classes c
    WHERE c.id = create_retrospective_session.class_id;
    IF NOT FOUND OR v_class.is_study_space OR NOT v_class.is_active THEN
        RAISE EXCEPTION 'class is not eligible for retrospective sessions';
    END IF;
    IF NOT (is_admin() OR (is_tutor() AND tutor_owns_class(create_retrospective_session.class_id))) THEN
        RAISE EXCEPTION 'not authorized';
    END IF;
    IF session_date IS NULL OR session_date >= v_today THEN
        RAISE EXCEPTION 'session date must be before today';
    END IF;
    IF notes IS NOT NULL AND BTRIM(notes) <> '' AND NOT is_feature_enabled('session_notes') THEN
        RAISE EXCEPTION 'session notes are disabled';
    END IF;
    IF sub_tutor_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM profiles p WHERE p.id = sub_tutor_id AND p.role = 'tutor'
    ) THEN
        RAISE EXCEPTION 'invalid substitute tutor';
    END IF;
    IF EXISTS (
        SELECT 1 FROM sessions s
        WHERE s.class_id = create_retrospective_session.class_id
          AND s.session_date = create_retrospective_session.session_date
    ) THEN
        RAISE EXCEPTION 'a session already exists for this class and date'
            USING ERRCODE = '23505';
    END IF;

    PERFORM set_config('app.retrospective_session_create', 'on', TRUE);
    INSERT INTO sessions (
        class_id, session_date, topic, notes, sub_tutor_id,
        ended_at, created_by
    ) VALUES (
        create_retrospective_session.class_id,
        create_retrospective_session.session_date,
        NULLIF(BTRIM(create_retrospective_session.topic), ''),
        NULLIF(BTRIM(create_retrospective_session.notes), ''),
        create_retrospective_session.sub_tutor_id,
        NOW(), auth.uid()
    )
    RETURNING * INTO v_session;
    PERFORM set_config('app.retrospective_session_create', 'off', TRUE);

    RETURN v_session;
END;
$$;

CREATE FUNCTION update_retrospective_session(
    session_id UUID,
    topic TEXT DEFAULT NULL,
    notes TEXT DEFAULT NULL,
    sub_tutor_id UUID DEFAULT NULL
)
RETURNS sessions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_session sessions%ROWTYPE;
    v_is_study_space BOOLEAN;
    v_today DATE := (NOW() AT TIME ZONE 'Asia/Singapore')::DATE;
BEGIN
    IF NOT is_feature_enabled('retrospective_sessions') THEN
        RAISE EXCEPTION 'retrospective sessions are disabled';
    END IF;

    SELECT s.* INTO v_session
    FROM sessions s
    WHERE s.id = update_retrospective_session.session_id;
    SELECT c.is_study_space INTO v_is_study_space
    FROM classes c WHERE c.id = v_session.class_id;
    IF NOT FOUND OR v_is_study_space OR v_session.session_date >= v_today THEN
        RAISE EXCEPTION 'session is not eligible for retrospective editing';
    END IF;
    IF NOT (is_admin() OR (is_tutor() AND tutor_owns_class(v_session.class_id))) THEN
        RAISE EXCEPTION 'not authorized';
    END IF;
    IF notes IS NOT NULL AND BTRIM(notes) <> '' AND NOT is_feature_enabled('session_notes') THEN
        RAISE EXCEPTION 'session notes are disabled';
    END IF;
    IF sub_tutor_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM profiles p WHERE p.id = sub_tutor_id AND p.role = 'tutor'
    ) THEN
        RAISE EXCEPTION 'invalid substitute tutor';
    END IF;

    UPDATE sessions s
    SET topic = NULLIF(BTRIM(update_retrospective_session.topic), ''),
        notes = NULLIF(BTRIM(update_retrospective_session.notes), ''),
        sub_tutor_id = update_retrospective_session.sub_tutor_id
    WHERE s.id = update_retrospective_session.session_id
    RETURNING s.* INTO v_session;

    RETURN v_session;
END;
$$;

CREATE FUNCTION get_retrospective_session_roster(session_id UUID)
RETURNS TABLE (
    student_id UUID,
    full_name TEXT,
    attendance_id UUID,
    status TEXT,
    marked_at TIMESTAMPTZ,
    notes TEXT,
    late_reason TEXT,
    avatar_url TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_class_id UUID;
    v_session_date DATE;
    v_is_study_space BOOLEAN;
    v_today DATE := (NOW() AT TIME ZONE 'Asia/Singapore')::DATE;
BEGIN
    IF NOT is_feature_enabled('retrospective_sessions') THEN
        RAISE EXCEPTION 'retrospective sessions are disabled';
    END IF;

    SELECT s.class_id, s.session_date, c.is_study_space
    INTO v_class_id, v_session_date, v_is_study_space
    FROM sessions s JOIN classes c ON c.id = s.class_id
    WHERE s.id = get_retrospective_session_roster.session_id;
    IF NOT FOUND OR v_is_study_space OR v_session_date >= v_today THEN
        RAISE EXCEPTION 'session is not eligible for retrospective editing';
    END IF;
    IF NOT (is_admin() OR (is_tutor() AND tutor_owns_class(v_class_id))) THEN
        RAISE EXCEPTION 'not authorized';
    END IF;

    RETURN QUERY
    WITH roster_students AS (
        SELECT e.student_id
        FROM enrollments e
        WHERE e.class_id = v_class_id
          AND (e.enrolled_at AT TIME ZONE 'Asia/Singapore')::DATE <= v_session_date
          AND (e.unenrolled_at IS NULL
               OR (e.unenrolled_at AT TIME ZONE 'Asia/Singapore')::DATE >= v_session_date)
        UNION
        SELECT ar.student_id
        FROM attendance_records ar
        WHERE ar.session_id = get_retrospective_session_roster.session_id
    )
    SELECT st.id, st.full_name, ar.id, ar.status, ar.marked_at,
           ar.notes, ar.late_reason, st.avatar_url
    FROM roster_students rs
    JOIN students st ON st.id = rs.student_id
    LEFT JOIN attendance_records ar
      ON ar.session_id = get_retrospective_session_roster.session_id
     AND ar.student_id = st.id
    ORDER BY st.full_name;
END;
$$;

CREATE FUNCTION mark_retrospective_attendance(
    session_id UUID,
    student_id UUID,
    status TEXT
)
RETURNS attendance_records
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_session sessions%ROWTYPE;
    v_is_study_space BOOLEAN;
    v_record attendance_records%ROWTYPE;
    v_today DATE := (NOW() AT TIME ZONE 'Asia/Singapore')::DATE;
BEGIN
    IF NOT is_feature_enabled('retrospective_sessions') THEN
        RAISE EXCEPTION 'retrospective sessions are disabled';
    END IF;

    SELECT s.* INTO v_session
    FROM sessions s
    WHERE s.id = mark_retrospective_attendance.session_id;
    SELECT c.is_study_space INTO v_is_study_space
    FROM classes c WHERE c.id = v_session.class_id;
    IF NOT FOUND OR v_is_study_space OR v_session.session_date >= v_today THEN
        RAISE EXCEPTION 'session is not eligible for retrospective editing';
    END IF;
    IF NOT (is_admin() OR (is_tutor() AND tutor_owns_class(v_session.class_id))) THEN
        RAISE EXCEPTION 'not authorized';
    END IF;
    IF status NOT IN ('present', 'late', 'absent', 'excused') THEN
        RAISE EXCEPTION 'invalid attendance status';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM students st
        WHERE st.id = mark_retrospective_attendance.student_id AND st.is_active
    ) THEN
        RAISE EXCEPTION 'student is not active or visible';
    END IF;
    IF is_tutor() AND NOT EXISTS (
        SELECT 1
        FROM enrollments e
        JOIN class_tutor_assignments cta ON cta.class_id = e.class_id
        WHERE e.student_id = mark_retrospective_attendance.student_id
          AND e.is_active
          AND cta.tutor_id = auth.uid()
          AND (cta.assigned_until IS NULL OR cta.assigned_until >= CURRENT_DATE)
    ) THEN
        RAISE EXCEPTION 'student is not visible';
    END IF;

    PERFORM set_config('app.retrospective_attendance_write', 'on', TRUE);
    INSERT INTO attendance_records (
        session_id, student_id, status, marked_by, marked_at, client_mutation_id
    ) VALUES (
        mark_retrospective_attendance.session_id,
        mark_retrospective_attendance.student_id,
        mark_retrospective_attendance.status,
        auth.uid(), NOW(), gen_random_uuid()::TEXT
    )
    ON CONFLICT ON CONSTRAINT attendance_records_session_id_student_id_key DO UPDATE
    SET status = EXCLUDED.status,
        marked_by = EXCLUDED.marked_by,
        marked_at = NOW(),
        client_mutation_id = EXCLUDED.client_mutation_id
    RETURNING * INTO v_record;
    PERFORM set_config('app.retrospective_attendance_write', 'off', TRUE);

    RETURN v_record;
END;
$$;

REVOKE EXECUTE ON FUNCTION create_retrospective_session(UUID, DATE, TEXT, TEXT, UUID) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION update_retrospective_session(UUID, TEXT, TEXT, UUID) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION get_retrospective_session_roster(UUID) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION mark_retrospective_attendance(UUID, UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION create_retrospective_session(UUID, DATE, TEXT, TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION update_retrospective_session(UUID, TEXT, TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_retrospective_session_roster(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION mark_retrospective_attendance(UUID, UUID, TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';

DO $$
BEGIN
    ASSERT EXISTS (
        SELECT 1 FROM feature_flags WHERE key = 'retrospective_sessions' AND enabled = FALSE
    ), 'retrospective_sessions flag missing or enabled';
    ASSERT to_regprocedure('create_retrospective_session(uuid,date,text,text,uuid)') IS NOT NULL,
           'create_retrospective_session missing';
    ASSERT to_regprocedure('update_retrospective_session(uuid,text,text,uuid)') IS NOT NULL,
           'update_retrospective_session missing';
    ASSERT to_regprocedure('get_retrospective_session_roster(uuid)') IS NOT NULL,
           'get_retrospective_session_roster missing';
    ASSERT to_regprocedure('mark_retrospective_attendance(uuid,uuid,text)') IS NOT NULL,
           'mark_retrospective_attendance missing';
    ASSERT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgrelid = 'sessions'::regclass
          AND tgname = 'enforce_retrospective_session_changes'
          AND NOT tgisinternal
    ), 'retrospective session immutability trigger missing';
    ASSERT NOT has_function_privilege('anon',
        'create_retrospective_session(uuid,date,text,text,uuid)', 'EXECUTE'),
        'anon can create retrospective sessions';
    ASSERT has_function_privilege('authenticated',
        'mark_retrospective_attendance(uuid,uuid,text)', 'EXECUTE'),
        'authenticated cannot mark retrospective attendance';
    ASSERT (SELECT BOOL_AND(p.prosecdef)
            FROM pg_proc p
            WHERE p.proname IN (
                'create_retrospective_session', 'update_retrospective_session',
                'get_retrospective_session_roster', 'mark_retrospective_attendance'
            )), 'retrospective RPC lost SECURITY DEFINER';
    ASSERT (SELECT BOOL_AND(
                COALESCE('search_path=public, pg_temp' = ANY(p.proconfig), FALSE)
            ) FROM pg_proc p
            WHERE p.proname IN (
                'create_retrospective_session', 'update_retrospective_session',
                'get_retrospective_session_roster', 'mark_retrospective_attendance'
            )), 'retrospective RPC search_path is not pinned';
END $$;
