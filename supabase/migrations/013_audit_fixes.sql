-- ============================================================
-- 013 — Audit fixes (IMPROVEMENTS.md second wave)
-- ============================================================
-- Closes: SEC-05, UX-06, DOC-02, MAINT-11, SP-02 (+ MAINT-09/MAINT-13 doc notes)
-- Down migration: 013_audit_fixes.down.sql

-- ════════════════════════════════════════════════════════════════
-- SEC-05 — handle_new_user must not let invite metadata mint admins
-- ════════════════════════════════════════════════════════════════
-- A requested role other than the default is only honoured when the
-- caller is already an admin, OR when profiles is empty (first-run
-- bootstrap of the very first admin). Otherwise the role is forced to
-- 'tutor'. The CHECK constraint still rejects unknown role strings.
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    requested_role TEXT := COALESCE(NEW.raw_user_meta_data->>'role', 'tutor');
    is_bootstrap   BOOLEAN := NOT EXISTS (SELECT 1 FROM profiles);
    final_role     TEXT;
BEGIN
    -- Default privilege is 'tutor'. A non-default role is honoured only on a
    -- trusted path:
    --   • first-run bootstrap (no profiles yet), or
    --   • a server-side invite — GoTrue's admin invite runs with no end-user JWT,
    --     so auth.uid() IS NULL; that path is already gated by the admin check in
    --     web/app/actions/invite.ts, or
    --   • the caller is itself an admin.
    -- Otherwise (an authenticated non-admin somehow triggering profile creation
    -- with an elevated role) the role is forced down to 'tutor'.
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

-- ════════════════════════════════════════════════════════════════
-- UX-06 — drop the hard-coded subject CHECK on result_slips
-- ════════════════════════════════════════════════════════════════
-- Allowed subjects are now enforced in application code so a new subject
-- (Physics, Chemistry, a language) doesn't require a migration.
ALTER TABLE result_slips DROP CONSTRAINT IF EXISTS result_slips_subject_check;

-- ════════════════════════════════════════════════════════════════
-- DOC-02 — validate recurrence_rule looks like an RRULE
-- ════════════════════════════════════════════════════════════════
-- Lightweight guard: NULL is allowed (one-off class); otherwise the
-- string must begin with FREQ= (RFC 5545 RRULE, e.g. FREQ=WEEKLY;BYDAY=MO).
-- Client-side validation in ClassFormView gives the friendlier error.
ALTER TABLE classes DROP CONSTRAINT IF EXISTS classes_recurrence_rule_check;
ALTER TABLE classes ADD CONSTRAINT classes_recurrence_rule_check
    CHECK (recurrence_rule IS NULL OR recurrence_rule ~ '^FREQ=');

-- ════════════════════════════════════════════════════════════════
-- MAINT-11 / SP-02 — sync_attendance: surface ended-session rejections
-- and guard the client_mutation_id unique constraint
-- ════════════════════════════════════════════════════════════════
-- Builds on 010_audit_fixes.sql:
--  • MAINT-11: a third counter `blocked_ended_session` distinguishes records
--    rejected by the open-session guard (008_attendance_session_guard.sql)
--    from records legitimately skipped because they were stale.
--  • SP-02: a second ON CONFLICT target on client_mutation_id prevents an
--    unhandled unique-violation when two devices use different mutation ids
--    for the same (session_id, student_id).
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
            -- The open-session guard raises when the target session has ended.
            WHEN raise_exception THEN
                blocked := blocked + 1;
            -- SP-02: a differing client_mutation_id for an already-updated row
            -- collides on the UNIQUE(client_mutation_id) constraint. The row was
            -- already reconciled via (session_id, student_id), so treat as skipped.
            WHEN unique_violation THEN
                skipped := skipped + 1;
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
-- MAINT-09 / MAINT-13 — documentation notes (no schema change)
-- ════════════════════════════════════════════════════════════════
COMMENT ON COLUMN sessions.sub_tutor_id IS
    'Substitute tutor. NOTE (MAINT-09): added by both 005_sprint_features.sql and '
    '006_session_end.sql (IF NOT EXISTS) due to live-DB drift; the live schema matches '
    'the full migration sequence.';
COMMENT ON POLICY "profiles: read own or admin" ON profiles IS
    'MAINT-13: tutors can only read their own profile row. fetchTutors() returns a '
    'complete list only for admins; any future tutor-facing peer selector must use a '
    'SECURITY DEFINER function instead of a direct profiles query.';
