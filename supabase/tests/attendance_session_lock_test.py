#!/usr/bin/env python3
"""Real session-closure races; run after `supabase db reset --local`.

Uses only the local Docker database and seeded tutor. Synchronization observes
PostgreSQL lock waits, not a sleep presumed long enough for a query to start.
Run against pre-062 to demonstrate failure, then apply 062 locally and rerun.
"""
import selectors
import subprocess
import time
import uuid

from sync_attendance_concurrency_test import PSQL, query

TUTOR = '00000000-0000-0000-0000-000000000002'
AUTH = (f"SET request.jwt.claim.sub = '{TUTOR}'; "
        "SET request.jwt.claim.role = 'authenticated'; SET ROLE authenticated;")


def start(sql, application, hold=False):
    process = subprocess.Popen(PSQL, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True)
    process.stdin.write(
        AUTH + f"SET application_name = '{application}'; "
        "SET statement_timeout = '15s';\n" + sql + '\n')
    if hold:
        process.stdin.write('\\echo READY\n')
        process.stdin.flush()
    else:
        process.stdin.close()
    return process


def ready(process):
    with selectors.DefaultSelector() as selector:
        selector.register(process.stdout, selectors.EVENT_READ)
        assert selector.select(timeout=10), 'transaction did not become ready'
        assert process.stdout.readline().strip() == 'READY', 'transaction failed before readiness'


def wait_for_lock(process, application):
    deadline = time.monotonic() + 10
    while query(f"""SELECT EXISTS (
        SELECT 1 FROM pg_stat_activity
        WHERE application_name = '{application}' AND wait_event_type = 'Lock'
    );""") != 't':
        assert process.poll() is None, 'operation finished without waiting for session lock'
        assert time.monotonic() < deadline, 'operation did not wait for session lock'
        time.sleep(0.05)


def finish(process):
    process.wait(timeout=20)
    assert process.returncode == 0, process.stderr.read()


def race(kind, attendance_first=False, rollback=False, substitute=False):
    class_id, session_id, student_id = [str(uuid.uuid4()) for _ in range(3)]
    mutation = 'session-lock-' + str(uuid.uuid4())
    application = 'tava-session-lock-' + str(uuid.uuid4())
    where = f"session_id = '{session_id}' AND student_id = '{student_id}'"
    holder = worker = None
    try:
        query(f"""
            INSERT INTO classes (id, name) VALUES ('{class_id}', 'Session lock fixture');
            INSERT INTO sessions (id, class_id, session_date, started_at)
            VALUES ('{session_id}', '{class_id}',
                    (NOW() AT TIME ZONE 'Asia/Singapore')::DATE, NOW());
            INSERT INTO students (id, full_name) VALUES ('{student_id}', 'Session lock fixture');
            INSERT INTO enrollments (student_id, class_id, enrolled_at)
            VALUES ('{student_id}', '{class_id}', NOW() - INTERVAL '1 day');
        """)
        if substitute:
            query(f"UPDATE sessions SET sub_tutor_id = '{TUTOR}' WHERE id = '{session_id}';")
        else:
            query(f"""INSERT INTO class_tutor_assignments (class_id, tutor_id, assigned_from)
                VALUES ('{class_id}', '{TUTOR}', CURRENT_DATE - 1);""")
        if kind in ('correction', 'clear'):
            query(AUTH + f"""
                INSERT INTO attendance_records (session_id, student_id, status, client_mutation_id)
                VALUES ('{session_id}', '{student_id}', 'present', '{mutation}-initial');
            """)
        if kind == 'insert':
            attendance = f"""INSERT INTO attendance_records
                (session_id, student_id, status, client_mutation_id)
                VALUES ('{session_id}', '{student_id}', 'late', '{mutation}');"""
        elif kind == 'correction':
            attendance = f"""UPDATE attendance_records SET status = 'late',
                client_mutation_id = '{mutation}' WHERE {where};"""
        else:
            attendance = f"PERFORM clear_attendance('{session_id}', '{student_id}', '{mutation}');"
        close = f"PERFORM set_session_lifecycle('{session_id}', 'end');"
        # Catch only the documented rejection, and fail if the write was accepted.
        rejected = f"""DO $$ BEGIN
            {attendance}
            RAISE EXCEPTION 'attendance accepted after concurrent closure';
        EXCEPTION WHEN SQLSTATE '{'42501' if kind in ('clear', 'empty_clear') else 'TA001'}'
            THEN NULL;
        END $$;"""
        holder_sql = attendance if attendance_first else close
        worker_sql = close if attendance_first else attendance
        holder = start('BEGIN; DO $$ BEGIN ' + holder_sql + ' END $$;', application + '-holder', True)
        ready(holder)
        worker = start(
            ('DO $$ BEGIN ' + worker_sql + ' END $$;')
            if attendance_first or rollback else rejected, application)
        wait_for_lock(worker, application)
        holder.stdin.write(('ROLLBACK' if rollback else 'COMMIT') + ';\n\\q\n')
        holder.stdin.flush()
        finish(holder)
        finish(worker)

        status = query(f'SELECT status FROM attendance_records WHERE {where};')
        accepted = attendance_first or rollback
        expected = ('late' if kind in ('insert', 'correction') else '') if accepted else (
            'present' if kind in ('correction', 'clear') else '')
        assert status == expected, (kind, status, expected)
        assert query(f"SELECT ended_at IS NOT NULL FROM sessions WHERE id = '{session_id}';") == (
            'f' if rollback else 't')
        if not accepted:
            assert query(f"SELECT count(*) FROM attendance_mutation_receipts WHERE mutation_id = '{mutation}';") == '0'
        print(f'{kind}: attendance_first={attendance_first}, rollback={rollback}, substitute={substitute} passed')
    finally:
        # Close stdin so the server rolls back an unfinished holder transaction.
        for process in (holder, worker):
            if process is not None:
                if process.stdin and not process.stdin.closed:
                    process.stdin.close()
                try:
                    process.wait(timeout=20)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)
        query(f"""
            BEGIN;
            SET LOCAL app.suppress_audit = 'on';
            SET LOCAL app.attendance_clear = 'on';
            DELETE FROM attendance_records WHERE {where};
            DELETE FROM attendance_mutation_receipts WHERE student_id = '{student_id}';
            DELETE FROM enrollments WHERE student_id = '{student_id}';
            DELETE FROM students WHERE id = '{student_id}';
            DELETE FROM sessions WHERE id = '{session_id}';
            DELETE FROM class_tutor_assignments WHERE class_id = '{class_id}';
            DELETE FROM classes WHERE id = '{class_id}';
            COMMIT;
        """)


if __name__ == '__main__':
    # Fail before fixture setup/cleanup if the local database is unavailable.
    query('SELECT 1;')
    for is_substitute in (False, True):
        for scenario in ('insert', 'correction', 'clear', 'empty_clear'):
            race(scenario, substitute=is_substitute)
            race(scenario, attendance_first=True, substitute=is_substitute)
            race(scenario, rollback=True, substitute=is_substitute)
    print('attendance_session_lock_test: all assertions passed')
