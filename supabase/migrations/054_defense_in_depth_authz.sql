-- 054_defense_in_depth_authz.sql
-- Defense-in-depth authorization tightenings from the 2026-07-29 security scan.
--
-- 1. get_study_space_roster: require admin + study_space_tracking + study-space session
-- 2. sync_attendance: explicit staff role gate (parents must never reach offline sync)
-- 3. link_parent_student: target profile must be role=parent
-- 4. register_device_token: refuse foreign-owner token takeover on conflict

-- ── 1. Study-space roster ───────────────────────────────────────
-- Was SECURITY INVOKER over all active students. Rebind as DEFINER with
-- explicit gates so a future broad student SELECT cannot silently expose
-- centre-wide presence via this RPC.
CREATE OR REPLACE FUNCTION public.get_study_space_roster(p_session_id UUID)
RETURNS TABLE (
    student_id      UUID,
    full_name       TEXT,
    attendance_id   UUID,
    status          TEXT,
    marked_at       TIMESTAMPTZ,
    avatar_url      TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF auth.uid() IS NULL
       OR NOT is_admin()
       OR NOT is_feature_enabled('study_space_tracking') THEN
        RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM sessions s
        JOIN classes c ON c.id = s.class_id
        WHERE s.id = p_session_id
          AND c.is_study_space = TRUE
          AND c.is_active = TRUE
    ) THEN
        RAISE EXCEPTION 'not a study space session' USING ERRCODE = '22023';
    END IF;

    RETURN QUERY
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
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_study_space_roster(UUID)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_study_space_roster(UUID)
    TO authenticated, service_role;

-- ── 2. Offline attendance sync staff gate ───────────────────────
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
    -- Defense in depth: parents (and any non-staff role) must fail closed even
    -- if an attendance write policy is ever re-introduced by mistake.
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
        -- Serialize identical mutation IDs so two concurrent retries cannot
        -- both pass the replay check before either write becomes visible.
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

-- ── 3. Parent link must target a parent profile ─────────────────
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

    IF p_parent IS NULL OR p_student IS NULL THEN
        RAISE EXCEPTION 'parent and student are required' USING ERRCODE = '22023';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM profiles
        WHERE id = p_parent AND role = 'parent'
    ) THEN
        RAISE EXCEPTION 'target account is not a parent' USING ERRCODE = '22023';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM students WHERE id = p_student
    ) THEN
        RAISE EXCEPTION 'student not found' USING ERRCODE = '22023';
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

-- ── 4. Device token: no foreign takeover ────────────────────────
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
    v_upserted UUID;
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

    -- Serialize per token so concurrent foreign claims cannot race the unique key.
    PERFORM pg_advisory_xact_lock(hashtextextended(v_token, 11));
    PERFORM pg_advisory_xact_lock(hashtextextended(auth.uid()::TEXT, 7));

    INSERT INTO device_tokens (user_id, token, platform, created_at)
    VALUES (auth.uid(), v_token, v_platform, clock_timestamp())
    ON CONFLICT (token) DO UPDATE
    SET platform = EXCLUDED.platform,
        created_at = EXCLUDED.created_at
    WHERE device_tokens.user_id = auth.uid()
    RETURNING id INTO v_upserted;

    -- FOUND is false when a foreign owner holds the token (UPDATE WHERE failed)
    -- or when the insert/update produced no row.
    IF v_upserted IS NULL THEN
        RAISE EXCEPTION 'device token already registered' USING ERRCODE = '23505';
    END IF;

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

-- Verification (DEVOPS-02)
DO $$
DECLARE
    v_roster TEXT;
    v_sync TEXT;
    v_link TEXT;
    v_token TEXT;
BEGIN
    v_roster := LOWER(pg_get_functiondef(
        'public.get_study_space_roster(uuid)'::REGPROCEDURE
    ));
    v_sync := LOWER(pg_get_functiondef(
        'public.sync_attendance(jsonb)'::REGPROCEDURE
    ));
    v_link := LOWER(pg_get_functiondef(
        'public.link_parent_student(uuid,uuid)'::REGPROCEDURE
    ));
    v_token := LOWER(pg_get_functiondef(
        'public.register_device_token(text,text)'::REGPROCEDURE
    ));

    ASSERT POSITION('is_admin()' IN v_roster) > 0,
        '054: get_study_space_roster missing is_admin gate';
    ASSERT POSITION('study_space_tracking' IN v_roster) > 0,
        '054: get_study_space_roster missing feature flag gate';
    ASSERT POSITION('is_study_space' IN v_roster) > 0,
        '054: get_study_space_roster missing study-space session check';
    ASSERT POSITION('security definer' IN v_roster) > 0,
        '054: get_study_space_roster must be SECURITY DEFINER';

    ASSERT POSITION('is_admin()' IN v_sync) > 0
       AND POSITION('is_tutor()' IN v_sync) > 0,
        '054: sync_attendance missing staff role gate';

    ASSERT POSITION('role = ''parent''' IN v_link) > 0,
        '054: link_parent_student missing parent role check';

    ASSERT POSITION('already registered' IN v_token) > 0,
        '054: register_device_token missing foreign-owner refusal';
    ASSERT POSITION('device_tokens.user_id = auth.uid()' IN v_token) > 0,
        '054: register_device_token must not reassign foreign owners on conflict';
    ASSERT POSITION('hashtextextended(v_token' IN v_token) > 0,
        '054: register_device_token missing per-token advisory lock';
END $$;
