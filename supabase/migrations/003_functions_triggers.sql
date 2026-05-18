-- ============================================================
-- TAVA Attendance Platform — Functions & Triggers
-- ============================================================


-- ── Audit Log Trigger ─────────────────────────────────────────
-- Records every INSERT, UPDATE, DELETE on audited tables.
-- Runs as SECURITY DEFINER so it can bypass RLS on audit_log.

CREATE OR REPLACE FUNCTION audit_trigger_func()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO audit_log (table_name, record_id, action, new_data, changed_by)
        VALUES (TG_TABLE_NAME, NEW.id, 'INSERT', to_jsonb(NEW), auth.uid());
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit_log (table_name, record_id, action, old_data, new_data, changed_by)
        VALUES (TG_TABLE_NAME, NEW.id, 'UPDATE', to_jsonb(OLD), to_jsonb(NEW), auth.uid());
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO audit_log (table_name, record_id, action, old_data, changed_by)
        VALUES (TG_TABLE_NAME, OLD.id, 'DELETE', to_jsonb(OLD), auth.uid());
        RETURN OLD;
    END IF;
END;
$$;

CREATE TRIGGER audit_students
    AFTER INSERT OR UPDATE OR DELETE ON students
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_func();

CREATE TRIGGER audit_attendance_records
    AFTER INSERT OR UPDATE OR DELETE ON attendance_records
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_func();

CREATE TRIGGER audit_sessions
    AFTER INSERT OR UPDATE ON sessions
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_func();

CREATE TRIGGER audit_enrollments
    AFTER INSERT OR UPDATE OR DELETE ON enrollments
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_func();


-- ── updated_at Auto-Stamp ──────────────────────────────────────

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

CREATE TRIGGER set_updated_at_profiles   BEFORE UPDATE ON profiles   FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER set_updated_at_students   BEFORE UPDATE ON students   FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER set_updated_at_classes    BEFORE UPDATE ON classes    FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- ── Attendance Summary View ────────────────────────────────────
-- Used by admin dashboard and future awards logic.
-- This is a regular view (not SECURITY DEFINER) so RLS from the
-- underlying tables is inherited automatically.

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
GROUP BY s.student_id, st.full_name, se.class_id, c.name;


-- ── Session + Roster Helper ────────────────────────────────────
-- Returns a session's enrolled students with their current attendance status.
-- Call: SELECT * FROM get_session_roster('<session_uuid>');

-- Runs as caller so RLS applies — tutors see only their classes,
-- parents see only their children.
CREATE OR REPLACE FUNCTION get_session_roster(p_session_id UUID)
RETURNS TABLE (
    student_id      UUID,
    full_name       TEXT,
    attendance_id   UUID,
    status          TEXT,
    marked_at       TIMESTAMPTZ,
    notes           TEXT
) LANGUAGE SQL STABLE AS $$
    SELECT
        st.id            AS student_id,
        st.full_name,
        ar.id            AS attendance_id,
        ar.status,
        ar.marked_at,
        ar.notes
    FROM sessions se
    JOIN enrollments e  ON e.class_id  = se.class_id AND e.is_active = TRUE
    JOIN students    st ON st.id       = e.student_id AND st.is_active = TRUE
    LEFT JOIN attendance_records ar ON ar.session_id = se.id AND ar.student_id = st.id
    WHERE se.id = p_session_id
    ORDER BY st.full_name;
$$;


-- ── Offline Sync Upsert ───────────────────────────────────────
-- Called by the iOS app when reconnecting after offline use.
-- Accepts a JSON array of pending attendance records.
-- Idempotent: duplicate client_mutation_ids are silently ignored.
-- Runs as caller (no SECURITY DEFINER) so RLS continues to apply —
-- tutors can only write attendance for their own sessions.

CREATE OR REPLACE FUNCTION sync_attendance(records JSONB)
RETURNS JSONB LANGUAGE plpgsql AS $$
DECLARE
    rec       JSONB;
    v_id      UUID;
    synced    INT := 0;
    skipped   INT := 0;
BEGIN
    FOR rec IN SELECT * FROM jsonb_array_elements(records)
    LOOP
        INSERT INTO attendance_records (
            session_id,
            student_id,
            status,
            notes,
            client_mutation_id,
            marked_by,
            marked_at
        )
        VALUES (
            (rec->>'session_id')::UUID,
            (rec->>'student_id')::UUID,
            rec->>'status',
            rec->>'notes',
            rec->>'client_mutation_id',
            auth.uid(),
            COALESCE((rec->>'marked_at')::TIMESTAMPTZ, NOW())
        )
        ON CONFLICT (session_id, student_id) DO UPDATE
            SET status             = EXCLUDED.status,
                notes              = EXCLUDED.notes,
                marked_by          = EXCLUDED.marked_by,
                marked_at          = EXCLUDED.marked_at,
                client_mutation_id = EXCLUDED.client_mutation_id
        -- Only overwrite if the incoming record is newer.
        WHERE attendance_records.marked_at <= EXCLUDED.marked_at
        RETURNING id INTO v_id;

        IF FOUND THEN
            synced := synced + 1;
        ELSE
            skipped := skipped + 1;
        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'synced',  synced,
        'skipped', skipped
    );
END;
$$;
