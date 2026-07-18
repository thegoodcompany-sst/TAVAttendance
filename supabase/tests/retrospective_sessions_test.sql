-- Behaviour checks for migration 037. Runs against a locally reset/seeded DB.
-- Run: psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/retrospective_sessions_test.sql
BEGIN;

CREATE FUNCTION pg_temp.as_user(p_user UUID)
RETURNS VOID LANGUAGE SQL AS $$
    SELECT set_config('request.jwt.claim.sub', p_user::TEXT, TRUE),
           set_config('request.jwt.claim.role', 'authenticated', TRUE);
$$;

CREATE FUNCTION pg_temp.expect_error(p_sql TEXT, p_message TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE p_sql;
    RAISE EXCEPTION 'expected failure containing: %', p_message;
EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'expected failure containing: ' || p_message THEN RAISE; END IF;
    ASSERT POSITION(p_message IN SQLERRM) > 0,
           'wrong error: expected ' || p_message || ', got ' || SQLERRM;
END;
$$;

INSERT INTO auth.users (
    id, email, encrypted_password, email_confirmed_at, role, aud,
    raw_user_meta_data, created_at, updated_at
) VALUES (
    '37000000-0000-0000-0000-000000000004', 'unrelated-037@tava.dev',
    crypt('test', gen_salt('bf')), NOW(), 'authenticated', 'authenticated',
    '{"full_name":"Unrelated Tutor","role":"tutor"}', NOW(), NOW()
);
UPDATE profiles SET role = 'tutor'
WHERE id = '37000000-0000-0000-0000-000000000004';

INSERT INTO classes (id, name)
VALUES ('37000000-0000-0000-0000-000000000010', 'Retrospective test class');
INSERT INTO class_tutor_assignments (class_id, tutor_id)
VALUES ('37000000-0000-0000-0000-000000000010', '00000000-0000-0000-0000-000000000002');
INSERT INTO students (id, full_name) VALUES
    ('37000000-0000-0000-0000-000000000020', 'Historical Member'),
    ('37000000-0000-0000-0000-000000000021', 'Joined Later'),
    ('37000000-0000-0000-0000-000000000022', 'Attendance Only');
INSERT INTO enrollments (student_id, class_id, enrolled_at, unenrolled_at, is_active) VALUES
    ('37000000-0000-0000-0000-000000000020', '37000000-0000-0000-0000-000000000010', NOW() - INTERVAL '20 days', NOW() - INTERVAL '5 days', FALSE),
    ('37000000-0000-0000-0000-000000000021', '37000000-0000-0000-0000-000000000010', NOW() - INTERVAL '2 days', NULL, TRUE);
SELECT set_config('app.retrospective_session_create', 'on', TRUE);
INSERT INTO sessions (id, class_id, session_date, ended_at)
VALUES (
    '37000000-0000-0000-0000-000000000030',
    '37000000-0000-0000-0000-000000000010',
    (NOW() AT TIME ZONE 'Asia/Singapore')::DATE - 10,
    NULL
);
INSERT INTO attendance_records (session_id, student_id, status, client_mutation_id)
VALUES (
    '37000000-0000-0000-0000-000000000030',
    '37000000-0000-0000-0000-000000000022', 'absent', 'retrospective-037-fixture'
);
UPDATE sessions SET ended_at = NOW()
WHERE id = '37000000-0000-0000-0000-000000000030';
SELECT set_config('app.retrospective_session_create', 'off', TRUE);

SELECT pg_temp.as_user('00000000-0000-0000-0000-000000000001');

-- OFF means every entry point fails closed.
SELECT pg_temp.expect_error(
    $$SELECT create_retrospective_session('37000000-0000-0000-0000-000000000010', CURRENT_DATE - 3, NULL, NULL, NULL)$$,
    'disabled');
SELECT pg_temp.expect_error(
    $$SELECT update_retrospective_session('37000000-0000-0000-0000-000000000030', NULL, NULL, NULL)$$,
    'disabled');
SELECT pg_temp.expect_error(
    $$SELECT * FROM get_retrospective_session_roster('37000000-0000-0000-0000-000000000030')$$,
    'disabled');
SELECT pg_temp.expect_error(
    $$SELECT mark_retrospective_attendance('37000000-0000-0000-0000-000000000030', '37000000-0000-0000-0000-000000000020', 'present')$$,
    'disabled');

UPDATE feature_flags SET enabled = TRUE WHERE key = 'retrospective_sessions';
UPDATE feature_flags SET enabled = TRUE WHERE key = 'session_notes';

DO $$
DECLARE
    v_admin_session sessions;
    v_tutor_session sessions;
    v_before_enrollments BIGINT;
    v_roster UUID[];
BEGIN
    SELECT f.* INTO v_admin_session
    FROM create_retrospective_session(
        '37000000-0000-0000-0000-000000000010', CURRENT_DATE - 4,
        'Admin topic', 'Admin note', '00000000-0000-0000-0000-000000000002'
    ) AS f;
    ASSERT v_admin_session.class_id = '37000000-0000-0000-0000-000000000010',
           'admin create failed';

    PERFORM pg_temp.as_user('00000000-0000-0000-0000-000000000002');
    SELECT f.* INTO v_tutor_session
    FROM create_retrospective_session(
        '37000000-0000-0000-0000-000000000010', CURRENT_DATE - 3,
        'Tutor topic', NULL, NULL
    ) AS f;
    ASSERT v_tutor_session.id IS NOT NULL, 'assigned tutor create failed';
    SELECT f.* INTO v_tutor_session
    FROM update_retrospective_session(
        v_tutor_session.id, 'Tutor updated topic', NULL, NULL
    ) AS f;
    ASSERT v_tutor_session.topic = 'Tutor updated topic',
           'assigned tutor update failed';
    PERFORM mark_retrospective_attendance(
        v_tutor_session.id, '37000000-0000-0000-0000-000000000021', 'late');
    ASSERT (SELECT status = 'late' FROM attendance_records
            WHERE session_id = v_tutor_session.id
              AND student_id = '37000000-0000-0000-0000-000000000021'),
           'assigned tutor attendance correction failed';

    PERFORM pg_temp.as_user('00000000-0000-0000-0000-000000000001');
    SELECT ARRAY_AGG(r.student_id ORDER BY r.student_id)
    INTO v_roster
    FROM get_retrospective_session_roster('37000000-0000-0000-0000-000000000030') r;
    ASSERT '37000000-0000-0000-0000-000000000020'::UUID = ANY(v_roster),
           'historically enrolled student missing';
    ASSERT NOT ('37000000-0000-0000-0000-000000000021'::UUID = ANY(v_roster)),
           'student enrolled after session date included';
    ASSERT '37000000-0000-0000-0000-000000000022'::UUID = ANY(v_roster),
           'attendance-only student missing';

    SELECT COUNT(*) INTO v_before_enrollments FROM enrollments;
    PERFORM mark_retrospective_attendance(
        '37000000-0000-0000-0000-000000000030',
        '37000000-0000-0000-0000-000000000021', 'present');
    ASSERT (SELECT status = 'present' FROM attendance_records
            WHERE session_id = '37000000-0000-0000-0000-000000000030'
              AND student_id = '37000000-0000-0000-0000-000000000021'),
           'historical attendance RPC did not write ended session';
    ASSERT (SELECT COUNT(*) FROM enrollments) = v_before_enrollments,
           'adding a session-only student changed enrollment';
END $$;

SELECT set_config('app.retrospective_attendance_write', 'off', TRUE);
SELECT pg_temp.expect_error(
    $$UPDATE attendance_records SET status = 'late' WHERE session_id = '37000000-0000-0000-0000-000000000030' AND student_id = '37000000-0000-0000-0000-000000000021'$$,
    'Cannot modify attendance for ended session');
SELECT pg_temp.expect_error(
    $$UPDATE sessions SET session_date = session_date - 1 WHERE id = '37000000-0000-0000-0000-000000000030'$$,
    'class and date are immutable');
SELECT pg_temp.expect_error(
    $$DELETE FROM sessions WHERE id = '37000000-0000-0000-0000-000000000030'$$,
    'cannot be deleted');
SELECT pg_temp.expect_error(
    $$INSERT INTO sessions (class_id, session_date) VALUES ('37000000-0000-0000-0000-000000000010', CURRENT_DATE - 20)$$,
    'must be created through');
SELECT pg_temp.expect_error(
    $$SELECT create_retrospective_session('37000000-0000-0000-0000-000000000010', CURRENT_DATE, NULL, NULL, NULL)$$,
    'before today');
SELECT pg_temp.expect_error(
    $$SELECT create_retrospective_session('37000000-0000-0000-0000-000000000010', CURRENT_DATE + 1, NULL, NULL, NULL)$$,
    'before today');
SELECT pg_temp.expect_error(
    $$SELECT create_retrospective_session('57000000-0000-0000-0000-000000000001', CURRENT_DATE - 2, NULL, NULL, NULL)$$,
    'not eligible');
SELECT pg_temp.expect_error(
    $$SELECT create_retrospective_session('37000000-0000-0000-0000-000000000010', CURRENT_DATE - 4, NULL, NULL, NULL)$$,
    'already exists');
SELECT pg_temp.expect_error(
    $$SELECT create_retrospective_session('37000000-0000-0000-0000-000000000010', CURRENT_DATE - 5, NULL, NULL, '00000000-0000-0000-0000-000000000003')$$,
    'invalid substitute');

SELECT pg_temp.as_user('37000000-0000-0000-0000-000000000004');
SELECT pg_temp.expect_error(
    $$SELECT create_retrospective_session('37000000-0000-0000-0000-000000000010', CURRENT_DATE - 6, NULL, NULL, NULL)$$,
    'not authorized');
SELECT pg_temp.as_user('00000000-0000-0000-0000-000000000003');
SELECT pg_temp.expect_error(
    $$SELECT get_retrospective_session_roster('37000000-0000-0000-0000-000000000030')$$,
    'not authorized');

DO $$ BEGIN RAISE NOTICE 'retrospective_sessions_test: all assertions passed'; END $$;
ROLLBACK;
