-- Absent: informed vs did not inform.
--
-- Storage is status = 'absent' plus a nullable companion boolean
-- (mirrors late_reason). Not a new status value.
--   TRUE  → Absent (informed)
--   FALSE → Absent (no notice)
--   NULL  → Absent (legacy / unspecified / non-iOS clients)
--
-- Deliberately NOT changed in this migration (intentional, not an oversight):
--   class_punctuality
--   get_parent_attendance_summary
--   get_parent_attendance_history
--   get_roster_for_date
--   _anonymise_student
--   supabase/functions/notify-parent/payload.ts
-- absence_informed is an attendance fact of the same category as status
-- (which anonymisation retains), not free-text personal data.

ALTER TABLE attendance_records
    ADD COLUMN IF NOT EXISTS absence_informed BOOLEAN;

ALTER TABLE attendance_records
    DROP CONSTRAINT IF EXISTS attendance_records_absence_informed_check,
    ADD CONSTRAINT attendance_records_absence_informed_check
        CHECK (absence_informed IS NULL OR status = 'absent') NOT VALID;
ALTER TABLE attendance_records
    VALIDATE CONSTRAINT attendance_records_absence_informed_check;

-- Null the flag whenever status is not absent (same pattern as late_reason).
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
    IF NEW.status <> 'absent' THEN NEW.absence_informed := NULL; END IF;

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
           OR NEW.status <> 'present'
           OR NOT is_feature_enabled('study_space_tracking')
           OR (auth.uid() IS NOT NULL AND NOT is_admin()) THEN
            RAISE EXCEPTION 'invalid Study Space attendance'
                USING ERRCODE = '23514';
        END IF;
    ELSIF NOT EXISTS (
        SELECT 1
        FROM enrollments e
        WHERE e.class_id = v_class_id
          AND e.student_id = NEW.student_id
          AND (e.enrolled_at AT TIME ZONE 'Asia/Singapore')::DATE
                <= v_session_date
          AND (
                e.unenrolled_at IS NULL
                OR (e.unenrolled_at AT TIME ZONE 'Asia/Singapore')::DATE
                    >= v_session_date
              )
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

-- Offline sync must carry absence_informed (do not inherit late_reason's hole).
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
            IF rec->'status' IS NULL OR rec->'status' = 'null'::JSONB THEN
                PERFORM clear_attendance(
                    (rec->>'session_id')::UUID,
                    (rec->>'student_id')::UUID,
                    v_mutation_id
                );
            ELSE
                IF rec->>'status' NOT IN ('present', 'late', 'absent') THEN
                    RAISE EXCEPTION 'invalid attendance status'
                        USING ERRCODE = '23514';
                END IF;
                INSERT INTO attendance_records (
                    session_id, student_id, status, notes, absence_informed,
                    client_mutation_id, marked_by, marked_at
                ) VALUES (
                    (rec->>'session_id')::UUID,
                    (rec->>'student_id')::UUID,
                    rec->>'status',
                    rec->>'notes',
                    (rec->>'absence_informed')::BOOLEAN,
                    v_mutation_id,
                    auth.uid(),
                    clock_timestamp()
                )
                ON CONFLICT (session_id, student_id) DO UPDATE
                SET status = EXCLUDED.status,
                    notes = EXCLUDED.notes,
                    absence_informed = EXCLUDED.absence_informed,
                    marked_by = EXCLUDED.marked_by,
                    marked_at = EXCLUDED.marked_at,
                    client_mutation_id = EXCLUDED.client_mutation_id
                RETURNING id INTO v_id;
            END IF;
            synced := synced + 1;
        EXCEPTION
            WHEN SQLSTATE 'TA001' THEN
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

GRANT EXECUTE ON FUNCTION public.sync_attendance(JSONB)
    TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.sync_attendance(JSONB) FROM PUBLIC, anon;

-- DROP first: adding a parameter creates an overload; PostgREST would hit PGRST203.
DROP FUNCTION IF EXISTS public.mark_retrospective_attendance(UUID, UUID, TEXT);

CREATE OR REPLACE FUNCTION public.mark_retrospective_attendance(
    session_id UUID,
    student_id UUID,
    status TEXT,
    absence_informed BOOLEAN DEFAULT NULL
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
    IF status IS NOT NULL AND status NOT IN ('present', 'late', 'absent') THEN
        RAISE EXCEPTION 'invalid attendance status';
    END IF;
    IF NOT student_is_enrolled_for_session(
        mark_retrospective_attendance.session_id,
        mark_retrospective_attendance.student_id
    ) THEN
        RAISE EXCEPTION 'student was not enrolled for this session';
    END IF;

    PERFORM set_config('app.retrospective_attendance_write', 'on', TRUE);
    IF status IS NULL THEN
        PERFORM clear_attendance(
            mark_retrospective_attendance.session_id,
            mark_retrospective_attendance.student_id,
            gen_random_uuid()::TEXT
        );
        RETURN NULL;
    END IF;

    INSERT INTO attendance_records (
        session_id, student_id, status, absence_informed,
        marked_by, marked_at, client_mutation_id
    ) VALUES (
        mark_retrospective_attendance.session_id,
        mark_retrospective_attendance.student_id,
        mark_retrospective_attendance.status,
        mark_retrospective_attendance.absence_informed,
        auth.uid(), NOW(), gen_random_uuid()::TEXT
    )
    ON CONFLICT ON CONSTRAINT attendance_records_session_id_student_id_key DO UPDATE
    SET status = EXCLUDED.status,
        absence_informed = EXCLUDED.absence_informed,
        marked_by = EXCLUDED.marked_by,
        marked_at = NOW(),
        client_mutation_id = EXCLUDED.client_mutation_id
    RETURNING * INTO v_record;

    RETURN v_record;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.mark_retrospective_attendance(UUID, UUID, TEXT, BOOLEAN)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_retrospective_attendance(UUID, UUID, TEXT, BOOLEAN)
    TO authenticated;

-- Roster projections: RETURNS TABLE shape change requires DROP + re-grant.
DROP FUNCTION IF EXISTS public.get_session_roster(UUID);

CREATE FUNCTION public.get_session_roster(p_session_id UUID)
RETURNS TABLE (
    student_id UUID,
    full_name TEXT,
    attendance_id UUID,
    status TEXT,
    marked_at TIMESTAMPTZ,
    notes TEXT,
    late_reason TEXT,
    absence_informed BOOLEAN,
    avatar_url TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM sessions s
        WHERE s.id = p_session_id
          AND (
                is_admin()
                OR (is_tutor() AND tutor_owns_class(s.class_id))
                OR substitute_covers_session(s.id)
              )
    ) THEN
        RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT st.id, st.full_name, ar.id, ar.status, ar.marked_at,
           ar.notes, ar.late_reason, ar.absence_informed, st.avatar_url
    FROM sessions se
    JOIN enrollments e
      ON e.class_id = se.class_id
     AND (e.enrolled_at AT TIME ZONE 'Asia/Singapore')::DATE <= se.session_date
     AND (
            e.unenrolled_at IS NULL
            OR (e.unenrolled_at AT TIME ZONE 'Asia/Singapore')::DATE
                >= se.session_date
         )
    JOIN students st ON st.id = e.student_id AND st.is_active
    LEFT JOIN attendance_records ar
      ON ar.session_id = se.id AND ar.student_id = st.id
    WHERE se.id = p_session_id
    ORDER BY st.full_name;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_session_roster(UUID)
    FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_session_roster(UUID) TO authenticated;

DROP FUNCTION IF EXISTS public.get_retrospective_session_roster(UUID);

CREATE FUNCTION public.get_retrospective_session_roster(session_id UUID)
RETURNS TABLE (
    student_id UUID,
    full_name TEXT,
    attendance_id UUID,
    status TEXT,
    marked_at TIMESTAMPTZ,
    notes TEXT,
    late_reason TEXT,
    absence_informed BOOLEAN,
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
           ar.notes, ar.late_reason, ar.absence_informed, st.avatar_url
    FROM roster_students rs
    JOIN students st ON st.id = rs.student_id
    LEFT JOIN attendance_records ar
      ON ar.session_id = get_retrospective_session_roster.session_id
     AND ar.student_id = st.id
    ORDER BY st.full_name;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_retrospective_session_roster(UUID)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_retrospective_session_roster(UUID)
    TO authenticated;

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
       COUNT(*) FILTER (WHERE ar.status = 'absent' AND ar.absence_informed IS TRUE)
           AS absent_informed_count,
       COUNT(*) FILTER (WHERE ar.status = 'absent' AND ar.absence_informed IS FALSE)
           AS absent_uninformed_count,
       ROUND(
           100.0 * COUNT(*) FILTER (WHERE ar.status IN ('present', 'late'))
           / NULLIF(COUNT(*), 0),
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

DO $$
DECLARE
    v_att_ty TEXT;
BEGIN
    SELECT data_type INTO v_att_ty
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'attendance_records'
      AND column_name = 'absence_informed';
    ASSERT v_att_ty = 'boolean',
           'absence_informed column missing or wrong type';

    ASSERT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'public.attendance_records'::REGCLASS
          AND conname = 'attendance_records_absence_informed_check'
          AND convalidated
    ), 'absence_informed check missing or not validated';

    ASSERT (
        SELECT count(*) FROM attendance_records
        WHERE absence_informed IS NOT NULL AND status <> 'absent'
    ) = 0, 'absence_informed set on non-absent rows';

    ASSERT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'attendance_summary'
          AND column_name = 'absent_informed_count'
    ), 'attendance_summary missing absent_informed_count';
    ASSERT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'attendance_summary'
          AND column_name = 'absent_uninformed_count'
    ), 'attendance_summary missing absent_uninformed_count';

    ASSERT (
        SELECT COALESCE('security_invoker=true' = ANY (c.reloptions), FALSE)
        FROM pg_class c
        WHERE c.oid = 'public.attendance_summary'::REGCLASS
    ), 'attendance_summary lost security_invoker';

    ASSERT (
        SELECT count(*) FROM pg_proc
        WHERE proname = 'mark_retrospective_attendance'
          AND pronamespace = 'public'::REGNAMESPACE
    ) = 1, 'mark_retrospective_attendance overload count drifted';
END;
$$;

NOTIFY pgrst, 'reload schema';
