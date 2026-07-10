-- Down migration for 013_audit_fixes.sql
-- Restores the pre-013 state (handle_new_user from 001, sync_attendance from 010,
-- re-adds the result_slips subject CHECK, drops the recurrence_rule CHECK).

-- SEC-05 revert → 001_schema.sql body
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    INSERT INTO profiles (id, full_name, role)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email),
        COALESCE(NEW.raw_user_meta_data->>'role', 'tutor')
    )
    ON CONFLICT (id) DO NOTHING;
    RETURN NEW;
END;
$$;

-- UX-06 revert → re-add subject CHECK
ALTER TABLE result_slips ADD CONSTRAINT result_slips_subject_check
    CHECK (subject IS NULL OR subject IN ('Math', 'English'));

-- DOC-02 revert → drop the RRULE CHECK
ALTER TABLE classes DROP CONSTRAINT IF EXISTS classes_recurrence_rule_check;

-- MAINT-11 / SP-02 revert → 010_audit_fixes.sql body (synced/skipped only)
CREATE OR REPLACE FUNCTION sync_attendance(records JSONB)
RETURNS JSONB LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    rec            JSONB;
    v_id           UUID;
    synced         INT := 0;
    skipped        INT := 0;
    v_marked_at    TIMESTAMPTZ;
BEGIN
    FOR rec IN SELECT * FROM jsonb_array_elements(records)
    LOOP
        v_marked_at := LEAST(
            COALESCE((rec->>'marked_at')::TIMESTAMPTZ, NOW()),
            NOW() + INTERVAL '5 minutes'
        );

        INSERT INTO attendance_records (
            session_id, student_id, status, notes,
            client_mutation_id, marked_by, marked_at
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
        WHERE attendance_records.marked_at <= EXCLUDED.marked_at
        RETURNING id INTO v_id;

        IF FOUND THEN synced := synced + 1; ELSE skipped := skipped + 1; END IF;
    END LOOP;

    RETURN jsonb_build_object('synced', synced, 'skipped', skipped);
END;
$$;

GRANT EXECUTE ON FUNCTION sync_attendance(JSONB) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION sync_attendance(JSONB) FROM PUBLIC, anon;
