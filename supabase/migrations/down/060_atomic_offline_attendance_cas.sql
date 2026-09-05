-- Reverse 060: restore the 055 clear and 058 sync definitions.

CREATE OR REPLACE FUNCTION public.clear_attendance(
    p_session_id UUID,
    p_student_id UUID,
    p_client_mutation_id TEXT
)
RETURNS VOID
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
        RETURN;
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
    DELETE FROM attendance_records
    WHERE session_id = p_session_id AND student_id = p_student_id;

    INSERT INTO attendance_mutation_receipts (
        mutation_id, session_id, student_id, actor_id, accepted_at
    ) VALUES (
        v_mutation_id, p_session_id, p_student_id, v_actor, clock_timestamp()
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.clear_attendance(UUID, UUID, TEXT)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.clear_attendance(UUID, UUID, TEXT)
    TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.sync_attendance(records JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    rec JSONB;
    v_id UUID;
    v_mutation_id TEXT;
    v_live_marked_at TIMESTAMPTZ;
    synced INTEGER := 0;
    skipped INTEGER := 0;
    blocked INTEGER := 0;
    skipped_conflict INTEGER := 0;
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

        -- CAS: apply only when live marked_at matches the last observed
        -- server timestamp (JSON null = no row). Key absent = legacy apply.
        IF rec ? 'observed_marked_at' THEN
            v_live_marked_at := NULL;
            SELECT ar.marked_at INTO v_live_marked_at
            FROM attendance_records ar
            WHERE ar.session_id = (rec->>'session_id')::UUID
              AND ar.student_id = (rec->>'student_id')::UUID;
            IF v_live_marked_at IS NULL THEN
                IF rec->'observed_marked_at' IS DISTINCT FROM 'null'::JSONB THEN
                    skipped_conflict := skipped_conflict + 1;
                    CONTINUE;
                END IF;
            ELSIF v_live_marked_at IS DISTINCT FROM
                  (rec->>'observed_marked_at')::TIMESTAMPTZ THEN
                skipped_conflict := skipped_conflict + 1;
                CONTINUE;
            END IF;
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
        'blocked_ended_session', blocked,
        'skipped_conflict', skipped_conflict
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.sync_attendance(JSONB)
    TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.sync_attendance(JSONB) FROM PUBLIC, anon;

DO $$
DECLARE
    v_fn TEXT;
BEGIN
    ASSERT to_regprocedure('public.sync_attendance(jsonb)') IS NOT NULL,
           'sync_attendance(jsonb) missing';
    v_fn := pg_get_functiondef('public.sync_attendance(jsonb)'::REGPROCEDURE);
    ASSERT POSITION('observed_marked_at' IN v_fn) > 0,
           'sync_attendance missing observed_marked_at';
    ASSERT POSITION('skipped_conflict' IN v_fn) > 0,
           'sync_attendance missing skipped_conflict';
END;
$$;

NOTIFY pgrst, 'reload schema';

DROP FUNCTION public.apply_attendance_clear(UUID, UUID, TEXT, BOOLEAN, TIMESTAMPTZ);
NOTIFY pgrst, 'reload schema';
