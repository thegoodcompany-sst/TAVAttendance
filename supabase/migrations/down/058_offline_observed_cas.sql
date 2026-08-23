-- Reverse of 058_offline_observed_cas.sql.
-- Restores the 056 sync_attendance body.

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

NOTIFY pgrst, 'reload schema';
