#!/usr/bin/env python3
"""Exercise real row-lock races against the disposable local Supabase database.

Run after `supabase db reset --local`:
    python3 supabase/tests/sync_attendance_concurrency_test.py
Uses Docker's psql, no host database driver or remote credentials. Only exact,
randomized test fixture IDs are removed. Requires the seeded local admin.
"""
import json
import subprocess
import time
import tomllib
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROJECT = tomllib.loads((ROOT / 'supabase/config.toml').read_text())['project_id']
PSQL = ['docker', 'exec', '-i', f'supabase_db_{PROJECT}', 'psql', '-X', '-qAt',
        '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1']
ACTOR = '00000000-0000-0000-0000-000000000001'
AUTH = f"SET request.jwt.claim.sub = '{ACTOR}'; SET request.jwt.claim.role = 'authenticated'; SET ROLE authenticated;"


def query(sql):
    return subprocess.run(PSQL, input=sql, text=True, capture_output=True,
                          check=True, timeout=20).stdout.strip()


def literal(value):
    return "'" + str(value).replace("'", "''") + "'"


def race(kind):
    class_id, session_id, student_id = [str(uuid.uuid4()) for _ in range(3)]
    mutation = 'concurrency-' + str(uuid.uuid4())
    application = 'tava-cas-' + str(uuid.uuid4())
    where = f"session_id = '{session_id}' AND student_id = '{student_id}'"
    worker = None
    writer = None
    try:
        query(f"""
            INSERT INTO classes (id, name) VALUES ('{class_id}', 'CAS concurrency fixture');
            INSERT INTO sessions (id, class_id, session_date)
            VALUES ('{session_id}', '{class_id}', (NOW() AT TIME ZONE 'Asia/Singapore')::DATE);
            INSERT INTO students (id, full_name) VALUES ('{student_id}', 'CAS concurrency fixture');
            INSERT INTO enrollments (student_id, class_id, enrolled_at)
            VALUES ('{student_id}', '{class_id}', NOW() - INTERVAL '1 day');
        """)
        observed = None
        if kind != 'insert':
            query(AUTH + f"""
                INSERT INTO attendance_records (session_id, student_id, status, client_mutation_id)
                VALUES ('{session_id}', '{student_id}', 'present', '{mutation}-initial');
            """)
            observed = query(f'SELECT marked_at FROM attendance_records WHERE {where};')

        writer = subprocess.Popen(PSQL, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE, text=True, bufsize=1)
        writer.stdin.write('BEGIN;\n' + AUTH + '\n')
        if kind == 'insert':
            writer.stdin.write(f"INSERT INTO attendance_records (session_id, student_id, status, client_mutation_id) VALUES ('{session_id}', '{student_id}', 'late', '{mutation}-online');\n")
        elif kind == 'delete':
            writer.stdin.write(f"SELECT clear_attendance('{session_id}', '{student_id}', '{mutation}-online');\n")
        else:
            writer.stdin.write(f"UPDATE attendance_records SET status = 'late', client_mutation_id = '{mutation}-online' WHERE {where};\n")
        writer.stdin.write('\\echo READY\n')
        writer.stdin.flush()
        while True:
            line = writer.stdout.readline()
            if line.strip() == 'READY':
                break
            if not line:
                raise AssertionError('online writer failed: ' + writer.stderr.read())

        payload = [{
            'session_id': session_id, 'student_id': student_id,
            'status': None if kind == 'clear' else 'absent',
            'client_mutation_id': mutation + '-offline',
            'observed_marked_at': observed,
        }]
        worker = subprocess.Popen(PSQL, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE, text=True)
        worker.stdin.write(AUTH + f"SET application_name = '{application}'; SELECT sync_attendance({literal(json.dumps(payload))}::jsonb);\n")
        worker.stdin.close()
        # Wait for PostgreSQL to prove the offline operation reached the
        # uncommitted row, instead of relying on a timing-dependent sleep.
        deadline = time.monotonic() + 10
        while query(f"SELECT EXISTS (SELECT 1 FROM pg_stat_activity WHERE application_name = '{application}' AND wait_event_type = 'Lock');") != 't':
            if time.monotonic() > deadline or worker.poll() is not None:
                raise AssertionError(f'{kind}: offline writer did not block on concurrent write')
            time.sleep(0.05)
        writer.stdin.write('COMMIT;\n\\q\n')
        writer.stdin.flush()
        writer.wait(timeout=10)
        assert writer.returncode == 0, writer.stderr.read()
        worker.wait(timeout=10)
        output = worker.stdout.read().strip()
        assert worker.returncode == 0, worker.stderr.read()
        result = json.loads(output.splitlines()[-1])
        assert result['skipped_conflict'] == 1 and result['synced'] == 0, (kind, result)
        status = query(f'SELECT status FROM attendance_records WHERE {where};')
        assert status == ('' if kind == 'delete' else 'late'), (kind, status)
        assert query(f"SELECT count(*) FROM attendance_mutation_receipts WHERE mutation_id = '{mutation}-offline';") == '0'
        print(f'{kind}: concurrent correction preserved')
    finally:
        for process in (worker, writer):
            if process is not None and process.poll() is None:
                process.kill()
                process.wait(timeout=10)
        query(f"""
            BEGIN;
            SET LOCAL app.suppress_audit = 'on';
            SET LOCAL app.attendance_clear = 'on';
            DELETE FROM attendance_records WHERE {where};
            DELETE FROM attendance_mutation_receipts WHERE student_id = '{student_id}';
            DELETE FROM enrollments WHERE student_id = '{student_id}';
            DELETE FROM students WHERE id = '{student_id}';
            DELETE FROM sessions WHERE id = '{session_id}';
            DELETE FROM classes WHERE id = '{class_id}';
            COMMIT;
        """)


if __name__ == '__main__':
    for scenario in ('update', 'clear', 'insert', 'delete'):
        race(scenario)
    print('sync_attendance_concurrency_test: all assertions passed')
