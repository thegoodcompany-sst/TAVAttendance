-- Restores the pre-055 schema/API. Rows deleted by the forward data migration
-- cannot be reconstructed; restore them from backup if this rollback is used.

ALTER TABLE attendance_records
    DROP CONSTRAINT IF EXISTS attendance_records_status_check,
    ADD CONSTRAINT attendance_records_status_check
        CHECK (status IN ('present', 'absent', 'late', 'excused')) NOT VALID;
ALTER TABLE attendance_records
    VALIDATE CONSTRAINT attendance_records_status_check;

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
BEGIN
    IF COALESCE(current_setting('app.suppress_audit', TRUE), 'off') = 'on' THEN
        RETURN COALESCE(NEW, OLD);
    END IF;
    IF TG_OP = 'DELETE' THEN
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
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.enforce_attendance_write_integrity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_session_date DATE;
    v_class_id UUID;
    v_class_active BOOLEAN;
    v_study_space BOOLEAN;
    v_student_active BOOLEAN;
    v_historical BOOLEAN := COALESCE(
        current_setting('app.retrospective_attendance_write', TRUE), 'off'
    ) = 'on';
BEGIN
    IF COALESCE(current_setting('app.suppress_audit', TRUE), 'off') = 'on' THEN
        RETURN NEW;
    END IF;
    IF TG_OP = 'UPDATE' AND (
        NEW.id IS DISTINCT FROM OLD.id
        OR NEW.session_id IS DISTINCT FROM OLD.session_id
        OR NEW.student_id IS DISTINCT FROM OLD.student_id
    ) THEN
        RAISE EXCEPTION 'attendance identity fields are immutable'
            USING ERRCODE = '23514';
    END IF;

    NEW.notes := NULLIF(BTRIM(NEW.notes), '');
    NEW.late_reason := NULLIF(BTRIM(NEW.late_reason), '');
    IF NEW.status <> 'late' THEN NEW.late_reason := NULL; END IF;
    IF NEW.notes IS NOT NULL AND char_length(NEW.notes) > 4000 THEN
        RAISE EXCEPTION 'attendance notes are too long' USING ERRCODE = '22001';
    END IF;
    IF NEW.late_reason IS NOT NULL AND char_length(NEW.late_reason) > 1000 THEN
        RAISE EXCEPTION 'late reason is too long' USING ERRCODE = '22001';
    END IF;
    IF COALESCE(NEW.late_reason, '') ~* '\m[STFGM][0-9]{7}[A-Z]\M' THEN
        RAISE EXCEPTION 'Late reason appears to contain an NRIC/FIN.'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.client_mutation_id IS NOT NULL THEN
        NEW.client_mutation_id := BTRIM(NEW.client_mutation_id);
    END IF;
    IF auth.uid() IS NOT NULL AND (
        NEW.client_mutation_id IS NULL
        OR NEW.client_mutation_id = ''
        OR char_length(NEW.client_mutation_id) > 128
    ) THEN
        RAISE EXCEPTION 'invalid attendance mutation identifier'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.client_mutation_id IS NOT NULL
       AND (TG_OP = 'INSERT'
            OR NEW.client_mutation_id IS DISTINCT FROM OLD.client_mutation_id)
       AND EXISTS (
            SELECT 1 FROM attendance_mutation_receipts receipt
            WHERE receipt.mutation_id = NEW.client_mutation_id
       ) THEN
        RAISE EXCEPTION 'attendance mutation identifier collision'
            USING ERRCODE = '23505';
    END IF;

    IF auth.uid() IS NOT NULL THEN NEW.marked_by := auth.uid(); END IF;
    NEW.marked_at := clock_timestamp();
    SELECT s.session_date, s.class_id, c.is_active, c.is_study_space,
           st.is_active
    INTO v_session_date, v_class_id, v_class_active, v_study_space,
         v_student_active
    FROM sessions s
    JOIN classes c ON c.id = s.class_id
    JOIN students st ON st.id = NEW.student_id
    WHERE s.id = NEW.session_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'attendance session or student does not exist'
            USING ERRCODE = '23503';
    END IF;

    IF v_study_space THEN
        IF NOT v_class_active
           OR NOT v_student_active
           OR NEW.status NOT IN ('present', 'excused')
           OR NOT is_feature_enabled('study_space_tracking')
           OR (auth.uid() IS NOT NULL AND NOT is_admin()) THEN
            RAISE EXCEPTION 'invalid Study Space attendance'
                USING ERRCODE = '23514';
        END IF;
    ELSIF NOT EXISTS (
        SELECT 1 FROM enrollments e
        WHERE e.class_id = v_class_id
          AND e.student_id = NEW.student_id
          AND (e.enrolled_at AT TIME ZONE 'Asia/Singapore')::DATE <= v_session_date
          AND (e.unenrolled_at IS NULL
               OR (e.unenrolled_at AT TIME ZONE 'Asia/Singapore')::DATE >= v_session_date)
    ) THEN
        RAISE EXCEPTION 'student was not enrolled for this session'
            USING ERRCODE = '23514';
    ELSIF NOT v_historical AND (NOT v_class_active OR NOT v_student_active) THEN
        RAISE EXCEPTION 'inactive class or student cannot receive current attendance'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_attendance(records JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    rec JSONB;
    v_id UUID;
    v_mutation_id TEXT;
    synced INTEGER := 0;
    skipped INTEGER := 0;
    blocked INTEGER := 0;
BEGIN
    IF auth.uid() IS NULL OR (NOT is_admin() AND NOT is_tutor()) THEN
        RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
    END IF;
    IF jsonb_typeof(records) IS DISTINCT FROM 'array'
       OR jsonb_array_length(records) > 500 THEN
        RAISE EXCEPTION 'invalid attendance sync batch' USING ERRCODE = '22023';
    END IF;

    PERFORM set_config('app.attendance_offline_sync', 'on', TRUE);
    FOR rec IN SELECT * FROM jsonb_array_elements(records)
    LOOP
        v_mutation_id := NULLIF(BTRIM(rec->>'client_mutation_id'), '');
        IF v_mutation_id IS NULL OR char_length(v_mutation_id) > 128 THEN
            RAISE EXCEPTION 'invalid attendance mutation identifier'
                USING ERRCODE = '23514';
        END IF;
        PERFORM pg_advisory_xact_lock(hashtextextended(v_mutation_id, 1));
        IF attendance_mutation_is_replay(
            v_mutation_id,
            (rec->>'session_id')::UUID,
            (rec->>'student_id')::UUID
        ) THEN
            skipped := skipped + 1;
            CONTINUE;
        END IF;
        BEGIN
            INSERT INTO attendance_records (
                session_id, student_id, status, notes,
                client_mutation_id, marked_by, marked_at
            ) VALUES (
                (rec->>'session_id')::UUID,
                (rec->>'student_id')::UUID,
                rec->>'status', rec->>'notes', v_mutation_id,
                auth.uid(), clock_timestamp()
            )
            ON CONFLICT (session_id, student_id) DO UPDATE
            SET status = EXCLUDED.status,
                notes = EXCLUDED.notes,
                marked_by = EXCLUDED.marked_by,
                marked_at = EXCLUDED.marked_at,
                client_mutation_id = EXCLUDED.client_mutation_id
            RETURNING id INTO v_id;
            synced := synced + 1;
        EXCEPTION WHEN SQLSTATE 'TA001' THEN
            blocked := blocked + 1;
        END;
    END LOOP;
    PERFORM set_config('app.attendance_offline_sync', 'off', TRUE);
    RETURN jsonb_build_object(
        'synced', synced,
        'skipped', skipped,
        'blocked_ended_session', blocked
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_retrospective_attendance(
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
    SELECT s.* INTO v_session FROM sessions s
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
    IF NOT student_is_enrolled_for_session(
        mark_retrospective_attendance.session_id,
        mark_retrospective_attendance.student_id
    ) THEN
        RAISE EXCEPTION 'student was not enrolled for this session';
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
    RETURN v_record;
END;
$$;

DROP VIEW public.attendance_summary;
CREATE VIEW public.attendance_summary
WITH (security_invoker = true)
AS
SELECT ar.student_id,
       st.full_name AS student_name,
       se.class_id,
       c.name AS class_name,
       COUNT(*) AS total_sessions,
       COUNT(*) FILTER (WHERE ar.status = 'present') AS present_count,
       COUNT(*) FILTER (WHERE ar.status = 'late') AS late_count,
       COUNT(*) FILTER (WHERE ar.status = 'absent') AS absent_count,
       COUNT(*) FILTER (WHERE ar.status = 'excused') AS excused_count,
       ROUND(
           100.0 * COUNT(*) FILTER (
               WHERE ar.status IN ('present', 'late', 'excused')
           ) / NULLIF(COUNT(*), 0),
           1
       ) AS attendance_pct
FROM attendance_records ar
JOIN students st ON st.id = ar.student_id
JOIN sessions se ON se.id = ar.session_id
JOIN classes c ON c.id = se.class_id
WHERE st.is_active = TRUE
  AND c.is_active = TRUE
  AND c.is_study_space = FALSE
GROUP BY ar.student_id, st.full_name, se.class_id, c.name;
REVOKE ALL ON public.attendance_summary FROM PUBLIC, anon;
GRANT SELECT ON public.attendance_summary TO authenticated, service_role;

DROP FUNCTION public.class_punctuality(UUID, DATE, DATE);
CREATE FUNCTION public.class_punctuality(
    p_class_id UUID, p_from DATE, p_to DATE
)
RETURNS TABLE (
    present_count BIGINT, late_count BIGINT, absent_count BIGINT,
    excused_count BIGINT, total_count BIGINT, on_time_rate NUMERIC
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT (is_admin() OR tutor_owns_class(p_class_id))
       OR NOT EXISTS (
            SELECT 1 FROM classes c
            WHERE c.id = p_class_id AND c.is_study_space = FALSE
       ) THEN
        RAISE EXCEPTION 'not authorized';
    END IF;
    RETURN QUERY
    SELECT COUNT(*) FILTER (WHERE ar.status = 'present'),
           COUNT(*) FILTER (WHERE ar.status = 'late'),
           COUNT(*) FILTER (WHERE ar.status = 'absent'),
           COUNT(*) FILTER (WHERE ar.status = 'excused'),
           COUNT(*),
           CASE WHEN COUNT(*) = 0 THEN NULL
                ELSE ROUND(
                    COUNT(*) FILTER (WHERE ar.status = 'present')::NUMERIC
                    / COUNT(*), 4
                )
           END
    FROM attendance_records ar
    JOIN sessions s ON s.id = ar.session_id
    WHERE s.class_id = p_class_id
      AND s.session_date BETWEEN p_from AND p_to;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.class_punctuality(UUID, DATE, DATE)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.class_punctuality(UUID, DATE, DATE)
    TO authenticated, service_role;

DROP FUNCTION public.get_parent_attendance_summary(UUID);
CREATE FUNCTION public.get_parent_attendance_summary(p_student_id UUID)
RETURNS TABLE (
    class_id UUID, class_name TEXT, total_sessions BIGINT,
    present_count BIGINT, late_count BIGINT, absent_count BIGINT,
    excused_count BIGINT, attendance_pct NUMERIC
)
LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT is_parent()
       OR NOT is_feature_enabled('parent_portal')
       OR NOT parent_owns_student(p_student_id) THEN
        RAISE EXCEPTION 'not authorized';
    END IF;
    RETURN QUERY
    SELECT s.class_id, c.name, COUNT(*),
           COUNT(*) FILTER (WHERE ar.status = 'present'),
           COUNT(*) FILTER (WHERE ar.status = 'late'),
           COUNT(*) FILTER (WHERE ar.status = 'absent'),
           COUNT(*) FILTER (WHERE ar.status = 'excused'),
           ROUND(
               100.0 * COUNT(*) FILTER (
                   WHERE ar.status IN ('present', 'late', 'excused')
               ) / NULLIF(COUNT(*), 0), 1
           )
    FROM attendance_records ar
    JOIN students st ON st.id = ar.student_id
    JOIN sessions s ON s.id = ar.session_id
    JOIN classes c ON c.id = s.class_id
    WHERE ar.student_id = p_student_id
      AND st.is_active = TRUE
      AND c.is_active = TRUE
      AND c.is_study_space = FALSE
    GROUP BY s.class_id, c.name
    ORDER BY c.name;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.get_parent_attendance_summary(UUID)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_parent_attendance_summary(UUID)
    TO authenticated, service_role;

DROP TRIGGER IF EXISTS archive_deleted_attendance_receipt ON attendance_records;
DROP FUNCTION IF EXISTS public.archive_deleted_attendance_receipt();
DROP FUNCTION IF EXISTS public.clear_attendance(UUID, UUID, TEXT);

NOTIFY pgrst, 'reload schema';
