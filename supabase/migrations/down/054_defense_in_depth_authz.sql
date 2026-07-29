-- down/054_defense_in_depth_authz.sql — reverse of 054.
-- Restores the pre-054 bodies from 015 (roster), 038 (sync + token), and 005/034 (link).

BEGIN;

-- Restore invoker study-space roster (015 shape).
CREATE OR REPLACE FUNCTION public.get_study_space_roster(p_session_id UUID)
RETURNS TABLE (
    student_id      UUID,
    full_name       TEXT,
    attendance_id   UUID,
    status          TEXT,
    marked_at       TIMESTAMPTZ,
    avatar_url      TEXT
) LANGUAGE SQL STABLE SECURITY INVOKER
SET search_path = public
AS $$
    SELECT
        st.id            AS student_id,
        st.full_name,
        ar.id            AS attendance_id,
        ar.status,
        ar.marked_at,
        st.avatar_url
    FROM students st
    LEFT JOIN attendance_records ar
           ON ar.session_id = p_session_id AND ar.student_id = st.id
    WHERE st.is_active = TRUE
    ORDER BY st.full_name;
$$;

GRANT EXECUTE ON FUNCTION public.get_study_space_roster(UUID) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.get_study_space_roster(UUID) FROM PUBLIC, anon;

-- Restore 038 sync_attendance without staff role gate.
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
                rec->>'status',
                rec->>'notes',
                v_mutation_id,
                auth.uid(),
                clock_timestamp()
            )
            ON CONFLICT (session_id, student_id) DO UPDATE
            SET status = EXCLUDED.status,
                notes = EXCLUDED.notes,
                marked_by = EXCLUDED.marked_by,
                marked_at = EXCLUDED.marked_at,
                client_mutation_id = EXCLUDED.client_mutation_id
            RETURNING id INTO v_id;
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

-- Restore link_parent_student without parent-role target check (005 + 034 search_path).
CREATE OR REPLACE FUNCTION public.link_parent_student(
    p_parent  UUID,
    p_student UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM profiles
        WHERE id = auth.uid() AND role = 'admin'
    ) THEN
        RAISE EXCEPTION 'Forbidden: admin role required';
    END IF;

    INSERT INTO parent_student_links (parent_id, student_id)
    VALUES (p_parent, p_student)
    ON CONFLICT DO NOTHING;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.link_parent_student(UUID, UUID)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.link_parent_student(UUID, UUID)
    TO authenticated, service_role;

-- Restore 038 register_device_token with foreign reassignment on conflict.
CREATE OR REPLACE FUNCTION public.register_device_token(
    p_token TEXT,
    p_platform TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_token TEXT := BTRIM(COALESCE(p_token, ''));
    v_platform TEXT := LOWER(BTRIM(COALESCE(p_platform, '')));
BEGIN
    IF auth.uid() IS NULL
       OR NOT is_parent()
       OR NOT is_feature_enabled('push_notifications') THEN
        RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
    END IF;
    IF char_length(v_token) NOT BETWEEN 32 AND 4096
       OR v_token ~ '[[:space:][:cntrl:]]'
       OR v_platform NOT IN ('ios', 'android') THEN
        RAISE EXCEPTION 'invalid device token' USING ERRCODE = '22023';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended(auth.uid()::TEXT, 7));
    INSERT INTO device_tokens (user_id, token, platform, created_at)
    VALUES (auth.uid(), v_token, v_platform, clock_timestamp())
    ON CONFLICT (token) DO UPDATE
    SET user_id = EXCLUDED.user_id,
        platform = EXCLUDED.platform,
        created_at = EXCLUDED.created_at;

    DELETE FROM device_tokens dt
    WHERE dt.user_id = auth.uid()
      AND dt.id IN (
          SELECT ranked.id
          FROM device_tokens ranked
          WHERE ranked.user_id = auth.uid()
          ORDER BY ranked.created_at DESC, ranked.id DESC
          OFFSET 5
      );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.register_device_token(TEXT, TEXT)
    FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.register_device_token(TEXT, TEXT)
    TO authenticated;

COMMIT;
