-- Offline-sync idempotency self-check for sync_attendance (body: migration 016).
-- Plain SQL + ASSERT, no pgTAP. Everything runs in one transaction and ROLLS BACK,
-- so it is safe against any environment that has the schema (local, branch, prod).
--
-- Run:  psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/sync_attendance_test.sql
-- (or paste the whole file into Supabase MCP execute_sql / the SQL editor)
-- Success = "sync_attendance_test: all assertions passed" notice; any failure aborts.
BEGIN;

INSERT INTO classes  (id, name) VALUES ('99999999-0000-0000-0000-000000000001', 'sync_attendance test class');
INSERT INTO sessions (id, class_id, session_date)
VALUES ('99999999-0000-0000-0000-000000000002', '99999999-0000-0000-0000-000000000001', CURRENT_DATE);
INSERT INTO students (id, full_name) VALUES ('99999999-0000-0000-0000-000000000003', 'sync_attendance test student');

CREATE FUNCTION pg_temp.payload(p_status TEXT, p_marked_at TIMESTAMPTZ, p_mutation TEXT)
RETURNS JSONB LANGUAGE SQL AS $$
    SELECT jsonb_build_array(jsonb_build_object(
        'session_id', '99999999-0000-0000-0000-000000000002',
        'student_id', '99999999-0000-0000-0000-000000000003',
        'status', p_status, 'marked_at', p_marked_at, 'client_mutation_id', p_mutation));
$$;

DO $$
DECLARE
    v_session UUID := '99999999-0000-0000-0000-000000000002';
    v_student UUID := '99999999-0000-0000-0000-000000000003';
    r JSONB;
BEGIN
    -- 1. fresh offline record syncs
    r := sync_attendance(pg_temp.payload('present', now(), 'synctest-1'));
    ASSERT (r->>'synced')::int = 1, 'fresh record should sync, got ' || r::text;

    -- 2. exact replay (retry after network drop) must not duplicate or error
    r := sync_attendance(pg_temp.payload('present', (SELECT marked_at FROM attendance_records
                                             WHERE session_id = v_session AND student_id = v_student), 'synctest-1'));
    ASSERT (SELECT count(*) FROM attendance_records
            WHERE session_id = v_session AND student_id = v_student) = 1,
           'replay must not create a second row';

    -- 3. an OLDER offline record must not overwrite the newer server record
    r := sync_attendance(pg_temp.payload('late', now() - interval '1 hour', 'synctest-2'));
    ASSERT (r->>'skipped')::int = 1, 'older record should be skipped, got ' || r::text;
    ASSERT (SELECT status FROM attendance_records
            WHERE session_id = v_session AND student_id = v_student) = 'present',
           'older record must not win';

    -- 4. a NEWER offline record overwrites
    r := sync_attendance(pg_temp.payload('late', now() + interval '1 minute', 'synctest-3'));
    ASSERT (r->>'synced')::int = 1, 'newer record should sync, got ' || r::text;
    ASSERT (SELECT status FROM attendance_records
            WHERE session_id = v_session AND student_id = v_student) = 'late',
           'newer record must win';

    -- 5. client-supplied marked_at is clamped to now()+5min (SEC-06)
    r := sync_attendance(pg_temp.payload('present', now() + interval '2 hours', 'synctest-4'));
    ASSERT (SELECT marked_at <= now() + interval '5 minutes' FROM attendance_records
            WHERE session_id = v_session AND student_id = v_student),
           'future marked_at must be clamped';

    -- 6. records for an ended session are rejected as blocked_ended_session
    UPDATE sessions SET ended_at = now() WHERE id = v_session;
    r := sync_attendance(pg_temp.payload('present', now() + interval '4 minutes', 'synctest-5'));
    ASSERT (r->>'blocked_ended_session')::int = 1,
           'ended session must block, got ' || r::text;

    RAISE NOTICE 'sync_attendance_test: all assertions passed';
END $$;

ROLLBACK;
