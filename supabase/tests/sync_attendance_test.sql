-- Offline-sync integrity self-check for sync_attendance (migration 038 + 054).
-- Plain SQL + ASSERT, no pgTAP. Everything runs in one transaction and ROLLS
-- BACK, so it is safe against any environment that has the current schema.
--
-- Migration 054 requires an authenticated staff principal (admin or tutor).
-- Setup uses the local seed admin so auth.uid() / is_admin() pass, while the
-- connection remains superuser so receipt-ledger assertions can still read
-- the RLS-hidden attendance_mutation_receipts table.
--
-- Run: psql "$DB_URL" -v ON_ERROR_STOP=1 \
--        -f supabase/tests/sync_attendance_test.sql
-- Success = "sync_attendance_test: all assertions passed"; any failure aborts.
BEGIN;

CREATE FUNCTION pg_temp.as_user(p_user UUID)
RETURNS VOID
LANGUAGE SQL
AS $$
    SELECT set_config('request.jwt.claim.sub', p_user::TEXT, TRUE),
           set_config('request.jwt.claim.role', 'authenticated', TRUE);
$$;

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
    ),
    (
        '99999999-0000-0000-0000-000000000013',
        'sync_attendance cas student'
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
-- Sibling class/session: the original session is ended in assertion 8 and
-- cannot be reopened (UNIQUE class_id, session_date).
INSERT INTO classes (id, name)
VALUES (
    '99999999-0000-0000-0000-000000000011',
    'sync_attendance cas class'
);
INSERT INTO sessions (id, class_id, session_date)
VALUES (
    '99999999-0000-0000-0000-000000000012',
    '99999999-0000-0000-0000-000000000011',
    (NOW() AT TIME ZONE 'Asia/Singapore')::DATE
);
INSERT INTO enrollments (student_id, class_id, enrolled_at, is_active) VALUES
    (
        '99999999-0000-0000-0000-000000000003',
        '99999999-0000-0000-0000-000000000011',
        NOW() - INTERVAL '1 day', TRUE
    ),
    (
        '99999999-0000-0000-0000-000000000004',
        '99999999-0000-0000-0000-000000000011',
        NOW() - INTERVAL '1 day', TRUE
    ),
    (
        '99999999-0000-0000-0000-000000000013',
        '99999999-0000-0000-0000-000000000011',
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

CREATE FUNCTION pg_temp.payload(
    p_student UUID,
    p_status TEXT,
    p_marked_at TIMESTAMPTZ,
    p_mutation TEXT,
    p_session UUID
)
RETURNS JSONB
LANGUAGE SQL
AS $$
    SELECT jsonb_build_array(jsonb_build_object(
        'session_id', p_session,
        'student_id', p_student,
        'status', p_status,
        'marked_at', p_marked_at,
        'client_mutation_id', p_mutation
    ));
$$;

CREATE FUNCTION pg_temp.payload(
    p_student UUID,
    p_status TEXT,
    p_marked_at TIMESTAMPTZ,
    p_mutation TEXT,
    p_observed_marked_at TIMESTAMPTZ,
    p_session UUID
)
RETURNS JSONB
LANGUAGE SQL
AS $$
    SELECT jsonb_build_array(jsonb_build_object(
        'session_id', p_session,
        'student_id', p_student,
        'status', p_status,
        'marked_at', p_marked_at,
        'client_mutation_id', p_mutation,
        'observed_marked_at', p_observed_marked_at
    ));
$$;

DO $$
DECLARE
    v_session UUID := '99999999-0000-0000-0000-000000000002';
    v_student UUID := '99999999-0000-0000-0000-000000000003';
    v_other_student UUID := '99999999-0000-0000-0000-000000000004';
    -- Local seed admin (supabase/seed.sql). Staff gate from migration 054.
    v_actor UUID := '00000000-0000-0000-0000-000000000001';
    v_first_marked_at TIMESTAMPTZ;
    v_before TIMESTAMPTZ;
    v_after TIMESTAMPTZ;
    v_cas_session UUID := '99999999-0000-0000-0000-000000000012';
    v_cas_student UUID := '99999999-0000-0000-0000-000000000013';
    v_cas_marked_at TIMESTAMPTZ;
    r JSONB;
BEGIN
    PERFORM pg_temp.as_user(v_actor);

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
    ASSERT (
        SELECT marked_by = v_actor
        FROM attendance_records
        WHERE session_id = v_session AND student_id = v_student
    ), 'fresh record did not bind marked_by to the authenticated staff actor';

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
          AND actor_id = v_actor
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

    -- 6. A null status clears the row, records both the replaced mutation and
    -- the clear mutation, and remains idempotent on replay.
    r := sync_attendance(pg_temp.payload(
        v_student, NULL, NOW(), 'synctest-clear'
    ));
    ASSERT (r->>'synced')::INTEGER = 1,
       'clear mutation should sync, got ' || r::TEXT;
    ASSERT NOT EXISTS (
        SELECT 1 FROM attendance_records
        WHERE session_id = v_session AND student_id = v_student
    ), 'clear mutation left an attendance row';
    ASSERT (
        SELECT COUNT(*) = 2
        FROM attendance_mutation_receipts
        WHERE mutation_id IN ('synctest-3', 'synctest-clear')
          AND session_id = v_session
          AND student_id = v_student
          AND actor_id = v_actor
    ), 'clear did not preserve both mutation receipts';
    r := sync_attendance(pg_temp.payload(
        v_student, 'absent', NOW(), 'synctest-clear'
    ));
    ASSERT (r->>'skipped')::INTEGER = 1,
       'clear replay should be skipped, got ' || r::TEXT;
    ASSERT NOT EXISTS (
        SELECT 1 FROM attendance_records
        WHERE session_id = v_session AND student_id = v_student
    ), 'clear replay recreated attendance';
    r := sync_attendance(pg_temp.payload(
        v_student, 'present', NOW(), 'synctest-5'
    ));
    ASSERT (r->>'synced')::INTEGER = 1,
       'post-clear mark should sync, got ' || r::TEXT;

    -- 7. Reusing an older, receipted mutation identifier for another logical
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

    -- 8. Ended-session retries remain distinguishable from ordinary skips and
    -- leave the last accepted record untouched.
    -- Session lifecycle is RPC-gated when auth.uid() is set (migration 038), so
    -- open the dedicated write path only for this fixture update.
    PERFORM set_config('app.session_lifecycle_write', 'on', TRUE);
    UPDATE sessions SET ended_at = NOW() WHERE id = v_session;
    PERFORM set_config('app.session_lifecycle_write', 'off', TRUE);
    r := sync_attendance(pg_temp.payload(
        v_student, 'late', NOW(), 'synctest-4'
    ));
    ASSERT (r->>'blocked_ended_session')::INTEGER = 1
       AND (r->>'synced')::INTEGER = 0,
       'ended session must be reported as blocked, got ' || r::TEXT;
    ASSERT (
        SELECT status = 'present'
           AND client_mutation_id = 'synctest-5'
        FROM attendance_records
        WHERE session_id = v_session AND student_id = v_student
    ), 'ended-session retry changed the accepted record';

    -- 9. Non-staff principals must fail closed (migration 054 staff gate).
    -- Seed parent: authenticated, but neither admin nor tutor.
    PERFORM pg_temp.as_user('00000000-0000-0000-0000-000000000003');
    BEGIN
        PERFORM sync_attendance(pg_temp.payload(
            v_student, 'late', NOW(), 'synctest-parent'
        ));
        RAISE EXCEPTION 'parent sync_attendance was accepted';
    EXCEPTION
        WHEN insufficient_privilege THEN NULL;
        WHEN OTHERS THEN
            IF SQLERRM IS DISTINCT FROM 'not authorized' THEN
                RAISE;
            END IF;
    END;

    BEGIN
        PERFORM apply_attendance_clear(
            v_session, v_student, 'cas-parent-clear', TRUE, NULL
        );
        RAISE EXCEPTION 'parent atomic attendance clear was accepted';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;

    -- 10–14. Offline observed_marked_at CAS (migration 058).
    -- Original session was ended above and cannot be reopened.
    PERFORM pg_temp.as_user(v_actor);

    -- 10. Delayed distinct mutation without the observed key still overwrites.
    r := sync_attendance(pg_temp.payload(
        v_student, 'present', '2099-01-01T00:00:00Z', 'cas-legacy-1',
        v_cas_session
    ));
    ASSERT (r->>'synced')::INTEGER = 1
       AND COALESCE((r->>'skipped_conflict')::INTEGER, 0) = 0,
       'cas legacy seed should sync, got ' || r::TEXT;
    r := sync_attendance(pg_temp.payload(
        v_student, 'late', '2000-01-01T00:00:00Z', 'cas-legacy-2',
        v_cas_session
    ));
    ASSERT (r->>'synced')::INTEGER = 1
       AND COALESCE((r->>'skipped_conflict')::INTEGER, 0) = 0,
       'legacy delayed mutation without observed key should overwrite, got '
       || r::TEXT;
    ASSERT (
        SELECT status = 'late' AND client_mutation_id = 'cas-legacy-2'
        FROM attendance_records
        WHERE session_id = v_cas_session AND student_id = v_student
    ), 'legacy path lost arrival-order overwrite';

    -- 11. Observed unmarked (JSON null) after a live kiosk-style insert is a
    -- conflict; the kiosk value must stay.
    r := sync_attendance(pg_temp.payload(
        v_other_student, 'present', NOW(), 'cas-kiosk-1', v_cas_session
    ));
    ASSERT (r->>'synced')::INTEGER = 1,
       'cas kiosk insert should sync, got ' || r::TEXT;
    r := sync_attendance(pg_temp.payload(
        v_other_student, 'late', '2000-01-01T00:00:00Z', 'cas-stale-1',
        NULL::TIMESTAMPTZ, v_cas_session
    ));
    ASSERT (r->>'skipped_conflict')::INTEGER = 1
       AND (r->>'synced')::INTEGER = 0
       AND (r->>'skipped')::INTEGER = 0,
       'stale unmarked observation should skip as conflict, got ' || r::TEXT;
    ASSERT (
        SELECT status = 'present' AND client_mutation_id = 'cas-kiosk-1'
        FROM attendance_records
        WHERE session_id = v_cas_session AND student_id = v_other_student
    ), 'conflict skip overwrote the kiosk row';

    -- 12. Matching observed_marked_at allows a later authorised correction.
    SELECT marked_at INTO v_cas_marked_at
    FROM attendance_records
    WHERE session_id = v_cas_session AND student_id = v_other_student;
    r := sync_attendance(pg_temp.payload(
        v_other_student, 'absent', NOW(), 'cas-correct-1',
        v_cas_marked_at, v_cas_session
    ));
    ASSERT (r->>'synced')::INTEGER = 1
       AND COALESCE((r->>'skipped_conflict')::INTEGER, 0) = 0,
       'matching observed_marked_at should apply, got ' || r::TEXT;
    ASSERT (
        SELECT status = 'absent' AND client_mutation_id = 'cas-correct-1'
        FROM attendance_records
        WHERE session_id = v_cas_session AND student_id = v_other_student
    ), 'matching CAS did not apply the authorised correction';

    -- 13. Replay of the same mutation id still increments skipped, not conflict.
    r := sync_attendance(pg_temp.payload(
        v_other_student, 'present', NOW(), 'cas-correct-1',
        v_cas_marked_at, v_cas_session
    ));
    ASSERT (r->>'skipped')::INTEGER = 1
       AND (r->>'synced')::INTEGER = 0
       AND COALESCE((r->>'skipped_conflict')::INTEGER, 0) = 0,
       'replay should increment skipped not skipped_conflict, got ' || r::TEXT;
    ASSERT (
        SELECT status = 'absent' AND client_mutation_id = 'cas-correct-1'
        FROM attendance_records
        WHERE session_id = v_cas_session AND student_id = v_other_student
    ), 'replay after CAS hit mutated the accepted row';

    -- 14. A conflict in the same batch must not abort later rows.
    r := sync_attendance(
        pg_temp.payload(
            v_other_student, 'present', NOW(), 'cas-batch-conflict',
            NULL::TIMESTAMPTZ, v_cas_session
        )
        || pg_temp.payload(
            v_cas_student, 'present', NOW(), 'cas-batch-ok',
            NULL::TIMESTAMPTZ, v_cas_session
        )
    );
    ASSERT (r->>'skipped_conflict')::INTEGER = 1
       AND (r->>'synced')::INTEGER = 1
       AND (r->>'skipped')::INTEGER = 0,
       'batch must count conflict and continue, got ' || r::TEXT;
    ASSERT (
        SELECT status = 'absent' AND client_mutation_id = 'cas-correct-1'
        FROM attendance_records
        WHERE session_id = v_cas_session AND student_id = v_other_student
    ), 'batch conflict overwrote the live row';
    ASSERT (
        SELECT status = 'present' AND client_mutation_id = 'cas-batch-ok'
        FROM attendance_records
        WHERE session_id = v_cas_session AND student_id = v_cas_student
    ), 'batch did not insert the later valid row';

    -- An empty observed clear never removes an existing mark, nor records a
    -- successful receipt for a rejected mutation.
    r := sync_attendance(pg_temp.payload(
        v_cas_student, NULL, NOW(), 'cas-empty-clear-conflict',
        NULL::TIMESTAMPTZ, v_cas_session
    ));
    ASSERT (r->>'skipped_conflict')::INTEGER = 1,
        'empty observed clear must preserve an existing row: ' || r::TEXT;
    ASSERT NOT EXISTS (
        SELECT 1 FROM attendance_mutation_receipts
        WHERE mutation_id = 'cas-empty-clear-conflict'
    ), 'conflicted clear incorrectly recorded an accepted receipt';

    SELECT marked_at INTO v_cas_marked_at FROM attendance_records
    WHERE session_id = v_cas_session AND student_id = v_cas_student;
    r := sync_attendance(pg_temp.payload(
        v_cas_student, NULL, NOW(), 'cas-matching-clear',
        v_cas_marked_at, v_cas_session
    ));
    ASSERT (r->>'synced')::INTEGER = 1 AND NOT EXISTS (
        SELECT 1 FROM attendance_records
        WHERE session_id = v_cas_session AND student_id = v_cas_student
    ), 'matching observed clear did not remove the row';
    ASSERT EXISTS (
        SELECT 1 FROM attendance_mutation_receipts
        WHERE mutation_id = 'cas-batch-ok'
    ), 'clear lost the previous mutation receipt';
    r := sync_attendance(pg_temp.payload(
        v_cas_student, NULL, NOW(), 'cas-matching-clear',
        v_cas_marked_at, v_cas_session
    ));
    ASSERT (r->>'skipped')::INTEGER = 1, 'accepted clear was not replay-safe';
    r := sync_attendance(pg_temp.payload(
        v_cas_student, NULL, NOW(), 'cas-empty-clear-ok',
        NULL::TIMESTAMPTZ, v_cas_session
    ));
    ASSERT (r->>'synced')::INTEGER = 1 AND EXISTS (
        SELECT 1 FROM attendance_mutation_receipts
        WHERE mutation_id = 'cas-empty-clear-ok'
    ), 'empty clear must retain an accepted receipt';
    r := sync_attendance(pg_temp.payload(
        v_cas_student, 'late', NOW(), 'cas-write-after-clear',
        v_cas_marked_at, v_cas_session
    ));
    ASSERT (r->>'skipped_conflict')::INTEGER = 1 AND NOT EXISTS (
        SELECT 1 FROM attendance_records
        WHERE session_id = v_cas_session AND student_id = v_cas_student
    ), 'stale observed update recreated a cleared row';

    RAISE NOTICE 'sync_attendance_test: all assertions passed';
END;
$$;

ROLLBACK;
