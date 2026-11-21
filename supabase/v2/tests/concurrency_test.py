#!/usr/bin/env python3
"""Two-connection integration races. Local psql only; no Python DB dependency.

Fixtures are owned by this test and removed in FK order in finally. No seed rows
are changed. Barriers observe actual pg_stat_activity lock waits, not guessed sleeps.
"""
import concurrent.futures
import json
import os
import re
import subprocess
import sys
import time
import uuid
from datetime import datetime, timezone, timedelta

DB = sys.argv[1] if len(sys.argv) == 2 else os.environ.get('TP_DB', '')
if len(sys.argv) > 2 or not re.fullmatch(r'tp_[a-z0-9_]{1,60}', DB):
    raise SystemExit('Explicit assigned tp_ database required')
ENV = {k: v for k, v in os.environ.items() if not k.startswith('PG')}
ENV['PGPASSFILE'] = '/dev/null'
ENV['PGSERVICEFILE'] = '/dev/null'
CMD = ['psql', '-X', '-qAt', '-h', 'localhost', '-p', '55432', '-U', 'postgres', '-d', DB, '-v', 'ON_ERROR_STOP=1']
A = '10000000-0000-4000-8000-000000000011'
B = '10000000-0000-4000-8000-000000000012'
D = '10000000-0000-4000-8000-000000000014'
ADMIN = '10000000-0000-4000-8000-000000000001'
STUDENT = '20000000-0000-4000-8000-000000000001'
N = (datetime.now(timezone.utc)-timedelta(days=1)).replace(hour=4, minute=0, second=0, microsecond=0).isoformat()
FIXTURES = []
CLIENTS = []
PASSES = 0


def uid():
    return str(uuid.uuid4())


def sql(statement):
    result = subprocess.run(CMD, input=statement, text=True, capture_output=True, env=ENV, timeout=12)
    if result.returncode:
        raise RuntimeError(result.stderr.strip())
    return result.stdout.strip()


def ok(condition, label):
    global PASSES
    if not condition:
        raise AssertionError(label)
    PASSES += 1
    print('NOTICE:  PASS concurrency ' + label, flush=True)


class Session:
    def __init__(self, role='service_role', actor=None):
        self.name = 'tp_concurrency_' + uuid.uuid4().hex
        self.proc = subprocess.Popen(CMD, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1, env=ENV)
        CLIENTS.append(self)
        self.execute(f"BEGIN; SET LOCAL statement_timeout='6s'; SET LOCAL lock_timeout='5s'; SET LOCAL application_name='{self.name}'; SET LOCAL ROLE {role};")
        if actor:
            self.execute("SELECT set_config('request.jwt.claims','" + json.dumps({'sub': actor}) + "',true);")

    def execute(self, statement):
        marker = 'done_' + uuid.uuid4().hex
        self.proc.stdin.write(statement + "\nSELECT '" + marker + "';\n")
        self.proc.stdin.flush()
        output = []
        while True:
            line = self.proc.stdout.readline()
            if not line:
                raise RuntimeError(self.proc.stderr.read().strip())
            line = line.strip()
            if line == marker:
                return '\n'.join(output)
            if line:
                output.append(line)

    def close(self):
        if self.proc.poll() is None:
            try:
                self.proc.stdin.write('ROLLBACK;\n\\q\n')
                self.proc.stdin.flush()
                self.proc.wait(timeout=2)
            except (BrokenPipeError, subprocess.TimeoutExpired):
                self.proc.kill()
                self.proc.wait(timeout=2)
        for stream in (self.proc.stdin, self.proc.stdout, self.proc.stderr):
            stream.close()


def fixture(worker=False, teacher=A, marked=False):
    lesson, cls = uid(), uid()
    start = f"'{N}'::timestamptz-interval '2 hours'"
    end = f"'{N}'::timestamptz+interval '5 minutes'"
    sql(f"""BEGIN;
    INSERT INTO public.classes(id,short_label,subject) VALUES('{cls}','Demo Race {cls[:8]}','Demo');
    INSERT INTO public.lessons(id,class_id,occurrence_date,scheduled_start_at,scheduled_end_at,accountable_teacher_id,overdue_at)
    VALUES('{lesson}','{cls}',(({start}) AT TIME ZONE 'Asia/Singapore')::date,{start},{end},'{teacher}',{end}+interval '75 minutes');
    INSERT INTO public.lesson_staff VALUES('{lesson}','{teacher}','regular');
    INSERT INTO public.lesson_roster(lesson_id,student_id) VALUES('{lesson}','{STUDENT}');
    COMMIT;""")
    FIXTURES.append((lesson, cls))
    if marked:
        sql(f"""BEGIN; INSERT INTO public.attendance_records VALUES('{lesson}','{STUDENT}','present',NULL,'{A}',clock_timestamp(),'{uid()}');
        UPDATE public.lessons SET register_revision=1 WHERE id='{lesson}'; COMMIT;""")
    return lesson


def claim(session, lesson):
    output = session.execute(f"SELECT row_to_json(c) FROM public.scheduler_tick('{N}',1) c;")
    value = json.loads(output) if output else None
    if not value or value['lesson_id'] != lesson:
        raise AssertionError('expected fixture claim')
    return value


def wait_for_lock(session):
    until = time.monotonic() + 3
    while time.monotonic() < until:
        if sql(f"SELECT count(*) FROM pg_stat_activity WHERE application_name='{session.name}' AND wait_event_type='Lock';") == '1':
            return
        time.sleep(0.02)
    raise AssertionError('competing transaction did not reach lock barrier')


def expect_conflict(future, label):
    try:
        future.result(timeout=8)
    except RuntimeError as err:
        ok('TP_CONFLICT' in str(err), label)
    else:
        raise AssertionError(label + ': unexpectedly succeeded')


def stop_lesson(lesson):
    sql(f"BEGIN; UPDATE public.lessons SET cancelled_at=clock_timestamp(),cancellation_reason='manual',plan_revision=plan_revision+1 WHERE id='{lesson}'; COMMIT;")


def tests():
    # Two workers claim while the first still holds all its lesson/plan/outbox locks.
    one, two = fixture(worker=True), fixture(worker=True, teacher=B)
    w1, w2 = Session(), Session()
    first = json.loads(w1.execute(f"SELECT row_to_json(c) FROM public.scheduler_tick('{N}',1) c;"))
    began = time.monotonic()
    second = json.loads(w2.execute(f"SELECT row_to_json(c) FROM public.scheduler_tick('{N}',1) c;"))
    ok(first['outbox_id'] != second['outbox_id'] and {first['lesson_id'], second['lesson_id']} == {one, two}, 'ticks claim disjoint lessons')
    ok(time.monotonic()-began < 2, 'SKIP LOCKED avoids held lesson')
    w1.execute('COMMIT;'); w2.execute('COMMIT;')
    stop_lesson(one); stop_lesson(two)

    # Submit starts with a stale UI revision while a mark is uncommitted.
    lesson = fixture()
    writer, submitter = Session('authenticated', A), Session('authenticated', A)
    writer.execute(f"SELECT public.mark_all_present('{lesson}',0,'{uid()}');")
    with concurrent.futures.ThreadPoolExecutor() as pool:
        future = pool.submit(submitter.execute, f"SELECT public.submit_lesson('{lesson}',0,0,'{uid()}');")
        wait_for_lock(submitter)
        ok(not future.done(), 'submission waits for attendance lesson lock')
        writer.execute('COMMIT;')
        expect_conflict(future, 'stale submit rejects committed attendance revision')
    ok(sql(f"SELECT count(*) FROM public.lesson_submissions WHERE lesson_id='{lesson}';") == '0', 'no stale submission receipt')
    stop_lesson(lesson)

    # Explicit combined confirmation must share the same lock/CAS boundary.
    lesson = fixture()
    writer, confirmer = Session('authenticated', A), Session('authenticated', A)
    writer.execute(f"SELECT public.mark_attendance('{lesson}','{STUDENT}','absent',true,NULL,0,'{uid()}');")
    with concurrent.futures.ThreadPoolExecutor() as pool:
        future = pool.submit(confirmer.execute, f"SELECT public.confirm_all_present_and_submit('{lesson}',0,0,'{uid()}');")
        wait_for_lock(confirmer)
        ok(not future.done(), 'atomic confirmation waits for attendance lock')
        writer.execute('COMMIT;')
        expect_conflict(future, 'atomic confirmation rejects a concurrently changed register')
    ok(sql(f"SELECT status FROM public.attendance_records WHERE lesson_id='{lesson}';") == 'absent', 'atomic confirmation never overwrites concurrent absence')
    ok(sql(f"SELECT count(*) FROM public.lesson_submissions WHERE lesson_id='{lesson}';") == '0', 'atomic confirmation conflict leaves no submission')
    confirmer = Session('authenticated', A)
    mutation = uid()
    first = json.loads(confirmer.execute(f"SELECT public.confirm_all_present_and_submit('{lesson}',1,0,'{mutation}');"))
    confirmer.execute('COMMIT;')
    replayer = Session('authenticated', A)
    replay = json.loads(replayer.execute(f"SELECT public.confirm_all_present_and_submit('{lesson}',1,0,'{mutation}');"))
    ok(first['submission_id'] == replay['submission_id'] and replay['replayed'], 'atomic confirmation exact receipt survives committed replay')
    replayer.execute('COMMIT;')

    # Clear/update both observed the same row. Only the first can succeed.
    lesson = fixture(marked=True)
    observed = sql(f"SELECT marked_at FROM public.attendance_records WHERE lesson_id='{lesson}';")
    clearer, updater = Session('authenticated', A), Session('authenticated', A)
    clearer.execute(f"SELECT public.mark_attendance('{lesson}','{STUDENT}',NULL,NULL,'{observed}',1,'{uid()}');")
    with concurrent.futures.ThreadPoolExecutor() as pool:
        future = pool.submit(updater.execute, f"SELECT public.mark_attendance('{lesson}','{STUDENT}','late',NULL,'{observed}',1,'{uid()}');")
        wait_for_lock(updater)
        clearer.execute('COMMIT;')
        expect_conflict(future, 'clear versus update CAS rejects stale update')
    ok(sql(f"SELECT count(*) FROM public.attendance_records WHERE lesson_id='{lesson}';") == '0', 'clear remains no row')
    stop_lesson(lesson)

    # A prepare that began before reassignment commits must wait, then suppress.
    for action in ['substitute', 'cancel']:
        lesson = fixture(worker=True)
        worker = Session()
        c = claim(worker, lesson)
        worker.execute('COMMIT;')
        editor, preparer = Session('authenticated', ADMIN), Session()
        operation = f"public.assign_lesson_teacher('{lesson}','{D}',false)" if action == 'substitute' else f"public.cancel_lesson('{lesson}')"
        editor.execute('SELECT ' + operation + ';')
        with concurrent.futures.ThreadPoolExecutor() as pool:
            future = pool.submit(preparer.execute, f"SELECT public.prepare_prompt_delivery('{c['outbox_id']}','{c['lease_token']}','{N}') IS NULL;")
            wait_for_lock(preparer)
            editor.execute('COMMIT;')
            ok(future.result(timeout=8) == 't', action + ' suppresses prepare after lock wait')
        preparer.execute('COMMIT;')
        stop_lesson(lesson)

    # Submission and an existing claim share the same lock order and cancel lease.
    lesson = fixture(marked=True)
    sql(f"UPDATE public.notification_plans SET due_at='{N}' WHERE lesson_id='{lesson}' AND kind='heads_up';")
    worker = Session(); c = claim(worker, lesson); worker.execute('COMMIT;')
    submitter, preparer = Session('authenticated', A), Session()
    submitter.execute(f"SELECT public.submit_lesson('{lesson}',1,0,'{uid()}');")
    with concurrent.futures.ThreadPoolExecutor() as pool:
        future = pool.submit(preparer.execute, f"SELECT public.prepare_prompt_delivery('{c['outbox_id']}','{c['lease_token']}','{N}') IS NULL;")
        wait_for_lock(preparer); submitter.execute('COMMIT;')
        ok(future.result(timeout=8) == 't', 'submission stops prepare on every device')
    preparer.execute('COMMIT;')

    # Reclaim owns a fresh lease while a late acknowledgement is waiting.
    lesson = fixture(worker=True)
    worker = Session(); old = claim(worker, lesson); worker.execute('COMMIT;')
    reclaimer, late = Session(), Session()
    current = json.loads(reclaimer.execute(f"SELECT row_to_json(c) FROM public.scheduler_tick('{N}'::timestamptz+interval '121 seconds',1) c;"))
    with concurrent.futures.ThreadPoolExecutor() as pool:
        future = pool.submit(late.execute, f"SELECT public.mark_prompt_sent('{old['outbox_id']}','{old['lease_token']}','{old['outbox_id']}','dry_run','{N}'::timestamptz+interval '122 seconds');")
        wait_for_lock(late); reclaimer.execute('COMMIT;')
        ok(future.result(timeout=8) == 'f', 'old lease acknowledgement cannot win')
    late.execute('COMMIT;')
    ok(current['attempt_no'] == 2 and current['lease_token'] != old['lease_token'], 'reclaim uses new version')
    stop_lesson(lesson)


def cleanup():
    for session in CLIENTS:
        session.close()
    for lesson, cls in reversed(FIXTURES):
        sql(f"""BEGIN;
        DELETE FROM public.notification_deliveries WHERE outbox_id IN (SELECT o.id FROM public.notification_outbox o JOIN public.notification_plans p ON p.id=o.plan_id WHERE p.lesson_id='{lesson}');
        DELETE FROM public.notification_outbox WHERE plan_id IN (SELECT id FROM public.notification_plans WHERE lesson_id='{lesson}');
        DELETE FROM public.notification_plans WHERE lesson_id='{lesson}';
        DELETE FROM public.mutation_receipts WHERE lesson_id='{lesson}';
        DELETE FROM public.audit_events WHERE lesson_id='{lesson}';
        DELETE FROM public.lesson_submissions WHERE lesson_id='{lesson}';
        DELETE FROM public.lesson_feedback WHERE lesson_id='{lesson}';
        DELETE FROM public.lessons WHERE id='{lesson}';
        DELETE FROM public.classes WHERE id='{cls}'; COMMIT;""")


try:
    tests()
finally:
    cleanup()
print(f'Concurrency summary: {PASSES} passed, 0 failed')
