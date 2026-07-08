-- ============================================================
-- 016 — Security fixes (audit 2026-07-06)
-- ============================================================
-- Corrects defects introduced/left open through migration 015. Safe to run
-- on environments that already applied the flawed 015 locally, and required
-- on prod once 013–015 are applied.
--
-- Fixes:
--   SEC-16a  attendance_summary lost security_invoker in 015 → RLS bypass
--   SEC-16b  attendance_summary lost the active-student/class filter (010)
--   SEC-16c  handle_new_user trusted `auth.uid() IS NULL` → self-signup admin
--   SEC-16d  parent attendance policy didn't exclude study-space rows
--   SEC-16e  erase_student / messages FK broke right-to-erasure
--   SEC-16f  link/unlink_parent_student had no pinned search_path
--   SEC-16g  sync_attendance swallowed ALL P0001 as blocked_ended_session
--   SEC-16h  ended-session guard didn't fire on DELETE
--   SEC-16i  is_feature_enabled executable by PUBLIC/anon
--   SEC-16j  dismissals FKs had no ON DELETE action
--
-- Down migration: 016_security_fixes.down.sql

-- ════════════════════════════════════════════════════════════════
-- SEC-16a/b — attendance_summary: restore security_invoker + active filter
-- ════════════════════════════════════════════════════════════════
-- 015's CREATE OR REPLACE reset the view's reloptions, silently dropping the
-- `security_invoker = true` set in 007/009 (the view then runs as its owner and
-- Supabase's default grants let any authenticated/anon reader see every
-- student's attendance) AND the `is_active` predicates added in 010 (MAINT-08).
-- Recreate with all three filters: security_invoker, active rows, no study space.
CREATE OR REPLACE VIEW attendance_summary
WITH (security_invoker = true)
AS
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
WHERE st.is_active     = TRUE
  AND c.is_active      = TRUE
  AND c.is_study_space = FALSE
GROUP BY s.student_id, st.full_name, se.class_id, c.name;

-- ════════════════════════════════════════════════════════════════
-- SEC-16c — handle_new_user must never trust metadata role
-- ════════════════════════════════════════════════════════════════
-- Public self-signup (enable_signup) also runs with auth.uid() IS NULL, so the
-- old "no JWT ⇒ trusted invite" assumption let anyone POST /auth/v1/signup with
-- {"data":{"role":"admin"}} and mint an admin. A metadata marker is no defence
-- because raw_user_meta_data is fully client-controlled at signup.
--
-- New rule: an elevated role is honoured ONLY on first-run bootstrap (no
-- profiles yet) or when an existing admin is the caller. Every other new user
-- is created as the least-privileged role ('parent') regardless of metadata.
-- The admin invite flow (web/app/actions/invite.ts) now sets the intended role
-- authoritatively via the service role AFTER the user is created.
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    requested_role TEXT    := COALESCE(NEW.raw_user_meta_data->>'role', 'parent');
    is_bootstrap   BOOLEAN := NOT EXISTS (SELECT 1 FROM profiles);
    final_role     TEXT;
BEGIN
    -- Trust the requested role only on a genuinely trusted path.
    IF is_bootstrap OR is_admin() THEN
        final_role := requested_role;
    ELSE
        final_role := 'parent';  -- least privilege; invite flow elevates later
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

-- ════════════════════════════════════════════════════════════════
-- SEC-16d — parent attendance policy: exclude study-space rows at the DB
-- ════════════════════════════════════════════════════════════════
-- The 015 invariant ("study-space attendance must NEVER appear in any parent
-- view") was enforced only in app query code; a parent hitting PostgREST
-- directly could read their child's study-space rows. Enforce it in RLS.
DROP POLICY IF EXISTS "attendance_records: parent reads own children" ON attendance_records;
CREATE POLICY "attendance_records: parent reads own children"
    ON attendance_records FOR SELECT
    TO authenticated
    USING (
        is_parent()
        AND parent_owns_student(attendance_records.student_id)
        AND NOT EXISTS (
            SELECT 1
            FROM sessions s
            JOIN classes c ON c.id = s.class_id
            WHERE s.id = attendance_records.session_id
              AND c.is_study_space
        )
    );

-- ════════════════════════════════════════════════════════════════
-- SEC-16e — right-to-erasure must handle messages
-- ════════════════════════════════════════════════════════════════
-- messages.student_id had no ON DELETE action, so DELETE FROM students in
-- erase_student() would fail with an FK violation once messaging is used.
ALTER TABLE messages DROP CONSTRAINT IF EXISTS messages_student_id_fkey;
ALTER TABLE messages
    ADD CONSTRAINT messages_student_id_fkey
    FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE SET NULL;

CREATE OR REPLACE FUNCTION erase_student(p_student_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NOT is_admin() THEN RAISE EXCEPTION 'not authorized'; END IF;
    PERFORM set_config('app.suppress_audit', 'on', true);  -- tx-local

    -- Tables without ON DELETE CASCADE from students → remove first.
    DELETE FROM messages            WHERE student_id = p_student_id;  -- message PII
    DELETE FROM dismissals          WHERE student_id = p_student_id;
    DELETE FROM food_poll_responses WHERE student_id = p_student_id;
    DELETE FROM students            WHERE id = p_student_id;  -- cascades to the rest

    -- Purge any audit snapshots referencing this student.
    DELETE FROM audit_log
        WHERE (table_name = 'students' AND record_id = p_student_id)
           OR (old_data->>'student_id' = p_student_id::text)
           OR (new_data->>'student_id' = p_student_id::text);
END;
$$;

-- ════════════════════════════════════════════════════════════════
-- SEC-16f — pin search_path on the parent-link SECURITY DEFINER functions
-- ════════════════════════════════════════════════════════════════
-- 009's hardening pass missed these two (added in 005).
ALTER FUNCTION link_parent_student(UUID, UUID)   SET search_path = public;
ALTER FUNCTION unlink_parent_student(UUID, UUID) SET search_path = public;

-- ════════════════════════════════════════════════════════════════
-- SEC-16g/h — ended-session guard: dedicated errcode + cover DELETE
-- ════════════════════════════════════════════════════════════════
-- The guard raised a generic P0001, which sync_attendance's
-- `WHEN raise_exception` handler swallowed as blocked_ended_session — so any
-- OTHER exception (e.g. the NRIC trigger) was miscounted and the client
-- silently discarded the record. Give the guard a dedicated SQLSTATE and catch
-- only that. Also fire on DELETE so records can't be destroyed post-end.
CREATE OR REPLACE FUNCTION check_session_not_ended()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_session_id UUID := COALESCE(NEW.session_id, OLD.session_id);
BEGIN
    IF EXISTS (
        SELECT 1 FROM sessions
        WHERE id = v_session_id AND ended_at IS NOT NULL
    ) THEN
        RAISE EXCEPTION 'Cannot modify attendance for ended session %', v_session_id
            USING ERRCODE = 'TA001';
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS enforce_attendance_on_open_session ON attendance_records;
CREATE TRIGGER enforce_attendance_on_open_session
BEFORE INSERT OR UPDATE OR DELETE ON attendance_records
FOR EACH ROW EXECUTE FUNCTION check_session_not_ended();

CREATE OR REPLACE FUNCTION sync_attendance(records JSONB)
RETURNS JSONB LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    rec            JSONB;
    v_id           UUID;
    synced         INT := 0;
    skipped        INT := 0;
    blocked        INT := 0;
    v_marked_at    TIMESTAMPTZ;
BEGIN
    FOR rec IN SELECT * FROM jsonb_array_elements(records)
    LOOP
        -- Clamp: do not allow a client to record a marked_at more than 5 minutes in the future.
        v_marked_at := LEAST(
            COALESCE((rec->>'marked_at')::TIMESTAMPTZ, NOW()),
            NOW() + INTERVAL '5 minutes'
        );

        BEGIN
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
                v_marked_at
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
        EXCEPTION
            -- Only the ended-session guard (dedicated errcode) counts as blocked.
            WHEN SQLSTATE 'TA001' THEN
                blocked := blocked + 1;
            -- SP-02: a differing client_mutation_id for an already-updated row
            -- collides on the UNIQUE(client_mutation_id) constraint. The row was
            -- already reconciled via (session_id, student_id), so treat as skipped.
            WHEN unique_violation THEN
                skipped := skipped + 1;
            -- Any other error (e.g. the NRIC guard) must NOT be swallowed as a
            -- blocked record — re-raise so the client keeps the pending record.
        END;
    END LOOP;

    RETURN jsonb_build_object(
        'synced',                synced,
        'skipped',               skipped,
        'blocked_ended_session', blocked
    );
END;
$$;

GRANT EXECUTE ON FUNCTION sync_attendance(JSONB) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION sync_attendance(JSONB) FROM PUBLIC, anon;

-- ════════════════════════════════════════════════════════════════
-- SEC-16i — is_feature_enabled: not executable by anon/PUBLIC
-- ════════════════════════════════════════════════════════════════
REVOKE EXECUTE ON FUNCTION is_feature_enabled(TEXT) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION is_feature_enabled(TEXT) TO authenticated, service_role;

-- ════════════════════════════════════════════════════════════════
-- SEC-16j — dismissals FKs: cascade on delete (avoid orphan/FK-violation)
-- ════════════════════════════════════════════════════════════════
ALTER TABLE dismissals DROP CONSTRAINT IF EXISTS dismissals_session_id_fkey;
ALTER TABLE dismissals
    ADD CONSTRAINT dismissals_session_id_fkey
    FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE;
ALTER TABLE dismissals DROP CONSTRAINT IF EXISTS dismissals_student_id_fkey;
ALTER TABLE dismissals
    ADD CONSTRAINT dismissals_student_id_fkey
    FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE CASCADE;
