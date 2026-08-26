-- Behaviour checks for migration 059 (NFC arrival station).
-- Run: psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/nfc_arrival_station_test.sql
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
    '59000000-0000-0000-0000-000000000001', 'station-059@tava.dev',
    crypt('test', gen_salt('bf')), NOW(), 'authenticated', 'authenticated',
    '{"full_name":"Arrival Station","role":"parent"}', NOW(), NOW()
);
UPDATE profiles
SET role = 'arrival_station', full_name = 'Arrival Station'
WHERE id = '59000000-0000-0000-0000-000000000001';

INSERT INTO classes (id, name, schedule_day, schedule_time, is_active, is_study_space)
VALUES (
    '59000000-0000-0000-0000-000000000010',
    'NFC today class',
    to_char((NOW() AT TIME ZONE 'Asia/Singapore')::DATE, 'FMDay'),
    '23:59:00',
    TRUE,
    FALSE
), (
    '59000000-0000-0000-0000-000000000011',
    'NFC other-day class',
    CASE to_char((NOW() AT TIME ZONE 'Asia/Singapore')::DATE, 'FMDay')
        WHEN 'Monday' THEN 'Tuesday'
        ELSE 'Monday'
    END,
    '19:30:00',
    TRUE,
    FALSE
);

INSERT INTO students (id, full_name, is_active) VALUES
    ('59000000-0000-0000-0000-000000000020', 'NFC On Roster', TRUE),
    ('59000000-0000-0000-0000-000000000021', 'NFC Other Day', TRUE),
    ('59000000-0000-0000-0000-000000000022', 'NFC Inactive', FALSE);

INSERT INTO enrollments (student_id, class_id, enrolled_at, is_active) VALUES
    ('59000000-0000-0000-0000-000000000020', '59000000-0000-0000-0000-000000000010', NOW() - INTERVAL '10 days', TRUE),
    ('59000000-0000-0000-0000-000000000021', '59000000-0000-0000-0000-000000000011', NOW() - INTERVAL '10 days', TRUE);

DO $$
BEGIN
    ASSERT normalize_nfc_chip_uid('04:a1:b2:c3') = '04A1B2C3',
           'colon UID should normalise';
    ASSERT normalize_nfc_chip_uid(' 04a1b2c3d4e5f6 ') = '04A1B2C3D4E5F6',
           '7-byte UID should normalise';
    ASSERT normalize_nfc_chip_uid('zzzz') IS NULL,
           'garbage UID should be rejected';
    ASSERT normalize_nfc_chip_uid('ABC') IS NULL,
           'odd-length UID should be rejected';

    ASSERT class_meets_on_singapore_date(
            to_char((NOW() AT TIME ZONE 'Asia/Singapore')::DATE, 'FMDay'),
            NULL,
            (NOW() AT TIME ZONE 'Asia/Singapore')::DATE
           ),
           'schedule_day today should meet';
    ASSERT NOT class_meets_on_singapore_date(
            CASE to_char((NOW() AT TIME ZONE 'Asia/Singapore')::DATE, 'FMDay')
                WHEN 'Monday' THEN 'Tuesday'
                ELSE 'Monday'
            END,
            NULL,
            (NOW() AT TIME ZONE 'Asia/Singapore')::DATE
           ),
           'other weekday should not meet';
    ASSERT class_meets_on_singapore_date(
            NULL,
            'FREQ=WEEKLY;BYDAY=' || CASE lower(to_char((NOW() AT TIME ZONE 'Asia/Singapore')::DATE, 'FMDay'))
                WHEN 'monday' THEN 'MO'
                WHEN 'tuesday' THEN 'TU'
                WHEN 'wednesday' THEN 'WE'
                WHEN 'thursday' THEN 'TH'
                WHEN 'friday' THEN 'FR'
                WHEN 'saturday' THEN 'SA'
                ELSE 'SU'
            END,
            (NOW() AT TIME ZONE 'Asia/Singapore')::DATE
           ),
           'BYDAY today should meet';
    ASSERT class_meets_on_singapore_date(NULL, NULL, (NOW() AT TIME ZONE 'Asia/Singapore')::DATE),
           'ad hoc class should always meet';
END;
$$;

SELECT pg_temp.as_user('00000000-0000-0000-0000-000000000001');

SELECT pg_temp.expect_error(
    $$SELECT pair_nfc_chip('59000000-0000-0000-0000-000000000020', '04A1B2C3')$$,
    'disabled');
SELECT pg_temp.expect_error(
    $$SELECT arrival_station_tap('04A1B2C3')$$,
    'disabled');

UPDATE feature_flags SET enabled = TRUE WHERE key = 'nfc_sign_in';
UPDATE feature_flags SET enabled = FALSE WHERE key = 'test_mode';

DO $nfc$
DECLARE
    v_bind JSONB;
    v_tap JSONB;
    v_status TEXT;
    v_count INTEGER;
BEGIN
    v_bind := pair_nfc_chip('59000000-0000-0000-0000-000000000020', '04:a1:b2:c3');
    ASSERT v_bind->>'chip_uid_suffix' = 'B2C3', 'pair suffix';

    v_bind := pair_nfc_chip('59000000-0000-0000-0000-000000000020', '04A1B2C3');
    ASSERT v_bind->>'chip_uid_suffix' = 'B2C3', 'idempotent re-pair';

    PERFORM pair_nfc_chip('59000000-0000-0000-0000-000000000021', 'AABBCCDD');

    PERFORM pg_temp.as_user('00000000-0000-0000-0000-000000000003');
    PERFORM pg_temp.expect_error(
        $$SELECT pair_nfc_chip('59000000-0000-0000-0000-000000000020', '04A1B2C3')$$,
        'not authorized');
    PERFORM pg_temp.expect_error(
        $$SELECT arrival_station_tap('04A1B2C3')$$,
        'not authorized');

    PERFORM pg_temp.as_user('00000000-0000-0000-0000-000000000002');
    PERFORM pg_temp.expect_error(
        $$SELECT pair_nfc_chip('59000000-0000-0000-0000-000000000020', '04A1B2C3')$$,
        'not authorized');
    PERFORM pg_temp.expect_error(
        $$SELECT arrival_station_tap('04A1B2C3')$$,
        'not authorized');

    PERFORM pg_temp.as_user('59000000-0000-0000-0000-000000000001');
    PERFORM pg_temp.expect_error(
        $$SELECT pair_nfc_chip('59000000-0000-0000-0000-000000000020', '04A1B2C3')$$,
        'not authorized');
    -- RLS assertions must run as `authenticated`; superuser bypasses policies.
    PERFORM set_config('role', 'authenticated', true);
    ASSERT (SELECT COUNT(*) FROM students) = 0,
           'station must not read students through RLS';
    ASSERT (SELECT COUNT(*) FROM nfc_tag_bindings) = 0,
           'station must not read nfc_tag_bindings through RLS';
    BEGIN
        INSERT INTO attendance_records (
            session_id, student_id, status, client_mutation_id
        ) VALUES (
            '30000000-0000-0000-0000-000000000001',
            '59000000-0000-0000-0000-000000000020',
            'present', 'station-direct-insert'
        );
        RAISE EXCEPTION 'station direct attendance insert should fail';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM = 'station direct attendance insert should fail' THEN RAISE; END IF;
    END;
    PERFORM set_config('role', 'postgres', true);
    ASSERT NOT EXISTS (
        SELECT 1 FROM attendance_records
        WHERE client_mutation_id = 'station-direct-insert'
    ), 'station must not persist a direct attendance row';

    v_tap := arrival_station_tap('zz');
    ASSERT v_tap->>'outcome' = 'unknown_card', 'invalid uid is unknown';

    v_tap := arrival_station_tap('FFFFFFFF');
    ASSERT v_tap->>'outcome' = 'unknown_card', 'unbound uid is unknown';
    ASSERT v_tap->>'chip_uid' = 'FFFFFFFF', 'unknown card should show uid for pairing';

    v_tap := arrival_station_tap('AABBCCDD');
    ASSERT v_tap->>'outcome' = 'not_on_roster',
           'bound student on a non-today class must fail closed';
    ASSERT v_tap->>'full_name' = 'NFC Other Day', 'not-on-roster names the child';

    v_tap := arrival_station_tap('04A1B2C3');
    ASSERT v_tap->>'outcome' = 'on_time', 'today class before schedule is on time';
    ASSERT v_tap->>'full_name' = 'NFC On Roster', 'on-time names the child';
    SELECT ar.status INTO v_status
    FROM attendance_records ar
    JOIN sessions s ON s.id = ar.session_id
    WHERE ar.student_id = '59000000-0000-0000-0000-000000000020'
      AND s.class_id = '59000000-0000-0000-0000-000000000010'
      AND s.session_date = (NOW() AT TIME ZONE 'Asia/Singapore')::DATE;
    ASSERT v_status = 'present', 'stored status must be present';
    ASSERT (SELECT marked_by FROM attendance_records ar
            JOIN sessions s ON s.id = ar.session_id
            WHERE ar.student_id = '59000000-0000-0000-0000-000000000020'
              AND s.class_id = '59000000-0000-0000-0000-000000000010')
           = '59000000-0000-0000-0000-000000000001',
           'marked_by must be the station actor';

    v_tap := arrival_station_tap('04A1B2C3');
    ASSERT v_tap->>'outcome' = 'already_signed_in', 'second tap is already signed in';

    PERFORM pg_temp.as_user('00000000-0000-0000-0000-000000000001');
    PERFORM clear_attendance(s.id, '59000000-0000-0000-0000-000000000020', 'nfc-clear-late')
    FROM sessions s
    WHERE s.class_id = '59000000-0000-0000-0000-000000000010'
      AND s.session_date = (NOW() AT TIME ZONE 'Asia/Singapore')::DATE;
    UPDATE classes
    SET schedule_time = '00:00:00'
    WHERE id = '59000000-0000-0000-0000-000000000010';

    PERFORM pg_temp.as_user('59000000-0000-0000-0000-000000000001');
    v_tap := arrival_station_tap('04A1B2C3');
    ASSERT v_tap->>'outcome' = 'late', 'past schedule_time is late';

    PERFORM pg_temp.as_user('00000000-0000-0000-0000-000000000001');
    UPDATE attendance_records SET status = 'absent'
    WHERE student_id = '59000000-0000-0000-0000-000000000020';

    PERFORM pg_temp.as_user('59000000-0000-0000-0000-000000000001');
    v_tap := arrival_station_tap('04A1B2C3');
    ASSERT v_tap->>'outcome' = 'marked_absent', 'absent is not auto-overridden';

    PERFORM pg_temp.as_user('00000000-0000-0000-0000-000000000001');
    PERFORM clear_attendance(s.id, '59000000-0000-0000-0000-000000000020', 'nfc-clear-dismiss')
    FROM sessions s
    WHERE s.class_id = '59000000-0000-0000-0000-000000000010'
      AND s.session_date = (NOW() AT TIME ZONE 'Asia/Singapore')::DATE;
    INSERT INTO dismissals (session_id, student_id, dismissed_at, dismissed_by)
    SELECT s.id, '59000000-0000-0000-0000-000000000020', NOW(),
           '00000000-0000-0000-0000-000000000001'
    FROM sessions s
    WHERE s.class_id = '59000000-0000-0000-0000-000000000010'
      AND s.session_date = (NOW() AT TIME ZONE 'Asia/Singapore')::DATE;

    PERFORM pg_temp.as_user('59000000-0000-0000-0000-000000000001');
    v_tap := arrival_station_tap('04A1B2C3');
    ASSERT v_tap->>'outcome' = 'already_dismissed', 'dismissed tap is not a sign-in';

    PERFORM pg_temp.as_user('00000000-0000-0000-0000-000000000001');
    PERFORM pg_temp.expect_error(
        $$SELECT pair_nfc_chip('59000000-0000-0000-0000-000000000022', '11223344')$$,
        'not eligible');

    -- Reissue: old UID dies, new UID works after clearing dismissal/attendance.
    DELETE FROM dismissals WHERE student_id = '59000000-0000-0000-0000-000000000020';
    PERFORM clear_attendance(s.id, '59000000-0000-0000-0000-000000000020', 'nfc-clear-reissue')
    FROM sessions s
    WHERE s.class_id = '59000000-0000-0000-0000-000000000010'
      AND s.session_date = (NOW() AT TIME ZONE 'Asia/Singapore')::DATE;
    UPDATE classes SET schedule_time = '23:59:00'
    WHERE id = '59000000-0000-0000-0000-000000000010';
    PERFORM pair_nfc_chip('59000000-0000-0000-0000-000000000020', '99AABBCC');
    SELECT COUNT(*) INTO v_count
    FROM nfc_tag_bindings
    WHERE student_id = '59000000-0000-0000-0000-000000000020'
      AND revoked_at IS NULL;
    ASSERT v_count = 1, 'reissue leaves one active card';

    PERFORM pg_temp.as_user('59000000-0000-0000-0000-000000000001');
    v_tap := arrival_station_tap('04A1B2C3');
    ASSERT v_tap->>'outcome' = 'unknown_card', 'revoked UID must fail closed';
    v_tap := arrival_station_tap('99AABBCC');
    ASSERT v_tap->>'outcome' = 'on_time', 'reissued UID signs in';

    PERFORM pg_temp.as_user('00000000-0000-0000-0000-000000000001');
    PERFORM revoke_nfc_chip_for_student('59000000-0000-0000-0000-000000000020');
    PERFORM pg_temp.as_user('59000000-0000-0000-0000-000000000001');
    v_tap := arrival_station_tap('99AABBCC');
    ASSERT v_tap->>'outcome' = 'unknown_card', 'revoked student card is unknown';
END;
$nfc$;

ROLLBACK;
