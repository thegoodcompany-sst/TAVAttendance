-- 059_nfc_arrival_station.sql
--
-- Dedicated Linux arrival station (Raspberry Pi / Orange Pi / Armbian).
-- Students tap an NFC card; staff still override on the named kiosk grid.
--
-- Invariants:
--   * Chip UID → student. The tag is never written with a student UUID.
--   * The station account is not admin. It may only call the tap RPC.
--   * Same mark path as a kiosk card tap (present/late from schedule/start).
--   * Study Space is excluded. Unexpected taps fail closed.
--   * Flag `nfc_sign_in` ships OFF. Do not apply this to production yet.
--
-- iOS 1.1.3 / current clients: additive only. No existing table columns change.
-- An `arrival_station` login on the phone apps must fail closed (not tutor UI).

INSERT INTO feature_flags (key, enabled, description) VALUES
    ('nfc_sign_in', FALSE,
     'Dedicated Linux arrival station: NFC chip UID sign-in. Pair and reissue cards on the web. Ships OFF.')
ON CONFLICT (key) DO NOTHING;

ALTER TABLE profiles DROP CONSTRAINT profiles_role_check;
ALTER TABLE profiles ADD CONSTRAINT profiles_role_check
    CHECK (role IN ('admin', 'tutor', 'parent', 'arrival_station'));

CREATE FUNCTION public.is_arrival_station()
RETURNS BOOLEAN
LANGUAGE SQL
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
    SELECT get_my_role() = 'arrival_station'
$$;

REVOKE EXECUTE ON FUNCTION public.is_arrival_station() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_arrival_station() TO authenticated, service_role;

-- ── Chip UID → student (admin pairs; station only resolves via RPC) ──

CREATE TABLE public.nfc_tag_bindings (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chip_uid    TEXT NOT NULL,
    student_id  UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    issued_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    issued_by   UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    revoked_at  TIMESTAMPTZ,
    revoked_by  UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    CONSTRAINT nfc_tag_bindings_uid_format
        CHECK (chip_uid ~ '^[0-9A-F]{8,20}$' AND length(chip_uid) % 2 = 0),
    CONSTRAINT nfc_tag_bindings_revoke_pair
        CHECK ((revoked_at IS NULL) = (revoked_by IS NULL))
);

CREATE UNIQUE INDEX nfc_tag_bindings_active_uid
    ON public.nfc_tag_bindings (chip_uid)
    WHERE revoked_at IS NULL;

CREATE UNIQUE INDEX nfc_tag_bindings_active_student
    ON public.nfc_tag_bindings (student_id)
    WHERE revoked_at IS NULL;

CREATE INDEX nfc_tag_bindings_student_idx
    ON public.nfc_tag_bindings (student_id);

ALTER TABLE public.nfc_tag_bindings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.nfc_tag_bindings FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.nfc_tag_bindings TO authenticated;

CREATE POLICY "nfc_tag_bindings: superadmin read"
    ON public.nfc_tag_bindings FOR SELECT TO authenticated
    USING (is_superadmin());

CREATE TRIGGER audit_nfc_tag_bindings
    AFTER INSERT OR UPDATE OR DELETE ON public.nfc_tag_bindings
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_func();

CREATE FUNCTION public.normalize_nfc_chip_uid(p_chip_uid TEXT)
RETURNS TEXT
LANGUAGE SQL
IMMUTABLE
SET search_path = public, pg_temp
AS $$
    SELECT CASE
        WHEN v_hex ~ '^[0-9A-F]{8,20}$' AND length(v_hex) % 2 = 0 THEN v_hex
        ELSE NULL
    END
    FROM (
        SELECT upper(regexp_replace(COALESCE(p_chip_uid, ''), '[^0-9A-Fa-f]', '', 'g')) AS v_hex
    ) n
$$;

REVOKE EXECUTE ON FUNCTION public.normalize_nfc_chip_uid(TEXT)
    FROM PUBLIC, anon, authenticated;

-- Mirrors iOS AttendanceService.classMeetsToday: BYDAY wins when present and
-- non-empty; otherwise schedule_day; neither set means ad hoc (always).
CREATE FUNCTION public.class_meets_on_singapore_date(
    p_schedule_day TEXT,
    p_recurrence_rule TEXT,
    p_date DATE
)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
DECLARE
    v_iso INTEGER := EXTRACT(ISODOW FROM p_date)::INT;
    v_weekday TEXT;
    v_code TEXT;
    v_part TEXT;
    v_byday TEXT;
    v_codes TEXT[];
BEGIN
    -- ISODOW is locale-safe; iOS classMeetsToday uses English weekday names.
    v_code := CASE v_iso
        WHEN 1 THEN 'MO'
        WHEN 2 THEN 'TU'
        WHEN 3 THEN 'WE'
        WHEN 4 THEN 'TH'
        WHEN 5 THEN 'FR'
        WHEN 6 THEN 'SA'
        WHEN 7 THEN 'SU'
        ELSE ''
    END;
    v_weekday := CASE v_iso
        WHEN 1 THEN 'monday'
        WHEN 2 THEN 'tuesday'
        WHEN 3 THEN 'wednesday'
        WHEN 4 THEN 'thursday'
        WHEN 5 THEN 'friday'
        WHEN 6 THEN 'saturday'
        WHEN 7 THEN 'sunday'
        ELSE ''
    END;

    IF p_recurrence_rule IS NOT NULL AND BTRIM(p_recurrence_rule) <> '' THEN
        FOREACH v_part IN ARRAY string_to_array(p_recurrence_rule, ';')
        LOOP
            IF upper(split_part(v_part, '=', 1)) = 'BYDAY' THEN
                v_byday := upper(BTRIM(split_part(v_part, '=', 2)));
                IF v_byday <> '' THEN
                    v_codes := string_to_array(replace(v_byday, ' ', ''), ',');
                    IF v_codes IS NOT NULL AND array_length(v_codes, 1) >= 1 THEN
                        RETURN v_code = ANY (v_codes);
                    END IF;
                END IF;
            END IF;
        END LOOP;
    END IF;

    IF p_schedule_day IS NOT NULL AND BTRIM(p_schedule_day) <> '' THEN
        RETURN lower(BTRIM(p_schedule_day)) = lower(v_weekday);
    END IF;

    RETURN TRUE;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.class_meets_on_singapore_date(TEXT, TEXT, DATE)
    FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.nfc_sign_in_status(
    p_schedule_time TIME,
    p_started_at TIMESTAMPTZ,
    p_now TIMESTAMPTZ
)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
DECLARE
    v_now_sg TIMESTAMP := p_now AT TIME ZONE 'Asia/Singapore';
    v_class_start TIMESTAMP;
BEGIN
    IF p_started_at IS NOT NULL AND p_now > p_started_at THEN
        RETURN 'late';
    END IF;
    -- Match iOS signInStatus: hour and minute only; seconds on TIME are ignored.
    IF p_schedule_time IS NOT NULL THEN
        v_class_start := date_trunc('day', v_now_sg)
            + make_interval(
                hours => EXTRACT(HOUR FROM p_schedule_time)::INT,
                mins => EXTRACT(MINUTE FROM p_schedule_time)::INT
              );
        IF v_now_sg > v_class_start THEN
            RETURN 'late';
        END IF;
    END IF;
    RETURN 'present';
END;
$$;

REVOKE EXECUTE ON FUNCTION public.nfc_sign_in_status(TIME, TIMESTAMPTZ, TIMESTAMPTZ)
    FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.pair_nfc_chip(p_student_id UUID, p_chip_uid TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid TEXT := normalize_nfc_chip_uid(p_chip_uid);
    v_student students%ROWTYPE;
    v_existing nfc_tag_bindings%ROWTYPE;
    v_row nfc_tag_bindings%ROWTYPE;
BEGIN
    IF NOT is_feature_enabled('nfc_sign_in') THEN
        RAISE EXCEPTION 'nfc sign-in is disabled';
    END IF;
    IF NOT is_admin() THEN
        RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
    END IF;
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'invalid NFC chip UID' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_student FROM students WHERE id = p_student_id;
    IF NOT FOUND OR NOT v_student.is_active THEN
        RAISE EXCEPTION 'student is not eligible for an NFC card';
    END IF;

    SELECT * INTO v_existing
    FROM nfc_tag_bindings
    WHERE chip_uid = v_uid AND revoked_at IS NULL;
    IF FOUND AND v_existing.student_id = p_student_id THEN
        RETURN jsonb_build_object(
            'chip_uid_suffix', right(v_uid, 4),
            'issued_at', v_existing.issued_at
        );
    END IF;

    UPDATE nfc_tag_bindings
    SET revoked_at = NOW(), revoked_by = auth.uid()
    WHERE revoked_at IS NULL
      AND (student_id = p_student_id OR chip_uid = v_uid);

    INSERT INTO nfc_tag_bindings (chip_uid, student_id, issued_by)
    VALUES (v_uid, p_student_id, auth.uid())
    RETURNING * INTO v_row;

    RETURN jsonb_build_object(
        'chip_uid_suffix', right(v_uid, 4),
        'issued_at', v_row.issued_at
    );
END;
$$;

CREATE FUNCTION public.revoke_nfc_chip_for_student(p_student_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT is_feature_enabled('nfc_sign_in') THEN
        RAISE EXCEPTION 'nfc sign-in is disabled';
    END IF;
    IF NOT is_admin() THEN
        RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
    END IF;

    UPDATE nfc_tag_bindings
    SET revoked_at = NOW(), revoked_by = auth.uid()
    WHERE student_id = p_student_id
      AND revoked_at IS NULL;
END;
$$;

CREATE FUNCTION public.get_student_nfc_binding(p_student_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
    v_row nfc_tag_bindings%ROWTYPE;
BEGIN
    IF NOT is_feature_enabled('nfc_sign_in') THEN
        RAISE EXCEPTION 'nfc sign-in is disabled';
    END IF;
    IF NOT is_admin() THEN
        RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_row
    FROM nfc_tag_bindings
    WHERE student_id = p_student_id
      AND revoked_at IS NULL;
    IF NOT FOUND THEN
        RETURN NULL;
    END IF;
    RETURN jsonb_build_object(
        'chip_uid_suffix', right(v_row.chip_uid, 4),
        'issued_at', v_row.issued_at
    );
END;
$$;

-- Station-only mark. Online, actor-bound, server-timed. Creates today's
-- eligible sessions the same way the kiosk does on load.
CREATE FUNCTION public.arrival_station_tap(p_chip_uid TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid TEXT := normalize_nfc_chip_uid(p_chip_uid);
    v_student_id UUID;
    v_full_name TEXT;
    v_today DATE := (clock_timestamp() AT TIME ZONE 'Asia/Singapore')::DATE;
    v_now TIMESTAMPTZ := clock_timestamp();
    v_test_mode BOOLEAN := is_feature_enabled('test_mode');
    v_class RECORD;
    v_session sessions%ROWTYPE;
    v_slot JSONB;
    v_slots JSONB := '[]'::JSONB;
    v_session_ids UUID[] := '{}';
    v_any_attending BOOLEAN := FALSE;
    v_any_absent BOOLEAN := FALSE;
    v_open_count INTEGER := 0;
    v_status TEXT;
    v_worst TEXT := 'present';
    v_recent BIGINT;
    v_mutation TEXT;
    v_schedule_time TIME;
BEGIN
    IF NOT is_feature_enabled('nfc_sign_in') THEN
        RAISE EXCEPTION 'nfc sign-in is disabled';
    END IF;
    IF auth.uid() IS NULL OR NOT is_arrival_station() THEN
        RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
    END IF;
    IF v_uid IS NULL THEN
        RETURN jsonb_build_object('outcome', 'unknown_card');
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended(auth.uid()::TEXT || ':nfc', 7));
    DELETE FROM rate_limit_events
    WHERE actor_id = auth.uid()
      AND action = 'arrival_station_tap'
      AND created_at < NOW() - INTERVAL '1 hour';
    SELECT COUNT(*) INTO v_recent
    FROM rate_limit_events
    WHERE actor_id = auth.uid()
      AND action = 'arrival_station_tap'
      AND created_at >= NOW() - INTERVAL '1 minute';
    IF v_recent >= 180 THEN
        RAISE EXCEPTION 'arrival station rate limit reached' USING ERRCODE = '54000';
    END IF;
    INSERT INTO rate_limit_events (actor_id, action)
    VALUES (auth.uid(), 'arrival_station_tap');

    SELECT b.student_id, st.full_name
    INTO v_student_id, v_full_name
    FROM nfc_tag_bindings b
    JOIN students st ON st.id = b.student_id
    WHERE b.chip_uid = v_uid
      AND b.revoked_at IS NULL
      AND st.is_active;
    IF v_student_id IS NULL THEN
        RETURN jsonb_build_object(
            'outcome', 'unknown_card',
            'chip_uid', v_uid
        );
    END IF;

    FOR v_class IN
        SELECT c.id, c.schedule_time
        FROM classes c
        JOIN enrollments e ON e.class_id = c.id
        WHERE e.student_id = v_student_id
          AND c.is_active
          AND COALESCE(c.is_study_space, FALSE) = FALSE
          AND (e.enrolled_at AT TIME ZONE 'Asia/Singapore')::DATE <= v_today
          AND (
                e.unenrolled_at IS NULL
                OR (e.unenrolled_at AT TIME ZONE 'Asia/Singapore')::DATE >= v_today
              )
          AND (
                v_test_mode
                OR class_meets_on_singapore_date(
                    c.schedule_day, c.recurrence_rule, v_today
                )
              )
    LOOP
        SELECT s.* INTO v_session
        FROM sessions s
        WHERE s.class_id = v_class.id AND s.session_date = v_today
        FOR UPDATE;

        IF NOT FOUND THEN
            PERFORM set_config('app.session_create_write', 'on', TRUE);
            INSERT INTO sessions (class_id, session_date, created_by)
            VALUES (v_class.id, v_today, auth.uid())
            ON CONFLICT (class_id, session_date) DO NOTHING;
            PERFORM set_config('app.session_create_write', 'off', TRUE);

            SELECT s.* INTO v_session
            FROM sessions s
            WHERE s.class_id = v_class.id AND s.session_date = v_today
            FOR UPDATE;
        END IF;

        IF NOT FOUND THEN
            CONTINUE;
        END IF;

        v_session_ids := array_append(v_session_ids, v_session.id);
        v_slots := v_slots || jsonb_build_array(jsonb_build_object(
            'session_id', v_session.id,
            'schedule_time', v_class.schedule_time,
            'started_at', v_session.started_at,
            'ended_at', v_session.ended_at
        ));
    END LOOP;

    IF jsonb_array_length(v_slots) = 0 THEN
        RETURN jsonb_build_object(
            'outcome', 'not_on_roster',
            'full_name', v_full_name
        );
    END IF;

    IF EXISTS (
        SELECT 1
        FROM dismissals d
        WHERE d.student_id = v_student_id
          AND d.session_id = ANY (v_session_ids)
    ) THEN
        RETURN jsonb_build_object(
            'outcome', 'already_dismissed',
            'full_name', v_full_name
        );
    END IF;

    SELECT
        COALESCE(bool_or(ar.status IN ('present', 'late')), FALSE),
        COALESCE(bool_or(ar.status = 'absent'), FALSE)
    INTO v_any_attending, v_any_absent
    FROM attendance_records ar
    WHERE ar.student_id = v_student_id
      AND ar.session_id = ANY (v_session_ids);

    IF v_any_attending THEN
        RETURN jsonb_build_object(
            'outcome', 'already_signed_in',
            'full_name', v_full_name
        );
    END IF;
    IF v_any_absent THEN
        RETURN jsonb_build_object(
            'outcome', 'marked_absent',
            'full_name', v_full_name
        );
    END IF;

    FOR v_slot IN SELECT value FROM jsonb_array_elements(v_slots)
    LOOP
        IF v_slot->>'ended_at' IS NOT NULL THEN
            CONTINUE;
        END IF;
        v_open_count := v_open_count + 1;
        v_schedule_time := NULLIF(v_slot->>'schedule_time', '')::TIME;
        v_status := nfc_sign_in_status(
            v_schedule_time,
            NULLIF(v_slot->>'started_at', '')::TIMESTAMPTZ,
            v_now
        );
        IF v_status = 'late' THEN
            v_worst := 'late';
        END IF;

        v_mutation := gen_random_uuid()::TEXT;
        INSERT INTO attendance_records (
            session_id, student_id, status, client_mutation_id
        ) VALUES (
            (v_slot->>'session_id')::UUID, v_student_id, v_status, v_mutation
        )
        ON CONFLICT (session_id, student_id) DO NOTHING;
    END LOOP;

    IF v_open_count = 0 THEN
        RETURN jsonb_build_object(
            'outcome', 'not_on_roster',
            'full_name', v_full_name
        );
    END IF;

    RETURN jsonb_build_object(
        'outcome', CASE WHEN v_worst = 'late' THEN 'late' ELSE 'on_time' END,
        'full_name', v_full_name,
        'status', v_worst
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.pair_nfc_chip(UUID, TEXT)
    FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.pair_nfc_chip(UUID, TEXT) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.revoke_nfc_chip_for_student(UUID)
    FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.revoke_nfc_chip_for_student(UUID) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.get_student_nfc_binding(UUID)
    FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_student_nfc_binding(UUID) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.arrival_station_tap(TEXT)
    FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.arrival_station_tap(TEXT) TO authenticated;

-- Subject-access bundle includes active chip suffixes only (not full UID).
CREATE OR REPLACE FUNCTION export_student_personal_data(p_student_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE result JSONB;
BEGIN
    IF NOT is_admin() THEN RAISE EXCEPTION 'not authorized'; END IF;
    SELECT jsonb_build_object(
        'student',         (SELECT to_jsonb(s) FROM students s WHERE s.id = p_student_id),
        'enrollments',     (SELECT COALESCE(jsonb_agg(to_jsonb(e)), '[]') FROM enrollments e WHERE e.student_id = p_student_id),
        'attendance',      (SELECT COALESCE(jsonb_agg(to_jsonb(a)), '[]')
                            FROM attendance_records a
                            JOIN sessions se ON se.id = a.session_id
                            JOIN classes c ON c.id = se.class_id
                            WHERE a.student_id = p_student_id AND c.is_study_space = FALSE),
        'parents',         (SELECT COALESCE(jsonb_agg(jsonb_build_object('parent', to_jsonb(p), 'link', to_jsonb(l))), '[]') FROM parent_student_links l JOIN profiles p ON p.id = l.parent_id WHERE l.student_id = p_student_id),
        'consent',         (SELECT COALESCE(jsonb_agg(to_jsonb(c)), '[]') FROM consent_records c WHERE c.student_id = p_student_id),
        'result_slips',    (SELECT COALESCE(jsonb_agg(to_jsonb(r)), '[]') FROM result_slips r WHERE r.student_id = p_student_id),
        'student_results', (SELECT COALESCE(jsonb_agg(to_jsonb(sr)), '[]') FROM student_results sr WHERE sr.student_id = p_student_id),
        'dismissals',      (SELECT COALESCE(jsonb_agg(to_jsonb(d)), '[]') FROM dismissals d WHERE d.student_id = p_student_id),
        'awards',          (SELECT COALESCE(jsonb_agg(to_jsonb(w)), '[]') FROM awards w WHERE w.student_id = p_student_id),
        'nfc_cards',       (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                                'chip_uid_suffix', right(b.chip_uid, 4),
                                'issued_at', b.issued_at,
                                'revoked_at', b.revoked_at
                            )), '[]')
                            FROM nfc_tag_bindings b
                            WHERE b.student_id = p_student_id),
        'generated_at',    NOW()
    ) INTO result;
    INSERT INTO data_disclosures (student_id, disclosed_to, disclosure_type, disclosed_by, detail)
    VALUES (p_student_id, 'Subject access request', 'subject_access_export', auth.uid(),
            jsonb_build_object('via', 'export_student_personal_data'));
    RETURN result;
END;
$$;

NOTIFY pgrst, 'reload schema';

-- Verification (DEVOPS-02): abort if this migration did not fully apply.
DO $$
BEGIN
    ASSERT (SELECT EXISTS (SELECT FROM feature_flags WHERE key = 'nfc_sign_in' AND enabled = FALSE)),
           '059: nfc_sign_in flag missing or not OFF';
    ASSERT (SELECT EXISTS (
                SELECT FROM pg_constraint
                WHERE conrelid = 'public.profiles'::REGCLASS
                  AND conname = 'profiles_role_check'
                  AND pg_get_constraintdef(oid) LIKE '%arrival_station%'
            )),
           '059: profiles.role does not allow arrival_station';
    ASSERT (SELECT EXISTS (SELECT FROM information_schema.tables
            WHERE table_schema = 'public' AND table_name = 'nfc_tag_bindings')),
           '059: nfc_tag_bindings missing';
    ASSERT (SELECT EXISTS (SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'public' AND p.proname = 'arrival_station_tap')),
           '059: arrival_station_tap missing';
    ASSERT (SELECT EXISTS (SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'public' AND p.proname = 'pair_nfc_chip')),
           '059: pair_nfc_chip missing';
    ASSERT (SELECT NOT has_table_privilege('anon', 'public.nfc_tag_bindings', 'SELECT')),
           '059: anon can read nfc_tag_bindings';
    ASSERT (SELECT NOT has_function_privilege(
                'anon', 'public.arrival_station_tap(text)', 'EXECUTE')),
           '059: anon can execute arrival_station_tap';
    ASSERT (SELECT coalesce('security_invoker=true' = ANY (c.reloptions), false)
            FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'public' AND c.relname = 'attendance_summary'),
           'attendance_summary lost security_invoker';
END $$;
