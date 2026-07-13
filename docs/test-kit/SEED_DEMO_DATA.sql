-- SEED_DEMO_DATA.sql — staging fixture for the staff TestFlight trial
--
-- PURPOSE
--   Puts a handful of obviously-fake demo students on the kiosk so the trial
--   is not an empty screen, and so screenshots taken during the trial contain
--   NO real names (PDPA).
--
-- DO NOT APPLY TO PROD UNTIL THE CENTRE CONFIRMS A TRIAL DATE.
--   Run this against prod ONLY on the trial morning, then run
--   TEARDOWN_DEMO_DATA.sql the same day once the trial is done.
--
-- HOW IT WORKS
--   One self-contained demo class with NO schedule_day and NO recurrence_rule.
--   Per the kiosk day-filter rule (CLAUDE.md), a class with neither set is
--   treated as ad-hoc and ALWAYS shows on the kiosk, regardless of weekday —
--   so this works on any trial date without touching real classes.
--   schedule_time is 08:00 so an afternoon trial exercises the orange "Late"
--   colour; a morning trial shows green "On Time".
--
--   All rows use fixed literal UUIDs (prefix dede0000-…) so TEARDOWN can delete
--   them exactly, cascading only these rows. No is_study_space rows are created.

BEGIN;

-- ── Demo class (ad-hoc: always visible on the kiosk) ──────────────
INSERT INTO classes (id, name, subject, level, schedule_day, schedule_time, duration_minutes, is_active, is_study_space)
VALUES ('dede0000-0000-0000-0000-000000000001',
        'ZZ Demo Class (delete after trial)', 'Demo', 'Demo',
        NULL, '08:00', 90, TRUE, FALSE);

-- ── Demo students (clearly fake names) ────────────────────────────
INSERT INTO students (id, full_name, school, year_of_study, is_active) VALUES
    ('dede0000-0000-0000-0000-0000000000a1', 'Demo Alice Tan',  'Demo Primary',   'Pri 5', TRUE),
    ('dede0000-0000-0000-0000-0000000000a2', 'Demo Ben Lim',    'Demo Primary',   'Pri 6', TRUE),
    ('dede0000-0000-0000-0000-0000000000a3', 'Demo Chloe Wong', 'Demo Secondary', 'Sec 2', TRUE),
    ('dede0000-0000-0000-0000-0000000000a4', 'Demo David Ng',   'Demo Secondary', 'Sec 3', TRUE),
    ('dede0000-0000-0000-0000-0000000000a5', 'Demo Emma Koh',   'Demo Secondary', 'Sec 4', TRUE);

-- ── Enrollments (put all five in the demo class) ──────────────────
INSERT INTO enrollments (student_id, class_id, is_active)
SELECT id, 'dede0000-0000-0000-0000-000000000001', TRUE
FROM students
WHERE id IN (
    'dede0000-0000-0000-0000-0000000000a1',
    'dede0000-0000-0000-0000-0000000000a2',
    'dede0000-0000-0000-0000-0000000000a3',
    'dede0000-0000-0000-0000-0000000000a4',
    'dede0000-0000-0000-0000-0000000000a5'
);

-- Verify what was inserted (expect 1 class, 5 students, 5 enrollments).
SELECT 'class'       AS kind, COUNT(*) FROM classes     WHERE id = 'dede0000-0000-0000-0000-000000000001'
UNION ALL SELECT 'students',    COUNT(*) FROM students    WHERE id::text LIKE 'dede0000-0000-0000-0000-0000000000a%'
UNION ALL SELECT 'enrollments', COUNT(*) FROM enrollments WHERE class_id = 'dede0000-0000-0000-0000-000000000001';

COMMIT;

-- OPTIONAL — to also exercise the TUTOR roster flow, assign the demo class to
-- a real tutor (kiosk sign-in as admin does NOT need this):
--   INSERT INTO class_tutor_assignments (class_id, tutor_id)
--   VALUES ('dede0000-0000-0000-0000-000000000001', '<tutor_auth_uuid>');
-- TEARDOWN already removes this row by class_id.
