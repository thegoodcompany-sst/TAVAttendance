#!/usr/bin/env python3
"""Validate rejection BEFORE any connection; the fake psql must never run."""
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
passes = 0
with tempfile.TemporaryDirectory(prefix='tp_runner_guard_') as directory:
    folder = Path(directory)
    for tool in ('psql', 'createdb', 'dropdb'):
        script = folder / tool
        script.write_text('#!/bin/sh\necho UNSAFE_CONNECTION >&2\nexit 99\n')
        script.chmod(0o700)
    env = {'PATH': directory + ':' + os.environ['PATH']}
    for runner in (['bash', str(root / 'supabase/v2/tests/run.sh')],
                   ['python3', str(root / 'supabase/v2/tests/concurrency_test.py')]):
        for name in (None, 'postgres', 'template0', 'template_any', 'other_pass', 'tp_', 'tp_X', 'tp_a;select', 'tp_'+'a'*61, 'postgresql://postgres@remote:55432/tp_g1'):
            result = subprocess.run(runner + ([] if name is None else [name]), env=env, capture_output=True, text=True, timeout=5)
            assert result.returncode != 0 and 'Explicit assigned tp_ database required' in result.stderr + result.stdout
            assert 'UNSAFE_CONNECTION' not in result.stderr + result.stdout
            passes += 1
            print('NOTICE:  PASS runner guard rejects missing/unsafe assignment')
print(f'Runner guard summary: {passes} passed, 0 failed')
