-- Offline-sync integrity self-check for sync_attendance (migration 038).
-- Plain SQL + ASSERT, no pgTAP. Everything runs in one transaction and ROLLS
-- BACK, so it is safe against any environment that has the current schema.
--
-- Run: psql "$DB_URL" -v ON_ERROR_STOP=1 \
--        -f supabase/tests/sync_attendance_test.sql
-- Success = "sync_attendance_test: all assertions passed"; any failure aborts.
BEGIN;

INSERT INTO classes (id, name)
VALUES (
    '99999999-0000-0000-0000-000000000001',
    'sync_attendance test class'
);
INSERT INTO sessions (id, class_id, session_date)
VALUES (
    '99999999-0000-0000-0000-000000000002',
    '99999999-0000-0000-0000-000000000001',
    (NOW() AT TIME ZONE 'Asia/Singapore')::DATE
);
INSERT INTO students (id, full_name) VALUES
    (
        '99999999-0000-0000-0000-000000000003',
        'sync_attendance test student'
    ),
    (
        '99999999-0000-0000-0000-000000000004',
        'sync_attendance collision student'
    );
INSERT INTO enrollments (student_id, class_id, enrolled_at, is_active) VALUES
    (
        '99999999-0000-0000-0000-000000000003',
        '99999999-0000-0000-0000-000000000001',
        NOW() - INTERVAL '1 day', TRUE
    ),
    (
        '99999999-0000-0000-0000-000000000004',
        '99999999-0000-0000-0000-000000000001',
        NOW() - INTERVAL '1 day', TRUE
    );

CREATE FUNCTION pg_temp.payload(
    p_student UUID,
    p_status TEXT,
    p_marked_at TIMESTAMPTZ,
    p_mutation TEXT
)
RETURNS JSONB
LANGUAGE SQL
AS $$
    SELECT jsonb_build_array(jsonb_build_object(
        'session_id', '99999999-0000-0000-0000-000000000002',
        'student_id', p_student,
        'status', p_status,
        -- Deliberately retained in the test payload: migration 038 must ignore
        -- this untrusted device clock and stamp server arrival time instead.
        'marked_at', p_marked_at,
        'client_mutation_id', p_mutation
    ));
$$;

DO $$
DECLARE
    v_session UUID := '99999999-0000-0000-0000-000000000002';
    v_student UUID := '99999999-0000-0000-0000-000000000003';
    v_other_student UUID := '99999999-0000-0000-0000-000000000004';
    v_first_marked_at TIMESTAMPTZ;
    v_before TIMESTAMPTZ;
    v_after TIMESTAMPTZ;
    r JSONB;
BEGIN
    -- 1. A fresh offline mutation syncs and is stamped with server time, not
    -- the caller's far-future device clock.
    v_before := clock_timestamp();
    r := sync_attendance(pg_temp.payload(
        v_student, 'present', '2099-01-01T00:00:00Z', 'synctest-1'
    ));
    v_after := clock_timestamp();
    ASSERT (r->>'synced')::INTEGER = 1
       AND (r->>'skipped')::INTEGER = 0,
       'fresh record should sync, got ' || r::TEXT;
    SELECT marked_at INTO v_first_marked_at
    FROM attendance_records
    WHERE session_id = v_session AND student_id = v_student;
    ASSERT v_first_marked_at BETWEEN v_before AND v_after,
       'fresh record trusted the device timestamp instead of server arrival';

    -- 2. An exact mutation replay is idempotent even when its other fields
    -- differ. It neither duplicates nor mutates the accepted row.
    r := sync_attendance(pg_temp.payload(
        v_student, 'late', '2000-01-01T00:00:00Z', 'synctest-1'
    ));
    ASSERT (r->>'skipped')::INTEGER = 1
       AND (r->>'synced')::INTEGER = 0,
       'exact replay should be skipped, got ' || r::TEXT;
    ASSERT (
        SELECT COUNT(*) = 1
           AND MIN(status) = 'present'
           AND MIN(marked_at) = v_first_marked_at
        FROM attendance_records
        WHERE session_id = v_session AND student_id = v_student
    ), 'exact replay changed or duplicated the accepted row';

    -- 3. A distinct mutation wins by server arrival order even if its device
    -- clock claims it is decades older.
    v_before := clock_timestamp();
    r := sync_attendance(pg_temp.payload(
        v_student, 'late', '2000-01-01T00:00:00Z', 'synctest-2'
    ));
    v_after := clock_timestamp();
    ASSERT (r->>'synced')::INTEGER = 1,
       'new stale-clock mutation should sync, got ' || r::TEXT;
    ASSERT (
        SELECT status = 'late'
           AND client_mutation_id = 'synctest-2'
           AND marked_at BETWEEN v_before AND v_after
        FROM attendance_records
        WHERE session_id = v_session AND student_id = v_student
    ), 'arrival order did not replace the stale-clock mutation safely';
    ASSERT EXISTS (
        SELECT 1 FROM attendance_mutation_receipts
        WHERE mutation_id = 'synctest-1'
          AND session_id = v_session
          AND student_id = v_student
          AND actor_id IS NULL
          AND accepted_at = v_first_marked_at
    ), 'replaced mutation did not create a bound durable receipt';

    -- 4. A delayed replay of mutation A remains idempotent after mutation B
    -- has replaced the row's current mutation ID. The durable receipt must
    -- stop A from rolling the newer state back.
    r := sync_attendance(pg_temp.payload(
        v_student, 'absent', '2099-01-01T00:00:00Z', 'synctest-1'
    ));
    ASSERT (r->>'skipped')::INTEGER = 1
       AND (r->>'synced')::INTEGER = 0,
       'delayed accepted replay should be skipped, got ' || r::TEXT;
    ASSERT (
        SELECT status = 'late'
           AND client_mutation_id = 'synctest-2'
        FROM attendance_records
        WHERE session_id = v_session AND student_id = v_student
    ), 'delayed replay overwrote the newer accepted mutation';

    -- 5. A far-future device clock receives the same treatment: the new
    -- mutation wins, but its marked_at remains bounded by server time.
    v_before := clock_timestamp();
    r := sync_attendance(pg_temp.payload(
        v_student, 'present', '2099-01-01T00:00:00Z', 'synctest-3'
    ));
    v_after := clock_timestamp();
    ASSERT (r->>'synced')::INTEGER = 1,
       'new future-clock mutation should sync, got ' || r::TEXT;
    ASSERT (
        SELECT status = 'present'
           AND client_mutation_id = 'synctest-3'
           AND marked_at BETWEEN v_before AND v_after
        FROM attendance_records
        WHERE session_id = v_session AND student_id = v_student
    ), 'future device clock escaped server-time stamping';

    -- 6. Reusing an older, receipted mutation identifier for another logical
    -- row is a hard collision. It must not be silently counted as skipped.
    BEGIN
        PERFORM sync_attendance(pg_temp.payload(
            v_other_student, 'present', NOW(), 'synctest-1'
        ));
        RAISE EXCEPTION 'mutation identifier collision was silently accepted';
    EXCEPTION
        WHEN unique_violation THEN NULL;
    END;
    ASSERT NOT EXISTS (
        SELECT 1 FROM attendance_records
        WHERE session_id = v_session AND student_id = v_other_student
    ), 'collision created attendance for the wrong logical row';

    -- 7. Ended-session retries remain distinguishable from ordinary skips and
    -- leave the last accepted record untouched.
    UPDATE sessions SET ended_at = NOW() WHERE id = v_session;
    r := sync_attendance(pg_temp.payload(
        v_student, 'late', NOW(), 'synctest-4'
    ));
    ASSERT (r->>'blocked_ended_session')::INTEGER = 1
       AND (r->>'synced')::INTEGER = 0,
       'ended session must be reported as blocked, got ' || r::TEXT;
    ASSERT (
        SELECT status = 'present'
           AND client_mutation_id = 'synctest-3'
        FROM attendance_records
        WHERE session_id = v_session AND student_id = v_student
    ), 'ended-session retry changed the accepted record';

    RAISE NOTICE 'sync_attendance_test: all assertions passed';
END;
$$;

ROLLBACK;
