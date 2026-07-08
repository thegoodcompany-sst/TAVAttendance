-- ============================================================
-- 016 — Security fixes  (DOWN)
-- ============================================================
-- Reverts 016 back to the post-015 state. NOTE: this deliberately restores the
-- INSECURE definitions that 016 fixed — only run to roll back the migration.

-- SEC-16a/b — restore 015's view (no security_invoker, no active filter)
CREATE OR REPLACE VIEW attendance_summary AS
SELECT
    s.student_id,
    st.full_name                                                     AS student_name,
    se.class_id,
    c.name                                                           AS class_name,
    COUNT(*)                                                         AS total_sessions,
    COUNT(*) FILTER (WHERE s.status = 'present')                    AS present_count,
    COUNT(*) FILTER (WHERE s.status = 'late')                       AS late_count,
    COUNT(*) FILTER (WHERE s.status = 'absent')                     AS absent_count,
    COUNT(*) FILTER (WHERE s.status = 'excused')                    AS excused_count,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE s.status IN ('present','late','excused'))
        / NULLIF(COUNT(*), 0),
        1
    )                                                                AS attendance_pct
FROM attendance_records s
JOIN students st  ON st.id = s.student_id
JOIN sessions se  ON se.id = s.session_id
JOIN classes  c   ON c.id  = se.class_id
WHERE c.is_study_space = FALSE
GROUP BY s.student_id, st.full_name, se.class_id, c.name;

-- SEC-16c — restore 013's handle_new_user
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    requested_role TEXT := COALESCE(NEW.raw_user_meta_data->>'role', 'tutor');
    is_bootstrap   BOOLEAN := NOT EXISTS (SELECT 1 FROM profiles);
    final_role     TEXT;
BEGIN
    IF requested_role = 'tutor'
       OR is_bootstrap
       OR auth.uid() IS NULL
       OR is_admin() THEN
        final_role := requested_role;
    ELSE
        final_role := 'tutor';
    END IF;

    INSERT INTO profiles (id, full_name, role)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email),
        final_role
    )
    ON CONFLICT (id) DO NOTHING;
    RETURN NEW;
END;
$$;

-- SEC-16d — restore 002's parent attendance policy
DROP POLICY IF EXISTS "attendance_records: parent reads own children" ON attendance_records;
CREATE POLICY "attendance_records: parent reads own children"
    ON attendance_records FOR SELECT
    TO authenticated
    USING (
        is_parent() AND parent_owns_student(attendance_records.student_id)
    );

-- SEC-16e — restore 011's erase_student and drop the messages ON DELETE action
CREATE OR REPLACE FUNCTION erase_student(p_student_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NOT is_admin() THEN RAISE EXCEPTION 'not authorized'; END IF;
    PERFORM set_config('app.suppress_audit', 'on', true);
    DELETE FROM dismissals          WHERE student_id = p_student_id;
    DELETE FROM food_poll_responses WHERE student_id = p_student_id;
    DELETE FROM students            WHERE id = p_student_id;
    DELETE FROM audit_log
        WHERE (table_name = 'students' AND record_id = p_student_id)
           OR (old_data->>'student_id' = p_student_id::text)
           OR (new_data->>'student_id' = p_student_id::text);
END;
$$;
ALTER TABLE messages DROP CONSTRAINT IF EXISTS messages_student_id_fkey;
ALTER TABLE messages
    ADD CONSTRAINT messages_student_id_fkey
    FOREIGN KEY (student_id) REFERENCES students(id);

-- SEC-16f — unpin search_path on parent-link functions
ALTER FUNCTION link_parent_student(UUID, UUID)   RESET search_path;
ALTER FUNCTION unlink_parent_student(UUID, UUID) RESET search_path;

-- SEC-16g/h — restore 008's guard (INSERT/UPDATE only, generic errcode) + 013 sync
CREATE OR REPLACE FUNCTION check_session_not_ended()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM sessions
    WHERE id = NEW.session_id AND ended_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Cannot modify attendance for ended session %', NEW.session_id;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS enforce_attendance_on_open_session ON attendance_records;
CREATE TRIGGER enforce_attendance_on_open_session
BEFORE INSERT OR UPDATE ON attendance_records
FOR EACH ROW EXECUTE FUNCTION check_session_not_ended();

CREATE OR REPLACE FUNCTION sync_attendance(records JSONB)
RETURNS JSONB LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    rec JSONB; v_id UUID; synced INT := 0; skipped INT := 0; blocked INT := 0;
    v_marked_at TIMESTAMPTZ;
BEGIN
    FOR rec IN SELECT * FROM jsonb_array_elements(records)
    LOOP
        v_marked_at := LEAST(
            COALESCE((rec->>'marked_at')::TIMESTAMPTZ, NOW()),
            NOW() + INTERVAL '5 minutes'
        );
        BEGIN
            INSERT INTO attendance_records (
                session_id, student_id, status, notes, client_mutation_id, marked_by, marked_at
            ) VALUES (
                (rec->>'session_id')::UUID, (rec->>'student_id')::UUID, rec->>'status',
                rec->>'notes', rec->>'client_mutation_id', auth.uid(), v_marked_at
            )
            ON CONFLICT (session_id, student_id) DO UPDATE
                SET status = EXCLUDED.status, notes = EXCLUDED.notes,
                    marked_by = EXCLUDED.marked_by, marked_at = EXCLUDED.marked_at,
                    client_mutation_id = EXCLUDED.client_mutation_id
            WHERE attendance_records.marked_at <= EXCLUDED.marked_at
            RETURNING id INTO v_id;
            IF FOUND THEN synced := synced + 1; ELSE skipped := skipped + 1; END IF;
        EXCEPTION
            WHEN raise_exception THEN blocked := blocked + 1;
            WHEN unique_violation THEN skipped := skipped + 1;
        END;
    END LOOP;
    RETURN jsonb_build_object('synced', synced, 'skipped', skipped, 'blocked_ended_session', blocked);
END;
$$;
GRANT EXECUTE ON FUNCTION sync_attendance(JSONB) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION sync_attendance(JSONB) FROM PUBLIC, anon;

-- SEC-16i — restore default PUBLIC execute on is_feature_enabled
GRANT EXECUTE ON FUNCTION is_feature_enabled(TEXT) TO PUBLIC;

-- SEC-16j — restore dismissals FKs to NO ACTION
ALTER TABLE dismissals DROP CONSTRAINT IF EXISTS dismissals_session_id_fkey;
ALTER TABLE dismissals
    ADD CONSTRAINT dismissals_session_id_fkey
    FOREIGN KEY (session_id) REFERENCES sessions(id);
ALTER TABLE dismissals DROP CONSTRAINT IF EXISTS dismissals_student_id_fkey;
ALTER TABLE dismissals
    ADD CONSTRAINT dismissals_student_id_fkey
    FOREIGN KEY (student_id) REFERENCES students(id);
