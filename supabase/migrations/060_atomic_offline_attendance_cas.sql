-- 060_atomic_offline_attendance_cas.sql
-- Put observed-state comparisons in the writes themselves so direct online
-- corrections cannot race a separate SELECT. Legacy payloads retain their
-- existing behavior, and accepted mutations keep the existing receipt triggers.

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

-- Keep the existing client RPC and its return shape unchanged.
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
BEGIN
    PERFORM public.apply_attendance_clear(
        p_session_id, p_student_id, p_client_mutation_id, FALSE, NULL
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.apply_attendance_clear(UUID, UUID, TEXT, BOOLEAN, TIMESTAMPTZ)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.apply_attendance_clear(UUID, UUID, TEXT, BOOLEAN, TIMESTAMPTZ)
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
    v_applied BOOLEAN;
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

        BEGIN
            v_applied := TRUE;
            IF rec->'status' IS NULL OR rec->'status' = 'null'::JSONB THEN
                v_applied := public.apply_attendance_clear(
                    (rec->>'session_id')::UUID,
                    (rec->>'student_id')::UUID,
                    v_mutation_id,
                    rec ? 'observed_marked_at',
                    (rec->>'observed_marked_at')::TIMESTAMPTZ
                );
            ELSE
                IF rec->>'status' NOT IN ('present', 'late', 'absent') THEN
                    RAISE EXCEPTION 'invalid attendance status'
                        USING ERRCODE = '23514';
                END IF;
                IF rec ? 'observed_marked_at' THEN
                    IF rec->'observed_marked_at' = 'null'::JSONB THEN
                        INSERT INTO attendance_records (
                            session_id, student_id, status, notes, absence_informed,
                            client_mutation_id, marked_by, marked_at
                        ) VALUES (
                            (rec->>'session_id')::UUID,
                            (rec->>'student_id')::UUID,
                            rec->>'status', rec->>'notes',
                            (rec->>'absence_informed')::BOOLEAN,
                            v_mutation_id, auth.uid(), clock_timestamp()
                        )
                        ON CONFLICT (session_id, student_id) DO NOTHING
                        RETURNING id INTO v_id;
                    ELSE
                        -- PostgreSQL rechecks this predicate after waiting for a
                        -- concurrent writer. A deleted row must not be recreated.
                        UPDATE attendance_records
                        SET status = rec->>'status',
                            notes = rec->>'notes',
                            absence_informed = (rec->>'absence_informed')::BOOLEAN,
                            marked_by = auth.uid(),
                            marked_at = clock_timestamp(),
                            client_mutation_id = v_mutation_id
                        WHERE session_id = (rec->>'session_id')::UUID
                          AND student_id = (rec->>'student_id')::UUID
                          AND marked_at = (rec->>'observed_marked_at')::TIMESTAMPTZ
                        RETURNING id INTO v_id;
                    END IF;
                    v_applied := FOUND;
                ELSE
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
            END IF;
            IF v_applied THEN
                synced := synced + 1;
            ELSE
                skipped_conflict := skipped_conflict + 1;
            END IF;
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

NOTIFY pgrst, 'reload schema';
