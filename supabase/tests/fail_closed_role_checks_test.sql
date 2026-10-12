-- Missing profiles, deleted accounts and stale relationships must not authorize RPCs.
BEGIN;
SET LOCAL plpgsql.check_asserts = on;

CREATE FUNCTION pg_temp.as_user(p_user UUID)
RETURNS VOID LANGUAGE SQL AS $$
    SELECT set_config('request.jwt.claim.sub', COALESCE(p_user::TEXT, ''), TRUE),
           set_config('request.jwt.claims', '{}', TRUE),
           set_config('request.jwt.claim.role', 'authenticated', TRUE);
$$;

CREATE FUNCTION pg_temp.expect_denied(p_sql TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE p_sql;
    RAISE EXCEPTION 'expected authorization denial: %', p_sql;
EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'not authorized' THEN RAISE; END IF;
END;
$$;

CREATE FUNCTION pg_temp.assert_no_role()
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    ASSERT get_my_role() IS NULL, 'absent profile must retain NULL role';
    ASSERT is_admin() IS FALSE, 'absent profile must not be admin';
    ASSERT is_tutor() IS FALSE, 'absent profile must not be tutor';
    ASSERT is_parent() IS FALSE, 'absent profile must not be parent';
    ASSERT is_arrival_station() IS FALSE, 'absent profile must not be station';
END;
$$;

CREATE FUNCTION pg_temp.submit_event()
RETURNS INTEGER LANGUAGE SQL AS $$
    SELECT submit_app_events(
        '[{"platform":"web","event_type":"tap","session_id":"role-boundary","name":"role_boundary_probe"}]'::JSONB);
$$;

CREATE FUNCTION pg_temp.assert_rpcs_denied()
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    PERFORM pg_temp.expect_denied($q$SELECT get_or_create_today_session(
        '10000000-0000-0000-0000-000000000001')$q$);
    PERFORM pg_temp.expect_denied($q$SELECT * FROM class_punctuality(
        '10000000-0000-0000-0000-000000000001', CURRENT_DATE - 7, CURRENT_DATE + 1)$q$);
    PERFORM pg_temp.expect_denied($q$SELECT * FROM get_study_space_roster(
        '61000000-0000-0000-0000-000000000011')$q$);
    PERFORM pg_temp.expect_denied($q$SELECT * FROM get_retrospective_session_roster(
        '61000000-0000-0000-0000-000000000012')$q$);
    PERFORM pg_temp.expect_denied($q$SELECT get_student_nfc_binding(
        '20000000-0000-0000-0000-000000000001')$q$);
    PERFORM pg_temp.expect_denied($q$SELECT arrival_station_tap('04A1B2C3')$q$);
    PERFORM pg_temp.expect_denied($q$SELECT pair_nfc_chip(
        '20000000-0000-0000-0000-000000000001', '04A1B2C3')$q$);
    PERFORM pg_temp.expect_denied($q$SELECT sync_attendance('[]'::JSONB)$q$);
END;
$$;

UPDATE feature_flags SET enabled = TRUE
WHERE key IN ('study_space_tracking', 'retrospective_sessions', 'nfc_sign_in', 'analytics');

INSERT INTO classes (id, name, is_study_space, is_active)
VALUES ('61000000-0000-0000-0000-000000000010', 'Role boundary study space', TRUE, TRUE);
SELECT set_config('app.retrospective_session_create', 'on', TRUE);
INSERT INTO sessions (id, class_id, session_date) VALUES
    ('61000000-0000-0000-0000-000000000011',
     '61000000-0000-0000-0000-000000000010', (NOW() AT TIME ZONE 'Asia/Singapore')::DATE),
    ('61000000-0000-0000-0000-000000000012',
     '10000000-0000-0000-0000-000000000001', (NOW() AT TIME ZONE 'Asia/Singapore')::DATE - 1);
SELECT set_config('app.retrospective_session_create', 'off', TRUE);
UPDATE enrollments SET enrolled_at = NOW() - INTERVAL '10 days'
WHERE class_id = '10000000-0000-0000-0000-000000000001';

SELECT pg_temp.as_user('00000000-0000-0000-0000-000000000001');
SET LOCAL ROLE authenticated;
DO $$
BEGIN
    ASSERT is_admin() AND NOT is_tutor() AND NOT is_parent() AND NOT is_arrival_station();
    ASSERT pg_temp.submit_event() = 1;
    ASSERT (get_or_create_today_session('10000000-0000-0000-0000-000000000001')).id
        = '30000000-0000-0000-0000-000000000001'::UUID;
    ASSERT (SELECT total_count FROM class_punctuality(
        '10000000-0000-0000-0000-000000000001', CURRENT_DATE - 7, CURRENT_DATE + 1)) = 3;
    ASSERT (SELECT COUNT(*) FROM get_study_space_roster(
        '61000000-0000-0000-0000-000000000011')) > 0;
    ASSERT (SELECT COUNT(*) FROM get_retrospective_session_roster(
        '61000000-0000-0000-0000-000000000012')) = 3;
    PERFORM pair_nfc_chip('20000000-0000-0000-0000-000000000001', '04A1B2C3');
    ASSERT get_student_nfc_binding('20000000-0000-0000-0000-000000000001')->>'chip_uid_suffix' = 'B2C3';
END;
$$;

SELECT pg_temp.as_user('00000000-0000-0000-0000-000000000002');
DO $$
BEGIN
    ASSERT NOT is_admin() AND is_tutor() AND NOT is_parent() AND NOT is_arrival_station();
    ASSERT pg_temp.submit_event() = 1;
    ASSERT (get_or_create_today_session('10000000-0000-0000-0000-000000000001')).id IS NOT NULL;
    ASSERT (SELECT total_count FROM class_punctuality(
        '10000000-0000-0000-0000-000000000001', CURRENT_DATE - 7, CURRENT_DATE + 1)) = 3;
    ASSERT (SELECT COUNT(*) FROM get_retrospective_session_roster(
        '61000000-0000-0000-0000-000000000012')) = 3;
    PERFORM pg_temp.expect_denied($q$SELECT * FROM get_study_space_roster(
        '61000000-0000-0000-0000-000000000011')$q$);
END;
$$;

SELECT pg_temp.as_user('00000000-0000-0000-0000-000000000003');
DO $$
BEGIN
    ASSERT NOT is_admin() AND NOT is_tutor() AND is_parent() AND NOT is_arrival_station();
    ASSERT pg_temp.submit_event() = 1;
    PERFORM pg_temp.assert_rpcs_denied();
END;
$$;

SELECT pg_temp.as_user('00000000-0000-0000-0000-000000000004');
DO $$
BEGIN
    ASSERT NOT is_admin() AND NOT is_tutor() AND NOT is_parent() AND is_arrival_station();
    ASSERT arrival_station_tap('not-a-card')->>'outcome' = 'unknown_card';
END;
$$;

-- No profile and no auth row: models a subject in a still-unexpired deleted-user JWT.
SELECT pg_temp.as_user('61000000-0000-0000-0000-000000000099');
SELECT pg_temp.assert_no_role();
SELECT pg_temp.assert_rpcs_denied();
SELECT pg_temp.expect_denied('SELECT pg_temp.submit_event()');
SELECT pg_temp.as_user(NULL);
SELECT pg_temp.assert_no_role();
SELECT pg_temp.assert_rpcs_denied();
SELECT pg_temp.expect_denied('SELECT pg_temp.submit_event()');

RESET ROLE;
SELECT pg_temp.as_user(NULL);
-- A demoted tutor retains an assignment; that relationship is no longer authority.
UPDATE profiles SET role = 'parent' WHERE id = '00000000-0000-0000-0000-000000000002';
SELECT pg_temp.as_user('00000000-0000-0000-0000-000000000002');
SET LOCAL ROLE authenticated;
SELECT pg_temp.assert_rpcs_denied();
RESET ROLE;
SELECT pg_temp.as_user(NULL);
DELETE FROM profiles WHERE id IN (
    '00000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000003');
DO $$
BEGIN
    ASSERT EXISTS (SELECT 1 FROM auth.users WHERE id = '00000000-0000-0000-0000-000000000002');
    ASSERT EXISTS (SELECT 1 FROM class_tutor_assignments WHERE tutor_id = '00000000-0000-0000-0000-000000000002');
    ASSERT EXISTS (SELECT 1 FROM parent_student_links WHERE parent_id = '00000000-0000-0000-0000-000000000003');
END;
$$;
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('00000000-0000-0000-0000-000000000002');
SELECT pg_temp.assert_no_role();
SELECT pg_temp.assert_rpcs_denied();
SELECT pg_temp.expect_denied('SELECT pg_temp.submit_event()');
SELECT pg_temp.as_user('00000000-0000-0000-0000-000000000003');
SELECT pg_temp.assert_no_role();
SELECT pg_temp.assert_rpcs_denied();
SELECT pg_temp.expect_denied('SELECT pg_temp.submit_event()');

-- PostgREST also supplies the subject via the JSON claim representation.
SELECT set_config('request.jwt.claim.sub', '', TRUE);
SELECT set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","role":"authenticated"}', TRUE);
SELECT pg_temp.assert_no_role();
SELECT pg_temp.assert_rpcs_denied();
SELECT pg_temp.expect_denied('SELECT pg_temp.submit_event()');

RESET ROLE;
SELECT pg_temp.as_user(NULL);
SET LOCAL ROLE service_role;
SELECT pg_temp.assert_no_role();
RESET ROLE;
DO $$
DECLARE
    v_signature TEXT;
    v_proc pg_proc%ROWTYPE;
BEGIN
    ASSERT (SELECT COUNT(*) FROM app_events WHERE name = 'role_boundary_probe') = 3,
        'only authorized role controls may write telemetry';
    FOREACH v_signature IN ARRAY ARRAY[
        'public.is_admin()', 'public.is_tutor()', 'public.is_parent()', 'public.is_arrival_station()'
    ] LOOP
        SELECT * INTO STRICT v_proc FROM pg_proc WHERE oid = v_signature::REGPROCEDURE;
        ASSERT v_proc.prosecdef AND v_proc.provolatile = 's';
        ASSERT 'search_path=public, pg_temp' = ANY(v_proc.proconfig);
        ASSERT NOT has_function_privilege('anon', v_signature, 'EXECUTE');
        ASSERT has_function_privilege('authenticated', v_signature, 'EXECUTE');
        ASSERT has_function_privilege('service_role', v_signature, 'EXECUTE');
    END LOOP;
END;
$$;
ROLLBACK;
