-- Behaviour checks for migration 038. Runs against a locally reset/seeded DB.
-- Run: psql "$DB_URL" -v ON_ERROR_STOP=1 \
--        -f supabase/tests/security_boundary_hardening_test.sql
BEGIN;

CREATE FUNCTION pg_temp.as_user(p_user UUID)
RETURNS VOID
LANGUAGE SQL
AS $$
    SELECT set_config('request.jwt.claim.sub', p_user::TEXT, TRUE),
           set_config('request.jwt.claim.role', 'authenticated', TRUE);
$$;

CREATE FUNCTION pg_temp.expect_rejected(p_sql TEXT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        RETURN;
    END;
    RAISE EXCEPTION 'expected statement to be rejected: %', p_sql;
END;
$$;

CREATE FUNCTION pg_temp.assert_true(p_value BOOLEAN, p_message TEXT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    IF COALESCE(p_value, FALSE) IS NOT TRUE THEN
        RAISE EXCEPTION 'assertion failed: %', p_message;
    END IF;
END;
$$;

-- A second tutor is used for both future-assignment and valid-substitution
-- checks.  The auth trigger creates a parent profile, which trusted setup then
-- promotes explicitly.
INSERT INTO auth.users (
    id, email, encrypted_password, email_confirmed_at, role, aud,
    raw_user_meta_data, created_at, updated_at
) VALUES (
    '38000000-0000-0000-0000-000000000001',
    'security-038-tutor@tava.dev',
    crypt('test', gen_salt('bf')), NOW(), 'authenticated', 'authenticated',
    '{"full_name":"Security 038 Tutor"}', NOW(), NOW()
);
UPDATE profiles SET role = 'tutor'
WHERE id = '38000000-0000-0000-0000-000000000001';

INSERT INTO auth.users (
    id, email, encrypted_password, email_confirmed_at, role, aud,
    raw_user_meta_data, created_at, updated_at
) VALUES (
    '38000000-0000-0000-0000-000000000002',
    'security-038-admin@tava.dev',
    crypt('test', gen_salt('bf')), NOW(), 'authenticated', 'authenticated',
    '{"full_name":"Security 038 Admin"}', NOW(), NOW()
);
UPDATE profiles SET role = 'admin'
WHERE id = '38000000-0000-0000-0000-000000000002';

-- A co-parent linked to the same child proves that upload authorization is
-- bound to the reserving actor, not merely to the child folder.
INSERT INTO auth.users (
    id, email, encrypted_password, email_confirmed_at, role, aud,
    raw_user_meta_data, created_at, updated_at
) VALUES (
    '38000000-0000-0000-0000-000000000003',
    'security-038-coparent@tava.dev',
    crypt('test', gen_salt('bf')), NOW(), 'authenticated', 'authenticated',
    '{"full_name":"Security 038 Co-parent"}', NOW(), NOW()
);

INSERT INTO classes (id, name, subject) VALUES
    ('38000000-0000-0000-0000-000000000010', 'Security 038 A', 'Mathematics'),
    ('38000000-0000-0000-0000-000000000011', 'Security 038 B', 'English'),
    ('38000000-0000-0000-0000-000000000012', 'Security 038 Future', 'Mathematics');

INSERT INTO class_tutor_assignments (
    class_id, tutor_id, assigned_from
) VALUES
    ('38000000-0000-0000-0000-000000000010',
     '00000000-0000-0000-0000-000000000002',
     (NOW() AT TIME ZONE 'Asia/Singapore')::DATE - 1),
    ('38000000-0000-0000-0000-000000000011',
     '00000000-0000-0000-0000-000000000002',
     (NOW() AT TIME ZONE 'Asia/Singapore')::DATE - 1),
    ('38000000-0000-0000-0000-000000000012',
     '38000000-0000-0000-0000-000000000001',
     (NOW() AT TIME ZONE 'Asia/Singapore')::DATE + 7);

INSERT INTO students (id, full_name, avatar_url) VALUES
    ('38000000-0000-0000-0000-000000000020', 'Same Class', NULL),
    ('38000000-0000-0000-0000-000000000021', 'Other Class', NULL),
    ('38000000-0000-0000-0000-000000000022', 'Future Student', NULL),
    ('38000000-0000-0000-0000-000000000023', 'Anonymise Me',
     '38000000-0000-0000-0000-000000000023/photo.jpg'),
    ('38000000-0000-0000-0000-000000000024', 'Erase Me', NULL),
    ('38000000-0000-0000-0000-000000000026', 'Enrolled Too Late', NULL);

UPDATE students
SET date_of_birth = '2012-01-02',
    notes = 'Staff-only child note',
    created_by = '00000000-0000-0000-0000-000000000001'
WHERE id = '38000000-0000-0000-0000-000000000020';

INSERT INTO enrollments (
    student_id, class_id, enrolled_at, is_active
) VALUES
    ('38000000-0000-0000-0000-000000000020',
     '38000000-0000-0000-0000-000000000010', NOW() - INTERVAL '20 days', TRUE),
    ('38000000-0000-0000-0000-000000000021',
     '38000000-0000-0000-0000-000000000011', NOW() - INTERVAL '20 days', TRUE),
    ('38000000-0000-0000-0000-000000000022',
     '38000000-0000-0000-0000-000000000012', NOW() - INTERVAL '20 days', TRUE),
    ('38000000-0000-0000-0000-000000000023',
     '38000000-0000-0000-0000-000000000010', NOW() - INTERVAL '20 days', TRUE),
    -- Deliberately starts after today's covered class-B session. It must not
    -- leak this student's photo/roster row to that session's substitute.
    ('38000000-0000-0000-0000-000000000020',
     '38000000-0000-0000-0000-000000000011', NOW() + INTERVAL '1 day', TRUE),
    ('38000000-0000-0000-0000-000000000026',
     '38000000-0000-0000-0000-000000000010', NOW(), TRUE);

INSERT INTO parent_student_links (parent_id, student_id) VALUES
    ('00000000-0000-0000-0000-000000000003',
     '38000000-0000-0000-0000-000000000020'),
    ('38000000-0000-0000-0000-000000000003',
     '38000000-0000-0000-0000-000000000020'),
    ('00000000-0000-0000-0000-000000000003',
     '38000000-0000-0000-0000-000000000023');

INSERT INTO sessions (id, class_id, session_date) VALUES
    ('38000000-0000-0000-0000-000000000030',
     '38000000-0000-0000-0000-000000000010',
     (NOW() AT TIME ZONE 'Asia/Singapore')::DATE),
    ('38000000-0000-0000-0000-000000000031',
     '38000000-0000-0000-0000-000000000011',
     (NOW() AT TIME ZONE 'Asia/Singapore')::DATE),
    ('38000000-0000-0000-0000-000000000032',
     '38000000-0000-0000-0000-000000000011',
     (NOW() AT TIME ZONE 'Asia/Singapore')::DATE + 1);

UPDATE sessions
SET notes = 'Staff-only session note',
    created_by = '00000000-0000-0000-0000-000000000001'
WHERE id = '38000000-0000-0000-0000-000000000030';

SELECT set_config('app.retrospective_session_create', 'on', TRUE);
INSERT INTO sessions (id, class_id, session_date, sub_tutor_id) VALUES
    ('38000000-0000-0000-0000-000000000033',
     '38000000-0000-0000-0000-000000000010',
     (NOW() AT TIME ZONE 'Asia/Singapore')::DATE - 10, NULL),
    ('38000000-0000-0000-0000-000000000034',
     '38000000-0000-0000-0000-000000000010',
     (NOW() AT TIME ZONE 'Asia/Singapore')::DATE - 11, NULL),
    ('38000000-0000-0000-0000-000000000035',
     '38000000-0000-0000-0000-000000000010',
     (NOW() AT TIME ZONE 'Asia/Singapore')::DATE - 12, NULL),
    ('38000000-0000-0000-0000-000000000036',
     '38000000-0000-0000-0000-000000000010',
     (NOW() AT TIME ZONE 'Asia/Singapore')::DATE - 1,
     '38000000-0000-0000-0000-000000000001');
SELECT set_config('app.retrospective_session_create', 'off', TRUE);

-- Preserve a deliberately stale substitute assignment to prove that the new
-- session-scoped capability expires after the offline replay window.
SELECT set_config('app.retrospective_session_update', 'on', TRUE);
UPDATE sessions
SET sub_tutor_id = '38000000-0000-0000-0000-000000000001'
WHERE id = '38000000-0000-0000-0000-000000000035';
SELECT set_config('app.retrospective_session_update', 'off', TRUE);

SELECT set_config('app.retrospective_attendance_write', 'on', TRUE);
INSERT INTO attendance_records (
    session_id, student_id, status, notes, late_reason, client_mutation_id
) VALUES (
    '38000000-0000-0000-0000-000000000034',
    '38000000-0000-0000-0000-000000000023',
    'late', 'Sensitive attendance note', 'Sensitive late reason',
    'security-038-anonymise'
);
SELECT set_config('app.retrospective_attendance_write', 'off', TRUE);
SELECT set_config('app.retrospective_session_update', 'on', TRUE);
UPDATE sessions SET ended_at = NOW()
WHERE id IN (
    '38000000-0000-0000-0000-000000000033',
    '38000000-0000-0000-0000-000000000034',
    '38000000-0000-0000-0000-000000000036'
);
SELECT set_config('app.retrospective_session_update', 'off', TRUE);

-- Role and feature-control authority is enforced below the application UI.
UPDATE feature_flags SET enabled = FALSE WHERE key = 'parent_portal';
SELECT pg_temp.as_user('00000000-0000-0000-0000-000000000003');
SET LOCAL ROLE authenticated;
SELECT pg_temp.expect_rejected($sql$
    SELECT * FROM get_parent_children()
$sql$);
SELECT pg_temp.expect_rejected($sql$
    UPDATE profiles SET role = 'admin'
    WHERE id = '00000000-0000-0000-0000-000000000003'
$sql$);
RESET ROLE;

SELECT pg_temp.as_user('38000000-0000-0000-0000-000000000002');
SET LOCAL ROLE authenticated;
SELECT pg_temp.assert_true(NOT is_superadmin(), 'ordinary admin is superadmin');
SELECT pg_temp.expect_rejected($sql$
    UPDATE profiles SET role = 'tutor'
    WHERE id = '00000000-0000-0000-0000-000000000003'
$sql$);
-- RLS may reject an UPDATE by making zero rows visible rather than raising an
-- error. Assert the protected value instead of requiring one PostgreSQL error
-- shape.
UPDATE feature_flags SET enabled = NOT enabled WHERE key = 'parent_portal';
RESET ROLE;
SELECT pg_temp.assert_true(
    NOT enabled,
    'ordinary admin changed a security feature flag'
)
FROM feature_flags
WHERE key = 'parent_portal';

SELECT pg_temp.as_user('00000000-0000-0000-0000-000000000001');
SET LOCAL ROLE authenticated;
SELECT pg_temp.assert_true(is_superadmin(), 'seeded principal is not superadmin');
SELECT pg_temp.assert_true(
    NOT has_function_privilege(
        'authenticated', 'wipe_operational_data(text)', 'EXECUTE'
    )
    AND NOT has_function_privilege(
        'authenticated', 'wipe_operational_data_secure(text,uuid)', 'EXECUTE'
    )
    AND has_function_privilege(
        'service_role', 'wipe_operational_data_secure(text,uuid)', 'EXECUTE'
    ),
    'wipe entry points are not restricted to trusted orchestration'
);
SELECT pg_temp.expect_rejected($sql$
    SELECT wipe_operational_data_secure(
        'WRONG CONFIRMATION',
        '00000000-0000-0000-0000-000000000001'
    )
$sql$);
SELECT pg_temp.expect_rejected($sql$
    UPDATE profiles SET role = 'tutor'
    WHERE id = '00000000-0000-0000-0000-000000000001'
$sql$);
UPDATE feature_flags SET enabled = enabled WHERE key = 'parent_portal';
RESET ROLE;

-- Future assignments do not confer early class or student access.
SELECT pg_temp.as_user('38000000-0000-0000-0000-000000000001');
SET LOCAL ROLE authenticated;
SELECT pg_temp.assert_true(
    NOT tutor_owns_class('38000000-0000-0000-0000-000000000012'),
    'future tutor owns class before assigned_from'
);
SELECT pg_temp.assert_true(
    NOT EXISTS (
        SELECT 1 FROM students
        WHERE id = '38000000-0000-0000-0000-000000000022'
    ),
    'future tutor can read enrolled student early'
);
RESET ROLE;

-- An owning tutor cannot delegate a session to a parent account.
SELECT pg_temp.as_user('00000000-0000-0000-0000-000000000002');
SET LOCAL ROLE authenticated;
SELECT pg_temp.expect_rejected($sql$
    UPDATE sessions
    SET sub_tutor_id = '00000000-0000-0000-0000-000000000003'
    WHERE id = '38000000-0000-0000-0000-000000000031'
$sql$);
UPDATE sessions
SET sub_tutor_id = '38000000-0000-0000-0000-000000000001'
WHERE id = '38000000-0000-0000-0000-000000000031';
RESET ROLE;
UPDATE feature_flags SET enabled = TRUE WHERE key = 'session_notes';

-- A valid substitute can see the covered session and mark only a student in
-- that session's class, even though ordinary enrollment RLS is not theirs.
SELECT pg_temp.as_user('38000000-0000-0000-0000-000000000001');
SET LOCAL ROLE authenticated;
SELECT pg_temp.assert_true(
    (get_or_create_today_session(
        '38000000-0000-0000-0000-000000000011'
    )).id = '38000000-0000-0000-0000-000000000031',
    'substitute cannot resolve the pre-assigned current session'
);
SELECT set_session_lifecycle(
    '38000000-0000-0000-0000-000000000031', 'start'
);
SELECT update_session_note(
    '38000000-0000-0000-0000-000000000031',
    'Substitute session note'
);
SELECT pg_temp.expect_rejected($sql$
    SELECT update_session_note(
        '38000000-0000-0000-0000-000000000031',
        'Identifier S1234567D is forbidden'
    )
$sql$);
SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1 FROM sessions
        WHERE id = '38000000-0000-0000-0000-000000000031'
    )
    AND NOT EXISTS (
        SELECT 1 FROM sessions
        WHERE id = '38000000-0000-0000-0000-000000000035'
    )
    AND EXISTS (
        SELECT 1 FROM get_my_classes()
        WHERE id = '38000000-0000-0000-0000-000000000011'
          AND can_operate_today_session
          AND NOT can_manage_sessions
    )
    AND EXISTS (
        SELECT 1 FROM get_my_classes()
        WHERE id = '38000000-0000-0000-0000-000000000010'
          AND NOT can_operate_today_session
          AND NOT can_manage_sessions
    )
    AND NOT EXISTS (
        SELECT 1 FROM get_my_classes()
        WHERE id = '38000000-0000-0000-0000-000000000012'
    )
    AND EXISTS (
        SELECT 1 FROM get_session_roster(
            '38000000-0000-0000-0000-000000000031'
        )
        WHERE student_id = '38000000-0000-0000-0000-000000000021'
    )
    AND NOT EXISTS (
        SELECT 1 FROM get_session_roster(
            '38000000-0000-0000-0000-000000000031'
        )
        WHERE student_id = '38000000-0000-0000-0000-000000000020'
    ),
    'substitute session, class, or roster scope is incorrect'
);
SELECT pg_temp.expect_rejected($sql$
    SELECT get_or_create_today_session(
        '38000000-0000-0000-0000-000000000010'
    )
$sql$);
SELECT pg_temp.expect_rejected($sql$
    SELECT * FROM get_session_roster(
        '38000000-0000-0000-0000-000000000030'
    )
$sql$);
SELECT pg_temp.expect_rejected($sql$
    SELECT * FROM get_session_roster(
        '38000000-0000-0000-0000-000000000035'
    )
$sql$);
INSERT INTO attendance_records (
    session_id, student_id, status, client_mutation_id
) VALUES (
    '38000000-0000-0000-0000-000000000031',
    '38000000-0000-0000-0000-000000000021',
    'present', 'security-038-substitute-valid'
);
SELECT pg_temp.expect_rejected($sql$
    INSERT INTO attendance_records (
        session_id, student_id, status, client_mutation_id
    ) VALUES (
        '38000000-0000-0000-0000-000000000031',
        '38000000-0000-0000-0000-000000000020',
        'present', 'security-038-substitute-cross-class'
    )
$sql$);
SELECT set_session_lifecycle(
    '38000000-0000-0000-0000-000000000031', 'end'
);
SELECT pg_temp.expect_rejected($sql$
    SELECT set_session_lifecycle(
        '38000000-0000-0000-0000-000000000031', 'start'
    )
$sql$);
RESET ROLE;
UPDATE feature_flags SET enabled = FALSE WHERE key = 'session_notes';
SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1 FROM sessions
        WHERE id = '38000000-0000-0000-0000-000000000031'
          AND started_at > clock_timestamp() - INTERVAL '1 minute'
          AND ended_at > clock_timestamp() - INTERVAL '1 minute'
          AND notes = 'Substitute session note'
    ),
    'substitute lifecycle or shaped note write did not persist server values'
);

-- Even a legacy invalid substitute value is inert because substitute policies
-- additionally require the caller's profile to be a tutor.
ALTER TABLE sessions DISABLE TRIGGER validate_session_sub_tutor;
UPDATE sessions
SET sub_tutor_id = '00000000-0000-0000-0000-000000000003'
WHERE id = '38000000-0000-0000-0000-000000000032';
ALTER TABLE sessions ENABLE TRIGGER validate_session_sub_tutor;
SELECT pg_temp.as_user('00000000-0000-0000-0000-000000000003');
SET LOCAL ROLE authenticated;
SELECT pg_temp.assert_true(
    NOT EXISTS (
        SELECT 1 FROM sessions
        WHERE id = '38000000-0000-0000-0000-000000000032'
    ),
    'non-tutor legacy substitute can read session'
);
RESET ROLE;

-- Owning tutors may write same-class attendance, never cross-class rows.
SELECT pg_temp.as_user('00000000-0000-0000-0000-000000000002');
SET LOCAL ROLE authenticated;
SELECT pg_temp.expect_rejected($sql$
    INSERT INTO sessions (class_id, session_date, created_by)
    VALUES (
        '38000000-0000-0000-0000-000000000010',
        (NOW() AT TIME ZONE 'Asia/Singapore')::DATE + 30,
        '38000000-0000-0000-0000-000000000002'
    )
$sql$);
SELECT pg_temp.expect_rejected($sql$
    UPDATE sessions
    SET session_date = (NOW() AT TIME ZONE 'Asia/Singapore')::DATE + 30,
        created_by = '38000000-0000-0000-0000-000000000002'
    WHERE id = '38000000-0000-0000-0000-000000000030'
$sql$);
SELECT pg_temp.expect_rejected($sql$
    UPDATE sessions SET created_at = created_at - INTERVAL '1 day'
    WHERE id = '38000000-0000-0000-0000-000000000030'
$sql$);
SELECT pg_temp.expect_rejected($sql$
    UPDATE sessions SET started_at = NOW()
    WHERE id = '38000000-0000-0000-0000-000000000030'
$sql$);
SELECT pg_temp.expect_rejected($sql$
    DELETE FROM sessions
    WHERE id = '38000000-0000-0000-0000-000000000030'
$sql$);
INSERT INTO attendance_records (
    session_id, student_id, status, notes, late_reason, marked_by, marked_at,
    client_mutation_id
) VALUES (
    '38000000-0000-0000-0000-000000000030',
    '38000000-0000-0000-0000-000000000020',
    'present', 'Staff-only attendance note', 'Staff-only late reason',
    '38000000-0000-0000-0000-000000000002', NOW() + INTERVAL '1 year',
    'security-038-owner-valid'
);
SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1 FROM attendance_records
        WHERE session_id = '38000000-0000-0000-0000-000000000030'
          AND student_id = '38000000-0000-0000-0000-000000000020'
          AND marked_by = '00000000-0000-0000-0000-000000000002'
          AND marked_at BETWEEN clock_timestamp() - INTERVAL '1 minute'
                            AND clock_timestamp() + INTERVAL '1 minute'
          AND late_reason IS NULL
    ),
    'attendance actor/time was caller-forged or non-late reason survived'
);
SELECT sync_attendance(jsonb_build_array(jsonb_build_object(
    'session_id', '38000000-0000-0000-0000-000000000030',
    'student_id', '38000000-0000-0000-0000-000000000020',
    'status', 'present',
    'marked_at', '2099-01-01T00:00:00Z',
    'client_mutation_id', 'security-038-owner-next'
)));
SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1 FROM attendance_records
        WHERE session_id = '38000000-0000-0000-0000-000000000030'
          AND student_id = '38000000-0000-0000-0000-000000000020'
          AND client_mutation_id = 'security-038-owner-next'
          AND marked_by = '00000000-0000-0000-0000-000000000002'
          AND marked_at < '2099-01-01T00:00:00Z'::TIMESTAMPTZ
    ),
    'offline sync trusted its actor or device timestamp'
);
SELECT pg_temp.expect_rejected($sql$
    SELECT * FROM attendance_mutation_receipts
$sql$);
SELECT pg_temp.expect_rejected($sql$
    SELECT attendance_mutation_is_replay(
        'security-038-owner-valid',
        '38000000-0000-0000-0000-000000000030',
        '38000000-0000-0000-0000-000000000020'
    )
$sql$);
SELECT pg_temp.expect_rejected($sql$
    INSERT INTO attendance_records (
        session_id, student_id, status, client_mutation_id
    ) VALUES (
        '38000000-0000-0000-0000-000000000030',
        '38000000-0000-0000-0000-000000000021',
        'present', 'security-038-owner-cross-class'
    )
$sql$);
SELECT pg_temp.expect_rejected($sql$
    INSERT INTO attendance_records (
        session_id, student_id, status, client_mutation_id
    ) VALUES (
        '38000000-0000-0000-0000-000000000032',
        '38000000-0000-0000-0000-000000000021',
        'present', 'security-038-future-attendance'
    )
$sql$);
SELECT pg_temp.expect_rejected($sql$
    INSERT INTO attendance_records (
        session_id, student_id, status, client_mutation_id
    ) VALUES (
        '38000000-0000-0000-0000-000000000035',
        '38000000-0000-0000-0000-000000000020',
        'present', 'security-038-direct-history'
    )
$sql$);
SELECT pg_temp.expect_rejected($sql$
    SELECT sync_attendance(jsonb_build_array(jsonb_build_object(
        'session_id', '38000000-0000-0000-0000-000000000035',
        'student_id', '38000000-0000-0000-0000-000000000020',
        'status', 'present',
        'client_mutation_id', 'security-038-stale-offline-rewrite'
    )))
$sql$);
SELECT pg_temp.expect_rejected($sql$
    DELETE FROM attendance_records
    WHERE session_id = '38000000-0000-0000-0000-000000000030'
      AND student_id = '38000000-0000-0000-0000-000000000020'
$sql$);
RESET ROLE;

-- Admin RLS cannot bypass the universal student/session domain check or reopen
-- an ended session for an ordinary direct write.
SELECT pg_temp.as_user('38000000-0000-0000-0000-000000000002');
SET LOCAL ROLE authenticated;
SELECT pg_temp.expect_rejected($sql$
    INSERT INTO attendance_records (
        session_id, student_id, status, client_mutation_id
    ) VALUES (
        '38000000-0000-0000-0000-000000000030',
        '38000000-0000-0000-0000-000000000021',
        'present', 'security-038-admin-cross-class'
    )
$sql$);
SELECT pg_temp.expect_rejected($sql$
    SELECT sync_attendance(jsonb_build_array(jsonb_build_object(
        'session_id', '38000000-0000-0000-0000-000000000030',
        'student_id', '38000000-0000-0000-0000-000000000020',
        'status', 'absent',
        'client_mutation_id', 'security-038-owner-valid'
    )))
$sql$);
SELECT pg_temp.expect_rejected($sql$
    UPDATE sessions SET ended_at = NULL
    WHERE id = '38000000-0000-0000-0000-000000000033'
$sql$);
RESET ROLE;

-- Retrospective tutor checks are also tied to the target session class.
UPDATE feature_flags SET enabled = TRUE WHERE key = 'retrospective_sessions';
SELECT pg_temp.as_user('00000000-0000-0000-0000-000000000002');
SET LOCAL ROLE authenticated;
SELECT pg_temp.expect_rejected($sql$
    UPDATE sessions
    SET topic = 'Direct historical bypass'
    WHERE id = '38000000-0000-0000-0000-000000000033'
$sql$);
SELECT update_retrospective_session(
    '38000000-0000-0000-0000-000000000033',
    'Dedicated historical update', 'Dedicated historical note', NULL
);
SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1 FROM sessions
        WHERE id = '38000000-0000-0000-0000-000000000033'
          AND topic = 'Dedicated historical update'
          AND notes = 'Dedicated historical note'
    ),
    'dedicated retrospective session update was blocked'
);
SELECT pg_temp.expect_rejected($sql$
    SELECT mark_retrospective_attendance(
        '38000000-0000-0000-0000-000000000033',
        '38000000-0000-0000-0000-000000000021', 'present'
    )
$sql$);
SELECT pg_temp.expect_rejected($sql$
    SELECT mark_retrospective_attendance(
        '38000000-0000-0000-0000-000000000033',
        '38000000-0000-0000-0000-000000000026', 'present'
    )
$sql$);
SELECT mark_retrospective_attendance(
    '38000000-0000-0000-0000-000000000033',
    '38000000-0000-0000-0000-000000000020', 'present'
);
RESET ROLE;

SELECT pg_temp.as_user('00000000-0000-0000-0000-000000000001');
SET LOCAL ROLE authenticated;
SELECT pg_temp.expect_rejected($sql$
    SELECT mark_retrospective_attendance(
        '38000000-0000-0000-0000-000000000033',
        '38000000-0000-0000-0000-000000000026', 'present'
    )
$sql$);
RESET ROLE;

-- Parent portal writes fail closed while disabled.
INSERT INTO result_slips (student_id, exam_name, uploaded_by) VALUES (
    '38000000-0000-0000-0000-000000000020', 'Dark-launch result',
    '00000000-0000-0000-0000-000000000003'
);
INSERT INTO messages (sender_id, student_id, body) VALUES (
    '00000000-0000-0000-0000-000000000003',
    '38000000-0000-0000-0000-000000000020', 'Dark-launch message'
);
INSERT INTO dismissals (
    id, session_id, student_id, dismissed_at
) VALUES (
    '38000000-0000-0000-0000-000000000036',
    '38000000-0000-0000-0000-000000000030',
    '38000000-0000-0000-0000-000000000020', NOW()
);
INSERT INTO consent_records (
    student_id, consent_type, status, method, source_note
) VALUES (
    '38000000-0000-0000-0000-000000000020', 'data_collection',
    'granted', 'admin_attestation', 'Internal provenance'
);
INSERT INTO correction_requests (
    student_id, requested_by, field_name, current_value, requested_value
) VALUES (
    '38000000-0000-0000-0000-000000000020',
    '00000000-0000-0000-0000-000000000003',
    'school', 'Internal current value', 'Requested value'
);
INSERT INTO awards (student_id, award_type, period) VALUES (
    '38000000-0000-0000-0000-000000000020',
    'attendance', '038-parent-boundary'
);
INSERT INTO storage.objects (bucket_id, name) VALUES
    (
        'result-slips',
        '38000000-0000-0000-0000-000000000020/staff-result.pdf'
    ),
    (
        'student-photos',
        '38000000-0000-0000-0000-000000000020/staff-photo.png'
    ),
    (
        'student-photos',
        '38000000-0000-0000-0000-000000000021/substitute-photo.png'
    );
UPDATE feature_flags SET enabled = TRUE
WHERE key IN ('push_notifications', 'student_photos');
UPDATE feature_flags SET enabled = FALSE WHERE key = 'parent_portal';
SELECT pg_temp.as_user('38000000-0000-0000-0000-000000000001');
SET LOCAL ROLE authenticated;
SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1 FROM storage.objects
        WHERE bucket_id = 'student-photos'
          AND name = '38000000-0000-0000-0000-000000000021/substitute-photo.png'
    )
    AND NOT EXISTS (
        SELECT 1 FROM storage.objects
        WHERE bucket_id = 'student-photos'
          AND name = '38000000-0000-0000-0000-000000000020/staff-photo.png'
    ),
    'substitute photo access ignores enrollment on the covered session date'
);
RESET ROLE;
SELECT pg_temp.as_user('00000000-0000-0000-0000-000000000003');
SET LOCAL ROLE authenticated;
SELECT pg_temp.expect_rejected($sql$
    INSERT INTO result_slips (student_id, exam_name, uploaded_by)
    VALUES (
        '38000000-0000-0000-0000-000000000020', 'CA1',
        '00000000-0000-0000-0000-000000000003'
    )
$sql$);
SELECT pg_temp.expect_rejected($sql$
    INSERT INTO messages (sender_id, student_id, body)
    VALUES (
        '00000000-0000-0000-0000-000000000003',
        '38000000-0000-0000-0000-000000000020', 'Hello'
    )
$sql$);
SELECT pg_temp.expect_rejected($sql$
    SELECT * FROM submit_parent_result_slip(
        '38000000-0000-0000-0000-000000000020',
        'CA1', NULL, NULL, 8, 10
    )
$sql$);
SELECT pg_temp.expect_rejected($sql$
    SELECT * FROM send_parent_message(
        '38000000-0000-0000-0000-000000000020', NULL, 'Hello'
    )
$sql$);
SELECT pg_temp.expect_rejected($sql$
    SELECT * FROM get_parent_children()
$sql$);
SELECT pg_temp.expect_rejected($sql$
    SELECT * FROM get_parent_attendance_history(
        '38000000-0000-0000-0000-000000000020', 100, NULL
    )
$sql$);
SELECT pg_temp.expect_rejected($sql$
    SELECT * FROM get_parent_attendance_summary(
        '38000000-0000-0000-0000-000000000020'
    )
$sql$);
SELECT pg_temp.expect_rejected($sql$
    SELECT * FROM get_parent_result_slips(
        '38000000-0000-0000-0000-000000000020'
    )
$sql$);
SELECT pg_temp.expect_rejected($sql$
    SELECT * FROM get_parent_messages(
        '38000000-0000-0000-0000-000000000020'
    )
$sql$);
SELECT pg_temp.expect_rejected($sql$
    SELECT * FROM get_parent_dismissals()
$sql$);
SELECT pg_temp.assert_true(
    NOT EXISTS (SELECT 1 FROM parent_student_links)
    AND NOT EXISTS (SELECT 1 FROM result_slips)
    AND NOT EXISTS (SELECT 1 FROM messages)
    AND NOT EXISTS (SELECT 1 FROM dismissals)
    AND NOT EXISTS (SELECT 1 FROM consent_records)
    AND NOT EXISTS (SELECT 1 FROM correction_requests)
    AND NOT EXISTS (SELECT 1 FROM awards)
    AND NOT EXISTS (
        SELECT 1 FROM storage.objects
        WHERE bucket_id IN ('result-slips', 'student-photos')
    ),
    'parent specialty reads bypass the disabled portal'
);
SELECT pg_temp.expect_rejected($sql$
    SELECT mark_safely_home('38000000-0000-0000-0000-000000000036')
$sql$);
RESET ROLE;

UPDATE feature_flags SET enabled = TRUE WHERE key = 'parent_portal';
SELECT pg_temp.as_user('00000000-0000-0000-0000-000000000003');
SET LOCAL ROLE authenticated;
SELECT pg_temp.assert_true(
    NOT EXISTS (
        SELECT 1 FROM students
        WHERE id = '38000000-0000-0000-0000-000000000020'
    )
    AND NOT EXISTS (
        SELECT 1 FROM classes
        WHERE id = '38000000-0000-0000-0000-000000000010'
    )
    AND NOT EXISTS (
        SELECT 1 FROM enrollments
        WHERE student_id = '38000000-0000-0000-0000-000000000020'
    )
    AND NOT EXISTS (
        SELECT 1 FROM sessions
        WHERE id = '38000000-0000-0000-0000-000000000030'
    )
    AND NOT EXISTS (
        SELECT 1 FROM attendance_records
        WHERE student_id = '38000000-0000-0000-0000-000000000020'
    ),
    'parent can read a staff-only base table directly'
);
SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1
        FROM get_parent_children() child
        WHERE child.id = '38000000-0000-0000-0000-000000000020'
          AND NOT (to_jsonb(child) ? 'notes')
          AND NOT (to_jsonb(child) ? 'date_of_birth')
          AND NOT (to_jsonb(child) ? 'created_by')
          AND NOT (to_jsonb(child) ? 'avatar_url')
    ),
    'safe child projection is missing or exposes staff-only fields'
);
SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1
        FROM get_parent_attendance_history(
            '38000000-0000-0000-0000-000000000020', 100, NULL
        ) history
        WHERE history.status = 'present'
          AND NOT (to_jsonb(history) ? 'notes')
          AND NOT (to_jsonb(history) ? 'late_reason')
          AND NOT (to_jsonb(history) ? 'marked_by')
          AND NOT (to_jsonb(history) ? 'client_mutation_id')
          AND NOT (history.session ? 'notes')
    ),
    'safe attendance history is missing or exposes staff-only fields'
);
SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1
        FROM get_parent_attendance_summary(
            '38000000-0000-0000-0000-000000000020'
        )
        WHERE class_id = '38000000-0000-0000-0000-000000000010'
    ),
    'safe parent attendance summary is missing'
);
SELECT pg_temp.expect_rejected($sql$
    SELECT * FROM get_parent_attendance_history(
        '38000000-0000-0000-0000-000000000021', 100, NULL
    )
$sql$);
SELECT pg_temp.expect_rejected($sql$
    SELECT * FROM get_parent_attendance_summary(
        '38000000-0000-0000-0000-000000000021'
    )
$sql$);
SELECT pg_temp.expect_rejected($sql$
    INSERT INTO result_slips (
        student_id, exam_name, uploaded_by, acknowledged_by, acknowledged_at
    ) VALUES (
        '38000000-0000-0000-0000-000000000020', 'Forged acknowledgement',
        '00000000-0000-0000-0000-000000000003',
        '00000000-0000-0000-0000-000000000003', NOW()
    )
$sql$);
SELECT pg_temp.expect_rejected($sql$
    INSERT INTO result_slips (
        student_id, exam_name, file_path, uploaded_by
    ) VALUES (
        '38000000-0000-0000-0000-000000000020', 'Wrong object',
        '38000000-0000-0000-0000-000000000021/result.pdf',
        '00000000-0000-0000-0000-000000000003'
    )
$sql$);
SELECT pg_temp.expect_rejected($sql$
    INSERT INTO result_slips (
        student_id, exam_name, file_path, uploaded_by
    ) VALUES (
        '38000000-0000-0000-0000-000000000020', 'Direct file row',
        '38000000-0000-0000-0000-000000000020/direct.pdf',
        '00000000-0000-0000-0000-000000000003'
    )
$sql$);
SELECT pg_temp.expect_rejected($sql$
    INSERT INTO result_slips (student_id, exam_name, uploaded_by)
    VALUES (
        '38000000-0000-0000-0000-000000000020', 'Bypass write RPC',
        '00000000-0000-0000-0000-000000000003'
    )
$sql$);
SELECT * FROM submit_parent_result_slip(
    '38000000-0000-0000-0000-000000000020',
    'Text only result', NULL, NULL, 8, 10
);
SELECT pg_temp.expect_rejected($sql$
    SELECT * FROM submit_parent_result_slip(
        '38000000-0000-0000-0000-000000000020',
        'Invalid score', NULL, NULL, 11, 10
    )
$sql$);

SELECT pg_temp.expect_rejected($sql$
    INSERT INTO messages (
        sender_id, recipient_id, student_id, body
    ) VALUES (
        '00000000-0000-0000-0000-000000000003',
        '00000000-0000-0000-0000-000000000002',
        '38000000-0000-0000-0000-000000000020', 'Forged recipient'
    )
$sql$);
SELECT pg_temp.expect_rejected($sql$
    INSERT INTO messages (
        sender_id, student_id, body, read_at
    ) VALUES (
        '00000000-0000-0000-0000-000000000003',
        '38000000-0000-0000-0000-000000000020', 'Forged read state', NOW()
    )
$sql$);
SELECT pg_temp.expect_rejected($sql$
    SELECT * FROM send_parent_message(
        '38000000-0000-0000-0000-000000000020',
        NULL, repeat('x', 10001)
    )
$sql$);
SELECT pg_temp.expect_rejected($sql$
    INSERT INTO messages (sender_id, student_id, body)
    VALUES (
        '00000000-0000-0000-0000-000000000003',
        '38000000-0000-0000-0000-000000000020', 'Bypass write RPC'
    )
$sql$);
SELECT * FROM send_parent_message(
    '38000000-0000-0000-0000-000000000020',
    'Question', 'Valid message'
);
SELECT pg_temp.expect_rejected($sql$
    INSERT INTO correction_requests (
        student_id, requested_by, field_name, requested_value,
        status, reviewed_by, reviewed_at
    ) VALUES (
        '38000000-0000-0000-0000-000000000020',
        '00000000-0000-0000-0000-000000000003',
        'school', 'Forged school', 'applied',
        '00000000-0000-0000-0000-000000000001', NOW()
    )
$sql$);
SELECT pg_temp.expect_rejected($sql$
    INSERT INTO correction_requests (
        student_id, requested_by, field_name, requested_value
    ) VALUES (
        '38000000-0000-0000-0000-000000000020',
        '00000000-0000-0000-0000-000000000003',
        'school', 'Requested school'
    )
$sql$);
SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1 FROM parent_student_links
        WHERE student_id = '38000000-0000-0000-0000-000000000020'
    )
    AND NOT EXISTS (
        SELECT 1 FROM result_slips
        WHERE student_id = '38000000-0000-0000-0000-000000000020'
    )
    AND NOT EXISTS (
        SELECT 1 FROM messages
        WHERE student_id = '38000000-0000-0000-0000-000000000020'
    )
    AND NOT EXISTS (
        SELECT 1 FROM dismissals
        WHERE student_id = '38000000-0000-0000-0000-000000000020'
    )
    AND NOT EXISTS (
        SELECT 1 FROM consent_records
        WHERE student_id = '38000000-0000-0000-0000-000000000020'
    )
    AND NOT EXISTS (
        SELECT 1 FROM correction_requests
        WHERE student_id = '38000000-0000-0000-0000-000000000020'
    )
    AND NOT EXISTS (
        SELECT 1 FROM awards
        WHERE student_id = '38000000-0000-0000-0000-000000000020'
    )
    AND NOT EXISTS (
        SELECT 1 FROM storage.objects
        WHERE bucket_id IN ('result-slips', 'student-photos')
          AND name LIKE '38000000-0000-0000-0000-000000000020/%'
    ),
    'parent can read a specialty base table directly'
);
SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1 FROM get_parent_result_slips(
            '38000000-0000-0000-0000-000000000020'
        ) result
        WHERE result.exam_name = 'Text only result'
          AND NOT (to_jsonb(result) ? 'uploaded_by')
          AND NOT (to_jsonb(result) ? 'acknowledged_by')
    )
    AND EXISTS (
        SELECT 1 FROM get_parent_messages(
            '38000000-0000-0000-0000-000000000020'
        ) message
        WHERE message.body = 'Valid message'
          AND message.is_from_parent = TRUE
          AND NOT (to_jsonb(message) ? 'sender_id')
          AND NOT (to_jsonb(message) ? 'recipient_id')
    )
    AND EXISTS (
        SELECT 1 FROM get_parent_dismissals() dismissal
        WHERE dismissal.id = '38000000-0000-0000-0000-000000000036'
          AND NOT (to_jsonb(dismissal) ? 'dismissed_by')
          AND NOT (to_jsonb(dismissal) ? 'confirmed_by')
    ),
    'safe specialty projection is missing or exposes an actor UUID'
);
SELECT pg_temp.expect_rejected($sql$
    SELECT reserve_result_slip_upload(
        '00000000-0000-0000-0000-000000000003',
        '38000000-0000-0000-0000-000000000020',
        '38000000-0000-0000-0000-000000000020/parent-call.pdf',
        128, 'application/pdf'
    )
$sql$);
SELECT pg_temp.expect_rejected($sql$
    SELECT finalize_result_slip_upload(
        '00000000-0000-0000-0000-000000000003',
        '38000000-0000-0000-0000-000000000020',
        '38000000-0000-0000-0000-000000000020/parent-call.pdf',
        'Parent call', NULL, NULL, NULL
    )
$sql$);
SELECT pg_temp.expect_rejected($sql$
    SELECT * FROM result_slip_upload_intents
$sql$);
SELECT pg_temp.expect_rejected($sql$
    INSERT INTO storage.objects (bucket_id, name)
    VALUES (
        'result-slips',
        '38000000-0000-0000-0000-000000000020/direct-storage.pdf'
    )
$sql$);
RESET ROLE;
SELECT pg_temp.assert_true(
    NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'correction_requests'
          AND policyname = 'correction_requests: parent creates own child'
    ),
    'parent correction-request create policy remains installed'
);

-- A co-parent may see the child's safe result projection, but cannot read the
-- other parent's message thread or any internal compliance ledger.
SELECT pg_temp.as_user('38000000-0000-0000-0000-000000000003');
SET LOCAL ROLE authenticated;
SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1 FROM get_parent_result_slips(
            '38000000-0000-0000-0000-000000000020'
        ) result
        WHERE result.exam_name = 'Text only result'
          AND NOT (to_jsonb(result) ? 'uploaded_by')
    )
    AND NOT EXISTS (
        SELECT 1 FROM get_parent_messages(
            '38000000-0000-0000-0000-000000000020'
        )
    )
    AND NOT EXISTS (
        SELECT 1 FROM correction_requests
        WHERE student_id = '38000000-0000-0000-0000-000000000020'
    )
    AND NOT EXISTS (
        SELECT 1 FROM consent_records
        WHERE student_id = '38000000-0000-0000-0000-000000000020'
    )
    AND NOT EXISTS (
        SELECT 1 FROM awards
        WHERE student_id = '38000000-0000-0000-0000-000000000020'
    ),
    'co-parent isolation or safe result projection regressed'
);
RESET ROLE;

-- The trusted upload workflow binds path, child and actor, then consumes the
-- intent atomically with the file-backed result row.
SELECT pg_temp.as_user('00000000-0000-0000-0000-000000000003');
SET LOCAL ROLE service_role;
SELECT pg_temp.expect_rejected($sql$
    SELECT reserve_result_slip_upload(
        '00000000-0000-0000-0000-000000000003',
        '38000000-0000-0000-0000-000000000020',
        '38000000-0000-0000-0000-000000000021/wrong-child.pdf',
        128, 'application/pdf'
    )
$sql$);
SELECT reserve_result_slip_upload(
    '00000000-0000-0000-0000-000000000003',
    '38000000-0000-0000-0000-000000000020',
    '38000000-0000-0000-0000-000000000020/authorized.pdf',
    128, 'application/pdf'
);
SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1 FROM result_slip_upload_intents
        WHERE path = '38000000-0000-0000-0000-000000000020/authorized.pdf'
          AND student_id = '38000000-0000-0000-0000-000000000020'
          AND actor_id = '00000000-0000-0000-0000-000000000003'
          AND expected_size = 128
          AND expected_mime = 'application/pdf'
          AND expires_at > NOW()
          AND cleanup_claimed_at IS NULL
    ),
    'trusted reservation did not persist its actor/path/file binding'
);
SELECT pg_temp.expect_rejected($sql$
    SELECT finalize_result_slip_upload(
        '38000000-0000-0000-0000-000000000003',
        '38000000-0000-0000-0000-000000000020',
        '38000000-0000-0000-0000-000000000020/authorized.pdf',
        'Stolen authorization', 'Math', 8, 10
    )
$sql$);
RESET ROLE;
SELECT pg_temp.as_user('00000000-0000-0000-0000-000000000003');
SET LOCAL ROLE authenticated;
SELECT pg_temp.expect_rejected($sql$
    INSERT INTO result_slips (
        student_id, exam_name, file_path, uploaded_by
    ) VALUES (
        '38000000-0000-0000-0000-000000000020', 'Bypass finalizer',
        '38000000-0000-0000-0000-000000000020/authorized.pdf',
        '00000000-0000-0000-0000-000000000003'
    )
$sql$);
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT finalize_result_slip_upload(
    '00000000-0000-0000-0000-000000000003',
    '38000000-0000-0000-0000-000000000020',
    '38000000-0000-0000-0000-000000000020/authorized.pdf',
    'Authorized result', 'Math', 8, 10
);
SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1 FROM result_slips
        WHERE student_id = '38000000-0000-0000-0000-000000000020'
          AND uploaded_by = '00000000-0000-0000-0000-000000000003'
          AND file_path = '38000000-0000-0000-0000-000000000020/authorized.pdf'
          AND exam_name = 'Authorized result'
    )
    AND EXISTS (
        SELECT 1
        FROM result_slip_upload_intents intent
        JOIN result_slips result ON result.id = intent.finalized_result_id
        WHERE intent.path =
            '38000000-0000-0000-0000-000000000020/authorized.pdf'
          AND intent.finalized_at IS NOT NULL
    ),
    'finalization did not atomically create the result and retain its token tombstone'
);
-- An exact retry represents an ambiguous/lost HTTP response. It must be a
-- successful no-op, while a caller cannot reuse the path for different data.
SELECT finalize_result_slip_upload(
    '00000000-0000-0000-0000-000000000003',
    '38000000-0000-0000-0000-000000000020',
    '38000000-0000-0000-0000-000000000020/authorized.pdf',
    'Authorized result', 'Math', 8, 10
);
SELECT pg_temp.assert_true(
    (
        SELECT COUNT(*) = 1
        FROM result_slips
        WHERE file_path =
            '38000000-0000-0000-0000-000000000020/authorized.pdf'
    ),
    'exact finalization retry duplicated its committed result'
);
SELECT pg_temp.expect_rejected($sql$
    SELECT finalize_result_slip_upload(
        '00000000-0000-0000-0000-000000000003',
        '38000000-0000-0000-0000-000000000020',
        '38000000-0000-0000-0000-000000000020/authorized.pdf',
        'Replayed result', 'Math', 8, 10
    )
$sql$);
SELECT reserve_result_slip_upload(
    '00000000-0000-0000-0000-000000000003',
    '38000000-0000-0000-0000-000000000020',
    '38000000-0000-0000-0000-000000000020/expired.pdf',
    256, 'application/pdf'
);
UPDATE result_slip_upload_intents
SET expires_at = NOW() - INTERVAL '1 minute'
WHERE path = '38000000-0000-0000-0000-000000000020/expired.pdf';
SELECT pg_temp.expect_rejected($sql$
    SELECT finalize_result_slip_upload(
        '00000000-0000-0000-0000-000000000003',
        '38000000-0000-0000-0000-000000000020',
        '38000000-0000-0000-0000-000000000020/expired.pdf',
        'Expired result', NULL, NULL, NULL
    )
$sql$);
SELECT pg_temp.assert_true(
    NOT EXISTS (
        SELECT 1 FROM result_slips
        WHERE file_path = '38000000-0000-0000-0000-000000000020/expired.pdf'
    ),
    'expired upload authorization created a result row'
);
SELECT reserve_result_slip_upload(
    '00000000-0000-0000-0000-000000000003',
    '38000000-0000-0000-0000-000000000020',
    '38000000-0000-0000-0000-000000000020/cleanup-claimed.pdf',
    512, 'application/pdf'
);
UPDATE result_slip_upload_intents
SET cleanup_claimed_at = NOW()
WHERE path = '38000000-0000-0000-0000-000000000020/cleanup-claimed.pdf';
SELECT pg_temp.expect_rejected($sql$
    SELECT finalize_result_slip_upload(
        '00000000-0000-0000-0000-000000000003',
        '38000000-0000-0000-0000-000000000020',
        '38000000-0000-0000-0000-000000000020/cleanup-claimed.pdf',
        'Cleanup race', NULL, NULL, NULL
    )
$sql$);
SELECT pg_temp.assert_true(
    NOT EXISTS (
        SELECT 1 FROM result_slips
        WHERE file_path =
            '38000000-0000-0000-0000-000000000020/cleanup-claimed.pdf'
    ),
    'cleanup-claimed upload authorization created a result row'
);
RESET ROLE;
SELECT pg_temp.assert_true(
    NOT has_function_privilege(
        'authenticated',
        'reserve_result_slip_upload(uuid,uuid,text,bigint,text)',
        'EXECUTE'
    )
    AND NOT has_function_privilege(
        'authenticated',
        'finalize_result_slip_upload(uuid,uuid,text,text,text,numeric,numeric)',
        'EXECUTE'
    )
    AND has_function_privilege(
        'service_role',
        'reserve_result_slip_upload(uuid,uuid,text,bigint,text)',
        'EXECUTE'
    )
    AND has_function_privilege(
        'service_role',
        'finalize_result_slip_upload(uuid,uuid,text,text,text,numeric,numeric)',
        'EXECUTE'
    )
    AND NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'storage'
          AND tablename = 'objects'
          AND policyname IN (
              'result-slips: parent upload own child',
              'result-slips: parent read',
              'student-photos: parent read'
          )
    ),
    'upload RPC privileges or parent Storage closure regressed'
);
SELECT pg_temp.as_user('00000000-0000-0000-0000-000000000001');
SET LOCAL ROLE authenticated;
SELECT pg_temp.expect_rejected($sql$
    DELETE FROM result_slips
    WHERE file_path =
        '38000000-0000-0000-0000-000000000020/authorized.pdf'
$sql$);
RESET ROLE;

-- Identity deletion must preserve the exact path until the signed upload token
-- is certainly expired and the cleanup worker has removed any late object.
INSERT INTO auth.users (
    id, email, encrypted_password, email_confirmed_at, role, aud,
    raw_user_meta_data, created_at, updated_at
) VALUES (
    '38000000-0000-0000-0000-000000000004',
    'security-038-expiring-upload@tava.dev',
    crypt('test', gen_salt('bf')), NOW(), 'authenticated', 'authenticated',
    '{"full_name":"Expiring Upload Parent"}', NOW(), NOW()
);
INSERT INTO students (id, full_name) VALUES (
    '38000000-0000-0000-0000-000000000027', 'Upload Tombstone Child'
);
INSERT INTO result_slip_upload_intents (
    path, student_id, actor_id, expected_size, expected_mime
) VALUES (
    '38000000-0000-0000-0000-000000000027/tombstone.pdf',
    '38000000-0000-0000-0000-000000000027',
    '38000000-0000-0000-0000-000000000004',
    64, 'application/pdf'
);
INSERT INTO result_slips (
    id, student_id, exam_name, file_path, uploaded_by
) VALUES (
    '38000000-0000-0000-0000-000000000080',
    '38000000-0000-0000-0000-000000000027',
    'Finalized before erasure',
    '38000000-0000-0000-0000-000000000027/tombstone.pdf',
    '38000000-0000-0000-0000-000000000004'
);
UPDATE result_slip_upload_intents
SET finalized_result_id = '38000000-0000-0000-0000-000000000080',
    finalized_at = NOW()
WHERE path = '38000000-0000-0000-0000-000000000027/tombstone.pdf';
DELETE FROM students
WHERE id = '38000000-0000-0000-0000-000000000027';
DELETE FROM auth.users
WHERE id = '38000000-0000-0000-0000-000000000004';
SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1 FROM result_slip_upload_intents
        WHERE path =
            '38000000-0000-0000-0000-000000000027/tombstone.pdf'
          AND student_id IS NULL
          AND actor_id IS NULL
          AND finalized_result_id IS NULL
          AND finalized_at IS NOT NULL
    ),
    'identity deletion discarded a live signed-upload cleanup tombstone'
);
SELECT pg_temp.as_user('00000000-0000-0000-0000-000000000003');
SET LOCAL ROLE authenticated;
SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1 FROM get_parent_result_slips(
            '38000000-0000-0000-0000-000000000020'
        ) result
        WHERE result.exam_name = 'Authorized result'
          AND result.file_path =
              '38000000-0000-0000-0000-000000000020/authorized.pdf'
          AND NOT (to_jsonb(result) ? 'uploaded_by')
    )
    AND NOT EXISTS (
        SELECT 1 FROM result_slips
        WHERE file_path =
            '38000000-0000-0000-0000-000000000020/authorized.pdf'
    ),
    'file-backed result bypasses or is missing from the safe projection'
);
RESET ROLE;

-- Correction review is admin-only and atomic: a locked pending request is
-- applied/rejected once, reviewer metadata is server-derived, and the
-- disclosure event never repeats either the old or requested personal data.
UPDATE students SET school = 'Old Academy'
WHERE id = '38000000-0000-0000-0000-000000000020';
INSERT INTO correction_requests (
    id, student_id, requested_by, field_name, current_value, requested_value
) VALUES
    (
        '38000000-0000-0000-0000-000000000070',
        '38000000-0000-0000-0000-000000000020',
        '00000000-0000-0000-0000-000000000003',
        'school', 'Old Academy', 'Atomic Academy'
    ),
    (
        '38000000-0000-0000-0000-000000000071',
        '38000000-0000-0000-0000-000000000020',
        '00000000-0000-0000-0000-000000000003',
        'full_name', 'Same Class', 'Unverified Name'
    ),
    (
        '38000000-0000-0000-0000-000000000072',
        '38000000-0000-0000-0000-000000000020',
        '00000000-0000-0000-0000-000000000003',
        'notes', 'Staff-only child note', 'S1234567D'
    ),
    (
        '38000000-0000-0000-0000-000000000073',
        '38000000-0000-0000-0000-000000000020',
        '00000000-0000-0000-0000-000000000003',
        'created_by', NULL, '38000000-0000-0000-0000-000000000001'
    ),
    (
        '38000000-0000-0000-0000-000000000074',
        '38000000-0000-0000-0000-000000000020',
        '00000000-0000-0000-0000-000000000003',
        'school', 'Old Academy', 'Stale Academy'
    );

SELECT pg_temp.as_user('38000000-0000-0000-0000-000000000001');
SET LOCAL ROLE authenticated;
SELECT pg_temp.expect_rejected($sql$
    SELECT review_correction_request(
        '38000000-0000-0000-0000-000000000070', 'applied', NULL
    )
$sql$);
RESET ROLE;

SELECT pg_temp.as_user('38000000-0000-0000-0000-000000000002');
SET LOCAL ROLE authenticated;
SELECT pg_temp.expect_rejected($sql$
    UPDATE correction_requests
    SET status = 'applied',
        reviewed_by = '38000000-0000-0000-0000-000000000002',
        reviewed_at = NOW()
    WHERE id = '38000000-0000-0000-0000-000000000070'
$sql$);
SELECT review_correction_request(
    '38000000-0000-0000-0000-000000000070', 'applied', NULL
);
SELECT pg_temp.expect_rejected($sql$
    SELECT review_correction_request(
        '38000000-0000-0000-0000-000000000070', 'applied', NULL
    )
$sql$);
SELECT review_correction_request(
    '38000000-0000-0000-0000-000000000071',
    'rejected', '  Not verified  '
);
SELECT pg_temp.expect_rejected($sql$
    SELECT review_correction_request(
        '38000000-0000-0000-0000-000000000072', 'applied', NULL
    )
$sql$);
SELECT pg_temp.expect_rejected($sql$
    SELECT review_correction_request(
        '38000000-0000-0000-0000-000000000073', 'applied', NULL
    )
$sql$);
SELECT pg_temp.expect_rejected($sql$
    SELECT review_correction_request(
        '38000000-0000-0000-0000-000000000074', 'applied', NULL
    )
$sql$);
RESET ROLE;

SELECT pg_temp.assert_true(
    (SELECT school = 'Atomic Academy' AND full_name = 'Same Class'
     FROM students
     WHERE id = '38000000-0000-0000-0000-000000000020')
    AND EXISTS (
        SELECT 1 FROM correction_requests
        WHERE id = '38000000-0000-0000-0000-000000000070'
          AND status = 'applied'
          AND reviewed_by = '38000000-0000-0000-0000-000000000002'
          AND reviewed_at IS NOT NULL
    )
    AND EXISTS (
        SELECT 1 FROM correction_requests
        WHERE id = '38000000-0000-0000-0000-000000000071'
          AND status = 'rejected'
          AND reviewed_by = '38000000-0000-0000-0000-000000000002'
          AND review_note = 'Not verified'
    )
    AND (
        SELECT COUNT(*) = 2
        FROM data_disclosures
        WHERE disclosure_type = 'correction_response'
          AND detail->>'request_id' IN (
              '38000000-0000-0000-0000-000000000070',
              '38000000-0000-0000-0000-000000000071'
          )
          AND disclosed_by = '38000000-0000-0000-0000-000000000002'
          AND jsonb_object_length(detail) = 2
          AND NOT (detail ? 'current_value')
          AND NOT (detail ? 'requested_value')
          AND NOT (detail ? 'applied_value')
          AND NOT (detail ? 'field')
          AND detail::TEXT NOT LIKE '%Atomic Academy%'
          AND detail::TEXT NOT LIKE '%Unverified Name%'
    )
    AND (
        SELECT COUNT(*) = 3
        FROM correction_requests
        WHERE id IN (
            '38000000-0000-0000-0000-000000000072',
            '38000000-0000-0000-0000-000000000073',
            '38000000-0000-0000-0000-000000000074'
        )
          AND status = 'pending'
          AND reviewed_by IS NULL
          AND reviewed_at IS NULL
    )
    AND NOT EXISTS (
        SELECT 1 FROM data_disclosures
        WHERE detail->>'request_id' IN (
            '38000000-0000-0000-0000-000000000072',
            '38000000-0000-0000-0000-000000000073',
            '38000000-0000-0000-0000-000000000074'
        )
    ),
    'correction review was non-atomic, forgeable, or copied corrected PII'
);
SELECT pg_temp.assert_true(
    has_function_privilege(
        'authenticated', 'review_correction_request(uuid,text,text)', 'EXECUTE'
    )
    AND NOT has_function_privilege(
        'anon', 'review_correction_request(uuid,text,text)', 'EXECUTE'
    )
    AND NOT has_function_privilege(
        'service_role', 'review_correction_request(uuid,text,text)', 'EXECUTE'
    )
    AND has_table_privilege(
        'authenticated', 'correction_requests', 'SELECT'
    )
    AND NOT has_table_privilege(
        'authenticated', 'correction_requests', 'INSERT'
    )
    AND NOT has_table_privilege(
        'authenticated', 'correction_requests', 'UPDATE'
    )
    AND NOT has_table_privilege(
        'authenticated', 'correction_requests', 'DELETE'
    )
    AND NOT has_table_privilege(
        'authenticated', 'correction_requests', 'TRUNCATE'
    )
    AND NOT has_table_privilege(
        'authenticated', 'correction_requests', 'REFERENCES'
    )
    AND NOT has_table_privilege(
        'authenticated', 'correction_requests', 'TRIGGER'
    ),
    'correction-review RPC grants regressed'
);

-- Consent/disclosure evidence is readable to admins but writable only through
-- shaped functions that derive provenance. Raw Data API writes are rejected.
SELECT pg_temp.as_user('38000000-0000-0000-0000-000000000001');
SET LOCAL ROLE authenticated;
SELECT pg_temp.expect_rejected($sql$
    SELECT record_admin_consent(
        '38000000-0000-0000-0000-000000000020',
        'photos', 'granted', 'Tutor forgery'
    )
$sql$);
RESET ROLE;

SELECT pg_temp.as_user('00000000-0000-0000-0000-000000000001');
SET LOCAL ROLE authenticated;
SELECT pg_temp.expect_rejected($sql$
    INSERT INTO consent_records (
        student_id, consent_type, status, method, notice_version,
        granted_by, created_at
    ) VALUES (
        '38000000-0000-0000-0000-000000000020', 'photos', 'granted',
        'admin_attestation', 'forged-version',
        '38000000-0000-0000-0000-000000000001', '2000-01-01'
    )
$sql$);
SELECT pg_temp.expect_rejected($sql$
    INSERT INTO data_disclosures (
        student_id, disclosed_to, disclosure_type, disclosed_by, detail
    ) VALUES (
        '38000000-0000-0000-0000-000000000020', 'Forged recipient',
        'other', '38000000-0000-0000-0000-000000000001',
        '{"forged":true}'::JSONB
    )
$sql$);
SELECT record_admin_consent(
    '38000000-0000-0000-0000-000000000020',
    'photos', 'granted', '  Verified paper form  '
);
SELECT pg_temp.expect_rejected($sql$
    SELECT record_admin_consent(
        '38000000-0000-0000-0000-000000000020',
        'photos', 'invalid', NULL
    )
$sql$);
SELECT pg_temp.expect_rejected($sql$
    UPDATE data_disclosures SET detail = '{"tampered":true}'::JSONB
    WHERE disclosure_type = 'correction_response'
$sql$);
SELECT pg_temp.expect_rejected($sql$
    DELETE FROM data_disclosures WHERE disclosure_type = 'correction_response'
$sql$);
RESET ROLE;
SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1 FROM consent_records cr
        JOIN policy_documents pd
          ON pd.doc_type = 'data_protection_notice'
         AND pd.is_current
         AND pd.version = cr.notice_version
        WHERE cr.student_id = '38000000-0000-0000-0000-000000000020'
          AND cr.consent_type = 'photos'
          AND cr.status = 'granted'
          AND cr.method = 'admin_attestation'
          AND cr.granted_by = '00000000-0000-0000-0000-000000000001'
          AND cr.parent_id IS NULL
          AND cr.source_note = 'Verified paper form'
          AND cr.created_at > NOW() - INTERVAL '1 minute'
    )
    AND has_function_privilege(
        'authenticated', 'record_admin_consent(uuid,text,text,text)', 'EXECUTE'
    )
    AND NOT has_function_privilege(
        'service_role', 'record_admin_consent(uuid,text,text,text)', 'EXECUTE'
    )
    AND has_table_privilege('authenticated', 'consent_records', 'SELECT')
    AND NOT has_table_privilege('authenticated', 'consent_records', 'INSERT')
    AND has_table_privilege('authenticated', 'data_disclosures', 'SELECT')
    AND NOT has_table_privilege('authenticated', 'data_disclosures', 'INSERT'),
    'consent/disclosure provenance boundary regressed'
);

-- Invite quota consumption is one service-only, advisory-locked transaction.
DELETE FROM rate_limit_events
WHERE actor_id = '38000000-0000-0000-0000-000000000002'
  AND action = 'invite';
INSERT INTO rate_limit_events (actor_id, action)
SELECT '38000000-0000-0000-0000-000000000002', 'invite'
FROM generate_series(1, 19);
SET LOCAL ROLE service_role;
SELECT consume_invite_rate_limit('38000000-0000-0000-0000-000000000002');
SELECT pg_temp.expect_rejected($sql$
    SELECT consume_invite_rate_limit('38000000-0000-0000-0000-000000000002')
$sql$);
SELECT pg_temp.expect_rejected($sql$
    SELECT consume_invite_rate_limit('38000000-0000-0000-0000-000000000001')
$sql$);
RESET ROLE;
SELECT pg_temp.assert_true(
    (SELECT COUNT(*) = 20 FROM rate_limit_events
     WHERE actor_id = '38000000-0000-0000-0000-000000000002'
       AND action = 'invite')
    AND has_function_privilege(
        'service_role', 'consume_invite_rate_limit(uuid)', 'EXECUTE'
    )
    AND NOT has_function_privilege(
        'authenticated', 'consume_invite_rate_limit(uuid)', 'EXECUTE'
    ),
    'invite quota is not service-only, actor-bound, or atomic'
);

-- Client analytics cannot forge provenance or write unbounded/raw rows. The
-- server flag fails closed, and the shaped RPC derives actor, role, and time.
DELETE FROM app_events WHERE name LIKE 'security_038_analytics%';
DELETE FROM rate_limit_events
WHERE actor_id = '38000000-0000-0000-0000-000000000003'
  AND action = 'analytics_event';
UPDATE feature_flags SET enabled = FALSE WHERE key = 'analytics';
SELECT pg_temp.as_user('38000000-0000-0000-0000-000000000003');
SET LOCAL ROLE authenticated;
SELECT pg_temp.assert_true(
    submit_app_events(jsonb_build_array(jsonb_build_object(
        'platform', 'web',
        'session_id', 'security-038-disabled',
        'event_type', 'ops',
        'name', 'security_038_analytics_disabled',
        'properties', '{}'::JSONB
    ))) = 0,
    'analytics ingestion did not fail closed with the flag disabled'
);
RESET ROLE;
SELECT pg_temp.assert_true(
    NOT EXISTS (
        SELECT 1 FROM app_events
        WHERE name = 'security_038_analytics_disabled'
    ),
    'disabled analytics wrote an event'
);

UPDATE feature_flags SET enabled = TRUE WHERE key = 'analytics';
SELECT pg_temp.as_user('38000000-0000-0000-0000-000000000003');
SET LOCAL ROLE authenticated;
SELECT pg_temp.expect_rejected($sql$
    INSERT INTO app_events (
        occurred_at, user_id, role, platform, session_id, event_type, name
    ) VALUES (
        '2000-01-01', '00000000-0000-0000-0000-000000000001', 'admin',
        'web', 'forged', 'ops', 'security_038_analytics_direct'
    )
$sql$);
SELECT pg_temp.assert_true(
    submit_app_events(jsonb_build_array(jsonb_build_object(
        'occurred_at', '2000-01-01T00:00:00Z',
        'user_id', '00000000-0000-0000-0000-000000000001',
        'role', 'admin',
        'platform', 'WEB',
        'app_version', 'security-test',
        'session_id', 'security-038-session',
        'event_type', 'OPS',
        'name', 'security_038_analytics_provenance',
        'properties', jsonb_build_object('source', 'security-test'),
        'device', 'test-runner'
    ))) = 1,
    'valid shaped analytics event was not accepted'
);
SELECT pg_temp.expect_rejected($sql$
    SELECT submit_app_events(jsonb_build_array(jsonb_build_object(
        'platform', 'web',
        'session_id', 'security-038-pii',
        'event_type', 'error',
        'name', 'security_038_analytics_pii',
        'properties', jsonb_build_object('contact', 'child@example.com')
    )))
$sql$);
SELECT pg_temp.expect_rejected($sql$
    SELECT submit_app_events((
        SELECT jsonb_agg(jsonb_build_object(
            'platform', 'web',
            'session_id', 'security-038-batch',
            'event_type', 'ops',
            'name', 'security_038_analytics_batch_' || i,
            'properties', '{}'::JSONB
        ))
        FROM generate_series(1, 101) AS generated(i)
    ))
$sql$);
RESET ROLE;
SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1 FROM app_events
        WHERE name = 'security_038_analytics_provenance'
          AND occurred_at > clock_timestamp() - INTERVAL '1 minute'
          AND user_id = '38000000-0000-0000-0000-000000000003'
          AND role = 'parent'
          AND platform = 'web'
          AND event_type = 'ops'
          AND properties = '{"source":"security-test"}'::JSONB
    )
    AND (
        SELECT COUNT(*) = 1 FROM rate_limit_events
        WHERE actor_id = '38000000-0000-0000-0000-000000000003'
          AND action = 'analytics_event'
    )
    AND NOT has_table_privilege('authenticated', 'app_events', 'INSERT')
    AND has_function_privilege(
        'authenticated', 'submit_app_events(jsonb)', 'EXECUTE'
    )
    AND NOT has_function_privilege(
        'service_role', 'submit_app_events(jsonb)', 'EXECUTE'
    ),
    'analytics provenance, quota accounting, or privileges regressed'
);

-- Parent push registration is shaped, feature-gated, and bounded to five
-- current tokens. Base-table reads/writes and non-parent registration fail.
DELETE FROM device_tokens
WHERE user_id = '38000000-0000-0000-0000-000000000003';
SELECT pg_temp.as_user('38000000-0000-0000-0000-000000000003');
SET LOCAL ROLE authenticated;
SELECT pg_temp.expect_rejected($sql$
    SELECT * FROM device_tokens
$sql$);
SELECT pg_temp.expect_rejected($sql$
    INSERT INTO device_tokens (user_id, token, platform)
    VALUES (
        '38000000-0000-0000-0000-000000000003',
        'security-038-direct-device-token-0001', 'android'
    )
$sql$);
SELECT register_device_token(
    'security-038-parent-device-token-' || LPAD(i::TEXT, 2, '0'),
    'android'
)
FROM generate_series(1, 6) AS generated(i);
SELECT pg_temp.expect_rejected($sql$
    SELECT register_device_token(
        'security-038-parent device-token-invalid', 'android'
    )
$sql$);
SELECT pg_temp.expect_rejected($sql$
    SELECT register_device_token(
        'security-038-parent-device-token-web-01', 'web'
    )
$sql$);
RESET ROLE;
SELECT pg_temp.assert_true(
    (
        SELECT COUNT(*) = 5 FROM device_tokens
        WHERE user_id = '38000000-0000-0000-0000-000000000003'
          AND platform = 'android'
    )
    AND NOT has_table_privilege('authenticated', 'device_tokens', 'SELECT')
    AND NOT has_table_privilege('authenticated', 'device_tokens', 'INSERT')
    AND has_function_privilege(
        'authenticated', 'register_device_token(text,text)', 'EXECUTE'
    )
    AND NOT has_function_privilege(
        'service_role', 'register_device_token(text,text)', 'EXECUTE'
    ),
    'device-token count, platform, or privileges regressed'
);
SELECT pg_temp.as_user('38000000-0000-0000-0000-000000000001');
SET LOCAL ROLE authenticated;
SELECT pg_temp.expect_rejected($sql$
    SELECT register_device_token(
        'security-038-tutor-device-token-000001', 'android'
    )
$sql$);
RESET ROLE;
UPDATE feature_flags SET enabled = FALSE WHERE key = 'push_notifications';
SELECT pg_temp.as_user('38000000-0000-0000-0000-000000000003');
SET LOCAL ROLE authenticated;
SELECT pg_temp.expect_rejected($sql$
    SELECT register_device_token(
        'security-038-disabled-device-token-001', 'android'
    )
$sql$);
RESET ROLE;
UPDATE feature_flags SET enabled = TRUE WHERE key = 'push_notifications';

SELECT pg_temp.assert_true(
    POSITION(
        'old.status is not distinct from new.status'
        IN LOWER(pg_get_functiondef(
            'notify_parent_on_attendance()'::REGPROCEDURE
        ))
    ) > 0
    AND POSITION(
        'new.status not in (''late'', ''absent'')'
        IN LOWER(pg_get_functiondef(
            'notify_parent_on_attendance()'::REGPROCEDURE
        ))
    ) > 0,
    'attendance notification duplicate/non-alerting status gates regressed'
);

-- Removing the current link revokes every child-scoped read and write RPC.
DELETE FROM parent_student_links
WHERE parent_id = '00000000-0000-0000-0000-000000000003'
  AND student_id = '38000000-0000-0000-0000-000000000020';
SELECT pg_temp.as_user('00000000-0000-0000-0000-000000000003');
SET LOCAL ROLE authenticated;
SELECT pg_temp.assert_true(
    NOT EXISTS (
        SELECT 1 FROM messages
        WHERE student_id = '38000000-0000-0000-0000-000000000020'
    )
    AND NOT EXISTS (
        SELECT 1 FROM result_slips
        WHERE student_id = '38000000-0000-0000-0000-000000000020'
    )
    AND NOT EXISTS (
        SELECT 1 FROM dismissals
        WHERE student_id = '38000000-0000-0000-0000-000000000020'
    )
    AND NOT EXISTS (
        SELECT 1 FROM parent_student_links
        WHERE student_id = '38000000-0000-0000-0000-000000000020'
    )
    AND NOT EXISTS (
        SELECT 1 FROM get_parent_children()
        WHERE id = '38000000-0000-0000-0000-000000000020'
    ),
    'unlinked parent retains child-scoped historical access'
);
SELECT pg_temp.expect_rejected($sql$
    SELECT * FROM get_parent_attendance_history(
        '38000000-0000-0000-0000-000000000020', 100, NULL
    )
$sql$);
SELECT pg_temp.expect_rejected($sql$
    SELECT * FROM get_parent_attendance_summary(
        '38000000-0000-0000-0000-000000000020'
    )
$sql$);
SELECT pg_temp.expect_rejected($sql$
    SELECT * FROM get_parent_result_slips(
        '38000000-0000-0000-0000-000000000020'
    )
$sql$);
SELECT pg_temp.expect_rejected($sql$
    SELECT * FROM get_parent_messages(
        '38000000-0000-0000-0000-000000000020'
    )
$sql$);
SELECT pg_temp.assert_true(
    NOT EXISTS (SELECT 1 FROM get_parent_dismissals()),
    'unlinked parent still resolves a dismissal'
);
SELECT pg_temp.expect_rejected($sql$
    SELECT * FROM submit_parent_result_slip(
        '38000000-0000-0000-0000-000000000020',
        'Unlinked write', NULL, NULL, 8, 10
    )
$sql$);
SELECT pg_temp.expect_rejected($sql$
    SELECT * FROM send_parent_message(
        '38000000-0000-0000-0000-000000000020',
        NULL, 'Unlinked write'
    )
$sql$);
RESET ROLE;
INSERT INTO parent_student_links (parent_id, student_id) VALUES (
    '00000000-0000-0000-0000-000000000003',
    '38000000-0000-0000-0000-000000000020'
);

SELECT pg_temp.assert_true(
    canonical_storage_student_id(
        '38000000-0000-0000-0000-000000000020/result.pdf'
    ) = '38000000-0000-0000-0000-000000000020'::UUID,
    'canonical result path rejected'
);
SELECT pg_temp.assert_true(
    canonical_storage_student_id(
        '38000000-0000-0000-0000-000000000020/nested/result.pdf'
    ) IS NULL,
    'nested result path accepted'
);
SELECT pg_temp.assert_true(
    canonical_storage_student_id('../result.pdf') IS NULL,
    'traversal result path accepted'
);
SELECT pg_temp.expect_rejected($sql$
    INSERT INTO students (id, full_name, avatar_url)
    VALUES (
        '38000000-0000-0000-0000-000000000025',
        'Malformed avatar', '../photo.jpg'
    )
$sql$);
SELECT pg_temp.expect_rejected($sql$
    INSERT INTO result_slips (student_id, exam_name, file_path)
    VALUES (
        '38000000-0000-0000-0000-000000000020',
        'Malformed path', '../result.pdf'
    )
$sql$);
SELECT pg_temp.assert_true(
    (
        SELECT file_size_limit = 10485760
           AND allowed_mime_types @> ARRAY[
               'application/pdf', 'image/jpeg', 'image/png'
           ]::TEXT[]
        FROM storage.buckets WHERE id = 'result-slips'
    ),
    'result-slips bucket limits missing'
);

SELECT pg_temp.assert_true(
    (
        SELECT file_size_limit = 5242880
           AND public = FALSE
           AND allowed_mime_types @> ARRAY['image/jpeg', 'image/png']::TEXT[]
        FROM storage.buckets WHERE id = 'student-photos'
    ),
    'student-photos bucket limits missing'
);

-- The photo flag protects both object writes (policy verification in the
-- migration) and assignment of an avatar path on the student row.
UPDATE feature_flags SET enabled = FALSE WHERE key = 'student_photos';
SELECT pg_temp.as_user('00000000-0000-0000-0000-000000000001');
SET LOCAL ROLE authenticated;
SELECT pg_temp.expect_rejected($sql$
    UPDATE students
    SET avatar_url = '38000000-0000-0000-0000-000000000020/photo.jpg'
    WHERE id = '38000000-0000-0000-0000-000000000020'
$sql$);
RESET ROLE;
UPDATE feature_flags SET enabled = TRUE WHERE key = 'student_photos';
SELECT pg_temp.as_user('00000000-0000-0000-0000-000000000001');
SET LOCAL ROLE authenticated;
UPDATE students
SET avatar_url = '38000000-0000-0000-0000-000000000020/photo.jpg'
WHERE id = '38000000-0000-0000-0000-000000000020';
SELECT pg_temp.expect_rejected($sql$
    UPDATE students
    SET avatar_url = '38000000-0000-0000-0000-000000000021/photo.jpg'
    WHERE id = '38000000-0000-0000-0000-000000000020'
$sql$);
RESET ROLE;

-- Session notes are gated at the table, not only in client code.  Unrelated
-- session updates remain possible while the flag is off.
UPDATE feature_flags SET enabled = FALSE WHERE key = 'session_notes';
SELECT pg_temp.as_user('00000000-0000-0000-0000-000000000002');
SET LOCAL ROLE authenticated;
SELECT pg_temp.expect_rejected($sql$
    UPDATE sessions SET notes = 'Hidden feature write'
    WHERE id = '38000000-0000-0000-0000-000000000030'
$sql$);
UPDATE sessions SET topic = 'Unrelated update remains valid'
WHERE id = '38000000-0000-0000-0000-000000000030';
RESET ROLE;
UPDATE feature_flags SET enabled = TRUE WHERE key = 'session_notes';

-- Simulate a legacy overlong row: changing another field must remain possible,
-- while replacement notes still have to cross the shaped, bounded RPC.
ALTER TABLE sessions DISABLE TRIGGER enforce_session_notes_feature_flag;
UPDATE sessions SET notes = repeat('x', 4001)
WHERE id = '38000000-0000-0000-0000-000000000030';
ALTER TABLE sessions ENABLE TRIGGER enforce_session_notes_feature_flag;
SELECT pg_temp.as_user('00000000-0000-0000-0000-000000000002');
SET LOCAL ROLE authenticated;
UPDATE sessions SET topic = 'Legacy note row remains updatable'
WHERE id = '38000000-0000-0000-0000-000000000030';
SELECT update_session_note(
    '38000000-0000-0000-0000-000000000030', 'Enabled note'
);
SELECT pg_temp.expect_rejected($sql$
    UPDATE sessions SET notes = 'Direct note bypass'
    WHERE id = '38000000-0000-0000-0000-000000000030'
$sql$);
SELECT pg_temp.expect_rejected($sql$
    SELECT update_session_note(
        '38000000-0000-0000-0000-000000000030', repeat('x', 4001)
    )
$sql$);
RESET ROLE;

-- Awards are invisible/unwritable to Data API users while disabled, but a
-- trusted maintenance connection (the migration owner here) still works.
UPDATE feature_flags SET enabled = FALSE WHERE key = 'awards';
INSERT INTO awards (student_id, award_type, period)
VALUES (
    '38000000-0000-0000-0000-000000000020', 'attendance', '038-maintenance'
);
SELECT pg_temp.as_user('00000000-0000-0000-0000-000000000001');
SET LOCAL ROLE authenticated;
SELECT pg_temp.expect_rejected($sql$
    INSERT INTO awards (student_id, award_type, period, awarded_by)
    VALUES (
        '38000000-0000-0000-0000-000000000020', 'punctuality',
        '038-disabled', '00000000-0000-0000-0000-000000000001'
    )
$sql$);
RESET ROLE;
SELECT pg_temp.as_user('00000000-0000-0000-0000-000000000003');
SET LOCAL ROLE authenticated;
SELECT pg_temp.assert_true(
    NOT EXISTS (
        SELECT 1 FROM awards
        WHERE student_id = '38000000-0000-0000-0000-000000000020'
    ),
    'parent can read awards while feature is disabled'
);
RESET ROLE;
UPDATE feature_flags SET enabled = TRUE WHERE key = 'awards';
SELECT pg_temp.as_user('00000000-0000-0000-0000-000000000001');
SET LOCAL ROLE authenticated;
INSERT INTO awards (student_id, award_type, period, awarded_by)
VALUES (
    '38000000-0000-0000-0000-000000000020', 'punctuality', '038-enabled',
    '00000000-0000-0000-0000-000000000001'
);
RESET ROLE;
SELECT pg_temp.as_user('00000000-0000-0000-0000-000000000003');
SET LOCAL ROLE authenticated;
SELECT pg_temp.assert_true(
    NOT EXISTS (
        SELECT 1 FROM awards
        WHERE student_id = '38000000-0000-0000-0000-000000000020'
    ),
    'parent base-table award read reopened while feature is enabled'
);
RESET ROLE;

-- Populate every child-linked table, then verify anonymisation removes those
-- rows while retaining only the anonymous attendance fact.
INSERT INTO messages (sender_id, student_id, body) VALUES (
    '00000000-0000-0000-0000-000000000003',
    '38000000-0000-0000-0000-000000000023', 'Sensitive message'
);
INSERT INTO result_slips (student_id, exam_name, uploaded_by) VALUES (
    '38000000-0000-0000-0000-000000000023', 'Sensitive result',
    '00000000-0000-0000-0000-000000000001'
);
INSERT INTO student_results (student_id, subject, grade) VALUES (
    '38000000-0000-0000-0000-000000000023', 'Math', 'AL1'
);
INSERT INTO dismissals (session_id, student_id, dismissed_at) VALUES (
    '38000000-0000-0000-0000-000000000034',
    '38000000-0000-0000-0000-000000000023', NOW()
);
INSERT INTO awards (student_id, award_type, period) VALUES (
    '38000000-0000-0000-0000-000000000023', 'attendance', '038-anonymise'
);
INSERT INTO food_polls (id, title) VALUES (
    '38000000-0000-0000-0000-000000000040', 'Sensitive poll'
);
INSERT INTO food_poll_responses (poll_id, student_id, selection) VALUES (
    '38000000-0000-0000-0000-000000000040',
    '38000000-0000-0000-0000-000000000023', '{"choice":1}'::JSONB
);
INSERT INTO consent_records (
    student_id, consent_type, status, method, notice_version
) VALUES (
    '38000000-0000-0000-0000-000000000023', 'data_collection',
    'granted', 'admin_attestation', '1.1'
);
INSERT INTO correction_requests (
    student_id, field_name, requested_value
) VALUES (
    '38000000-0000-0000-0000-000000000023', 'school', 'Sensitive school'
);
INSERT INTO data_disclosures (
    student_id, disclosed_to, disclosure_type, detail
) VALUES (
    '38000000-0000-0000-0000-000000000023', 'Parent response',
    'correction_response',
    jsonb_build_object(
        'applied_value', 'Sensitive school',
        'student_id', '38000000-0000-0000-0000-000000000023'
    )
);
INSERT INTO app_events (
    user_id, platform, session_id, event_type, name, properties
) VALUES (
    '00000000-0000-0000-0000-000000000001', 'web', 'security-038',
    'ops', 'student_action',
    jsonb_build_object(
        'context', jsonb_build_object(
            'student_id', '38000000-0000-0000-0000-000000000023'
        )
    )
);
INSERT INTO app_events (
    user_id, platform, session_id, event_type, name, properties
) VALUES (
    '00000000-0000-0000-0000-000000000001', 'web', 'security-038',
    'ops', 'student_38000000-0000-0000-0000-000000000023', '{}'::JSONB
);

CREATE TEMP TABLE anonymise_original_attendance AS
SELECT id
FROM attendance_records
WHERE session_id = '38000000-0000-0000-0000-000000000034'
  AND student_id = '38000000-0000-0000-0000-000000000023';

SELECT pg_temp.as_user('00000000-0000-0000-0000-000000000001');
SET LOCAL ROLE authenticated;
SELECT pg_temp.assert_true(
    NOT has_function_privilege(
        'authenticated', 'anonymise_student(uuid)', 'EXECUTE'
    )
    AND NOT has_function_privilege(
        'authenticated', '_anonymise_student(uuid)', 'EXECUTE'
    )
    AND NOT has_function_privilege(
        'authenticated', 'anonymise_student_secure(uuid,uuid)', 'EXECUTE'
    ),
    'authenticated can bypass trusted Storage cleanup for anonymisation'
);
SELECT pg_temp.expect_rejected($sql$
    SELECT anonymise_student('38000000-0000-0000-0000-000000000023')
$sql$);
SELECT pg_temp.expect_rejected($sql$
    SELECT _anonymise_student('38000000-0000-0000-0000-000000000023')
$sql$);
SELECT pg_temp.expect_rejected($sql$
    SELECT anonymise_student_secure(
        '38000000-0000-0000-0000-000000000023',
        '00000000-0000-0000-0000-000000000001'
    )
$sql$);
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT pg_temp.expect_rejected($sql$
    SELECT anonymise_student_secure(
        '38000000-0000-0000-0000-000000000023',
        '00000000-0000-0000-0000-000000000002'
    )
$sql$);
SELECT anonymise_student_secure(
    '38000000-0000-0000-0000-000000000023',
    '00000000-0000-0000-0000-000000000001'
);
RESET ROLE;

SELECT pg_temp.assert_true(
    NOT EXISTS (
        SELECT 1 FROM students
        WHERE id = '38000000-0000-0000-0000-000000000023'
    )
    AND NOT EXISTS (
        SELECT 1 FROM attendance_records
        WHERE student_id = '38000000-0000-0000-0000-000000000023'
           OR id IN (SELECT id FROM anonymise_original_attendance)
    )
    AND EXISTS (
        SELECT 1
        FROM attendance_records ar
        JOIN students st ON st.id = ar.student_id
        WHERE ar.session_id = '38000000-0000-0000-0000-000000000034'
          AND st.id <> '38000000-0000-0000-0000-000000000023'
          AND st.full_name = 'Redacted Student'
          AND st.avatar_url IS NULL
          AND st.date_of_birth IS NULL
          AND st.school IS NULL
          AND st.year_of_study IS NULL
          AND st.notes IS NULL
          AND st.is_active = FALSE
          AND ar.status = 'late'
          AND ar.notes IS NULL
          AND ar.late_reason IS NULL
          AND ar.marked_by IS NULL
          AND ar.client_mutation_id IS NULL
    ),
    'student and attendance identifiers were not rotated and scrubbed'
);
SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1 FROM student_storage_cleanup_queue
        WHERE student_id = '38000000-0000-0000-0000-000000000023'
          AND reason = 'anonymise'
    ),
    'anonymisation did not enqueue durable Storage cleanup'
);
SELECT pg_temp.assert_true(
    NOT EXISTS (
        SELECT 1 FROM parent_student_links
        WHERE student_id = '38000000-0000-0000-0000-000000000023'
    )
    AND NOT EXISTS (
        SELECT 1 FROM enrollments
        WHERE student_id = '38000000-0000-0000-0000-000000000023'
    )
    AND NOT EXISTS (
        SELECT 1 FROM messages
        WHERE student_id = '38000000-0000-0000-0000-000000000023'
    )
    AND NOT EXISTS (
        SELECT 1 FROM result_slips
        WHERE student_id = '38000000-0000-0000-0000-000000000023'
    )
    AND NOT EXISTS (
        SELECT 1 FROM student_results
        WHERE student_id = '38000000-0000-0000-0000-000000000023'
    )
    AND NOT EXISTS (
        SELECT 1 FROM dismissals
        WHERE student_id = '38000000-0000-0000-0000-000000000023'
    )
    AND NOT EXISTS (
        SELECT 1 FROM awards
        WHERE student_id = '38000000-0000-0000-0000-000000000023'
    )
    AND NOT EXISTS (
        SELECT 1 FROM food_poll_responses
        WHERE student_id = '38000000-0000-0000-0000-000000000023'
    )
    AND NOT EXISTS (
        SELECT 1 FROM consent_records
        WHERE student_id = '38000000-0000-0000-0000-000000000023'
    )
    AND NOT EXISTS (
        SELECT 1 FROM correction_requests
        WHERE student_id = '38000000-0000-0000-0000-000000000023'
    )
    AND NOT EXISTS (
        SELECT 1 FROM app_events
        WHERE properties::TEXT LIKE '%38000000-0000-0000-0000-000000000023%'
           OR name LIKE '%38000000-0000-0000-0000-000000000023%'
    ),
    'child-linked rows survived anonymisation'
);
SELECT pg_temp.assert_true(
    NOT EXISTS (
        SELECT 1 FROM data_disclosures
        WHERE student_id = '38000000-0000-0000-0000-000000000023'
           OR detail::TEXT LIKE '%38000000-0000-0000-0000-000000000023%'
           OR detail::TEXT LIKE '%Sensitive school%'
    )
    AND EXISTS (
        SELECT 1 FROM data_disclosures
        WHERE disclosure_type = 'correction_response'
          AND student_id IS NULL
          AND disclosed_to = '[redacted]'
          AND detail IS NULL
    ),
    'disclosure ledger retained child PII after anonymisation'
);

SELECT pg_temp.as_user('00000000-0000-0000-0000-000000000003');
SET LOCAL ROLE authenticated;
SELECT pg_temp.assert_true(
    NOT EXISTS (
        SELECT 1 FROM get_parent_children()
        WHERE id = '38000000-0000-0000-0000-000000000023'
    ),
    'former parent can still resolve the anonymised child'
);
RESET ROLE;

SELECT pg_temp.as_user('00000000-0000-0000-0000-000000000002');
SET LOCAL ROLE authenticated;
SELECT pg_temp.assert_true(
    NOT EXISTS (
        SELECT 1 FROM attendance_records
        WHERE session_id = '38000000-0000-0000-0000-000000000034'
    ),
    'tutor can correlate retained anonymised attendance'
);
RESET ROLE;

-- Hard erasure also scrubs indirect disclosure/analytics payloads before the
-- FK cascades remove the student identity.
INSERT INTO data_disclosures (
    student_id, disclosed_to, disclosure_type, detail
) VALUES (
    '38000000-0000-0000-0000-000000000024', 'Erase response',
    'correction_response',
    jsonb_build_object('applied_value', 'Erase PII')
);
INSERT INTO app_events (
    user_id, platform, session_id, event_type, name, properties
) VALUES (
    '00000000-0000-0000-0000-000000000001', 'web', 'security-038',
    'ops', 'erase_38000000-0000-0000-0000-000000000024', '{}'::JSONB
);
SELECT pg_temp.as_user('00000000-0000-0000-0000-000000000001');
SET LOCAL ROLE authenticated;
SELECT pg_temp.assert_true(
    NOT has_function_privilege(
        'authenticated', 'erase_student(uuid)', 'EXECUTE'
    )
    AND NOT has_function_privilege(
        'authenticated', 'erase_student_secure(uuid,uuid)', 'EXECUTE'
    ),
    'authenticated can bypass trusted Storage cleanup for hard erasure'
);
SELECT pg_temp.as_user('00000000-0000-0000-0000-000000000001');
SET LOCAL ROLE authenticated;
SELECT pg_temp.expect_rejected($sql$
    DELETE FROM students
    WHERE id = '38000000-0000-0000-0000-000000000024'
$sql$);
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.expect_rejected($sql$
    SELECT erase_student('38000000-0000-0000-0000-000000000024')
$sql$);
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT pg_temp.expect_rejected($sql$
    SELECT erase_student_secure(
        '38000000-0000-0000-0000-000000000024',
        '00000000-0000-0000-0000-000000000002'
    )
$sql$);
SELECT erase_student_secure(
    '38000000-0000-0000-0000-000000000024',
    '00000000-0000-0000-0000-000000000001'
);
RESET ROLE;
SELECT pg_temp.assert_true(
    NOT EXISTS (
        SELECT 1 FROM students
        WHERE id = '38000000-0000-0000-0000-000000000024'
    )
    AND NOT EXISTS (
        SELECT 1 FROM app_events
        WHERE name LIKE '%38000000-0000-0000-0000-000000000024%'
    )
    AND NOT EXISTS (
        SELECT 1 FROM data_disclosures
        WHERE detail::TEXT LIKE '%Erase PII%'
           OR student_id = '38000000-0000-0000-0000-000000000024'
    )
    AND (
        SELECT COUNT(*) >= 2 FROM data_disclosures
        WHERE disclosure_type = 'correction_response'
          AND disclosed_to = '[redacted]'
          AND student_id IS NULL
          AND detail IS NULL
    ),
    'hard erase retained indirect child PII'
);
SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1 FROM student_storage_cleanup_queue
        WHERE student_id = '38000000-0000-0000-0000-000000000024'
          AND reason = 'erase'
    ),
    'hard erase did not enqueue durable Storage cleanup'
);

-- Anonymous users receive only the current public privacy notice, not internal
-- breach/retention documents.
INSERT INTO policy_documents (
    doc_type, version, title, body, is_current
) VALUES (
    'breach_plan', 'security-038', 'Internal breach plan', 'Do not publish', TRUE
);
SET LOCAL ROLE anon;
SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1 FROM policy_documents
        WHERE doc_type = 'data_protection_notice' AND is_current
    )
    AND NOT EXISTS (
        SELECT 1 FROM policy_documents
        WHERE doc_type <> 'data_protection_notice'
    ),
    'anonymous policy boundary hides the notice or exposes an internal document'
);
RESET ROLE;

SELECT pg_temp.as_user('00000000-0000-0000-0000-000000000003');
SET LOCAL ROLE authenticated;
SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1 FROM policy_documents
        WHERE doc_type = 'data_protection_notice' AND is_current
    )
    AND NOT EXISTS (
        SELECT 1 FROM policy_documents WHERE doc_type = 'breach_plan'
    ),
    'parent can read an internal policy document'
);
RESET ROLE;

SELECT pg_temp.as_user('00000000-0000-0000-0000-000000000002');
SET LOCAL ROLE authenticated;
SELECT pg_temp.assert_true(
    NOT EXISTS (
        SELECT 1 FROM policy_documents WHERE doc_type = 'breach_plan'
    ),
    'tutor can read an internal policy document'
);
RESET ROLE;

SELECT pg_temp.as_user('38000000-0000-0000-0000-000000000002');
SET LOCAL ROLE authenticated;
SELECT pg_temp.assert_true(
    EXISTS (
        SELECT 1 FROM policy_documents
        WHERE doc_type = 'breach_plan' AND version = 'security-038'
    ),
    'admin cannot read the internal breach plan'
);
RESET ROLE;

DO $$
BEGIN
    RAISE NOTICE 'security_boundary_hardening_test: all assertions passed';
END;
$$;
ROLLBACK;
