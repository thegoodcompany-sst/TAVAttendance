-- Behaviour checks for migration 056 (absence_informed companion column).
-- Plain SQL + ASSERT, one transaction, ROLLBACK at the end — safe on any env.
--
-- Run: psql "$DB_URL" -v ON_ERROR_STOP=1 \
--        -f supabase/tests/absence_informed_test.sql
-- Success = "absence_informed_test: all assertions passed"; any failure aborts.
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
    '56000000-0000-0000-0000-000000000001',
    'absence_informed test class'
);
INSERT INTO class_tutor_assignments (class_id, tutor_id)
VALUES (
    '56000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000002'
);
INSERT INTO sessions (id, class_id, session_date)
VALUES (
    '56000000-0000-0000-0000-000000000002',
    '56000000-0000-0000-0000-000000000001',
    (NOW() AT TIME ZONE 'Asia/Singapore')::DATE
);
-- Past session for retrospective marking (must be before Singapore today).
SELECT set_config('app.retrospective_session_create', 'on', TRUE);
INSERT INTO sessions (id, class_id, session_date, ended_at)
VALUES (
    '56000000-0000-0000-0000-000000000003',
    '56000000-0000-0000-0000-000000000001',
    (NOW() AT TIME ZONE 'Asia/Singapore')::DATE - 5,
    NOW()
);
SELECT set_config('app.retrospective_session_create', 'off', TRUE);

INSERT INTO students (id, full_name) VALUES
    ('56000000-0000-0000-0000-000000000010', 'absence informed student'),
    ('56000000-0000-0000-0000-000000000011', 'absence summary student');
INSERT INTO enrollments (student_id, class_id, enrolled_at, is_active) VALUES
    (
        '56000000-0000-0000-0000-000000000010',
        '56000000-0000-0000-0000-000000000001',
        NOW() - INTERVAL '30 days', TRUE
    ),
    (
        '56000000-0000-0000-0000-000000000011',
        '56000000-0000-0000-0000-000000000001',
        NOW() - INTERVAL '30 days', TRUE
    );

SELECT pg_temp.as_user('00000000-0000-0000-0000-000000000001');

DO $$
DECLARE
    v_session UUID := '56000000-0000-0000-0000-000000000002';
    v_past UUID := '56000000-0000-0000-0000-000000000003';
    v_student UUID := '56000000-0000-0000-0000-000000000010';
    v_summary UUID := '56000000-0000-0000-0000-000000000011';
    v_actor UUID := '00000000-0000-0000-0000-000000000001';
    r JSONB;
    v_informed BOOLEAN;
    v_row attendance_records%ROWTYPE;
BEGIN
    PERFORM pg_temp.as_user(v_actor);

    -- 1. Direct upsert: absent + informed=TRUE persists TRUE.
    INSERT INTO attendance_records (
        session_id, student_id, status, absence_informed,
        marked_by, marked_at, client_mutation_id
    ) VALUES (
        v_session, v_student, 'absent', TRUE,
        v_actor, NOW(), 'absence-informed-test-1'
    );
    SELECT absence_informed INTO v_informed
    FROM attendance_records
    WHERE session_id = v_session AND student_id = v_student;
    ASSERT v_informed IS TRUE,
           'absent + absence_informed=TRUE did not persist';

    -- 2. Late with absence_informed=TRUE is nulled by the integrity trigger.
    UPDATE attendance_records
    SET status = 'late',
        absence_informed = TRUE,
        client_mutation_id = 'absence-informed-test-2'
    WHERE session_id = v_session AND student_id = v_student;
    SELECT absence_informed INTO v_informed
    FROM attendance_records
    WHERE session_id = v_session AND student_id = v_student;
    ASSERT v_informed IS NULL,
           'late status left absence_informed set';

    -- 3. Absent informed, then update to present → flag nulled.
    UPDATE attendance_records
    SET status = 'absent',
        absence_informed = TRUE,
        client_mutation_id = 'absence-informed-test-3'
    WHERE session_id = v_session AND student_id = v_student;
    UPDATE attendance_records
    SET status = 'present',
        client_mutation_id = 'absence-informed-test-4'
    WHERE session_id = v_session AND student_id = v_student;
    SELECT absence_informed INTO v_informed
    FROM attendance_records
    WHERE session_id = v_session AND student_id = v_student;
    ASSERT v_informed IS NULL,
           'present status left absence_informed set';

    -- 4. sync_attendance round-trips absence_informed.
    PERFORM clear_attendance(v_session, v_student, 'absence-informed-clear-1');
    r := sync_attendance(jsonb_build_array(jsonb_build_object(
        'session_id', v_session,
        'student_id', v_student,
        'status', 'absent',
        'absence_informed', TRUE,
        'marked_at', '2099-01-01T00:00:00Z',
        'client_mutation_id', 'absence-informed-sync-1'
    )));
    ASSERT (r->>'synced')::INTEGER = 1,
           'sync_attendance should sync absence_informed row, got ' || r::TEXT;
    SELECT absence_informed INTO v_informed
    FROM attendance_records
    WHERE session_id = v_session AND student_id = v_student;
    ASSERT v_informed IS TRUE,
           'sync_attendance dropped absence_informed';

    -- 5. mark_retrospective_attendance carries FALSE; only the 4-arg form exists.
    ASSERT to_regprocedure(
        'public.mark_retrospective_attendance(uuid,uuid,text)'
    ) IS NULL,
           'old 3-arg mark_retrospective_attendance overload still present';
    ASSERT to_regprocedure(
        'public.mark_retrospective_attendance(uuid,uuid,text,boolean)'
    ) IS NOT NULL,
           '4-arg mark_retrospective_attendance missing';

    UPDATE feature_flags SET enabled = TRUE WHERE key = 'retrospective_sessions';
    SELECT * INTO v_row
    FROM mark_retrospective_attendance(v_past, v_student, 'absent', FALSE);
    ASSERT v_row.status = 'absent' AND v_row.absence_informed IS FALSE,
           'retrospective mark did not persist absence_informed=FALSE';

    -- 6. attendance_summary splits informed vs uninformed.
    -- Second past session so summary has two absences for one student.
    PERFORM set_config('app.retrospective_session_create', 'on', TRUE);
    INSERT INTO sessions (id, class_id, session_date, ended_at)
    VALUES (
        '56000000-0000-0000-0000-000000000004',
        '56000000-0000-0000-0000-000000000001',
        (NOW() AT TIME ZONE 'Asia/Singapore')::DATE - 6,
        NOW()
    );
    PERFORM set_config('app.retrospective_session_create', 'off', TRUE);

    PERFORM mark_retrospective_attendance(
        '56000000-0000-0000-0000-000000000004',
        v_summary, 'absent', TRUE
    );
    PERFORM mark_retrospective_attendance(
        v_past, v_summary, 'absent', FALSE
    );

    ASSERT EXISTS (
        SELECT 1 FROM attendance_summary
        WHERE student_id = v_summary
          AND class_id = '56000000-0000-0000-0000-000000000001'
          AND absent_count = 2
          AND absent_informed_count = 1
          AND absent_uninformed_count = 1
    ), 'attendance_summary did not split informed/uninformed absences';
END;
$$;

ROLLBACK;

\echo 'absence_informed_test: all assertions passed'
