-- TEARDOWN_DEMO_DATA.sql — exact removal of the trial fixture
--
-- Removes ONLY the rows created by SEED_DEMO_DATA.sql, matched by their fixed
-- literal UUIDs (demo class dede0000-…-0001, demo students dede0000-…-a1..a5),
-- plus everything the trial generated for them (attendance, dismissals,
-- sessions). Nothing else is touched.
--
-- Run this on the trial day once the staff are finished, the same way the
-- demo-day rows are torn down (HUMANS.md §37) so attendance percentages are
-- never skewed by demo data.
--
-- Ordered deletes: dismissals and attendance_records have no cascade guarantee
-- from every parent, so delete children before parents explicitly.

BEGIN;

-- 1. Dismissals for demo students or demo-class sessions (no ON DELETE CASCADE).
DELETE FROM dismissals
WHERE student_id::text LIKE 'dede0000-0000-0000-0000-0000000000a%'
   OR session_id IN (SELECT id FROM sessions WHERE class_id = 'dede0000-0000-0000-0000-000000000001');

-- 2. Attendance rows for demo students (also covers demo-class sessions).
DELETE FROM attendance_records
WHERE student_id::text LIKE 'dede0000-0000-0000-0000-0000000000a%'
   OR session_id IN (SELECT id FROM sessions WHERE class_id = 'dede0000-0000-0000-0000-000000000001');

-- 3. Sessions the trial created for the demo class.
DELETE FROM sessions WHERE class_id = 'dede0000-0000-0000-0000-000000000001';

-- 4. Enrollments.
DELETE FROM enrollments
WHERE class_id = 'dede0000-0000-0000-0000-000000000001'
   OR student_id::text LIKE 'dede0000-0000-0000-0000-0000000000a%';

-- 5. Any tutor assignment added for the demo class (optional line in the seed).
DELETE FROM class_tutor_assignments WHERE class_id = 'dede0000-0000-0000-0000-000000000001';

-- 6. The demo class.
DELETE FROM classes WHERE id = 'dede0000-0000-0000-0000-000000000001';

-- 7. The demo students.
DELETE FROM students WHERE id::text LIKE 'dede0000-0000-0000-0000-0000000000a%';

-- Verify nothing remains (every count must be 0).
SELECT 'class'       AS kind, COUNT(*) FROM classes     WHERE id = 'dede0000-0000-0000-0000-000000000001'
UNION ALL SELECT 'students',    COUNT(*) FROM students    WHERE id::text LIKE 'dede0000-0000-0000-0000-0000000000a%'
UNION ALL SELECT 'enrollments', COUNT(*) FROM enrollments WHERE class_id = 'dede0000-0000-0000-0000-000000000001'
UNION ALL SELECT 'sessions',    COUNT(*) FROM sessions    WHERE class_id = 'dede0000-0000-0000-0000-000000000001'
UNION ALL SELECT 'attendance',  COUNT(*) FROM attendance_records WHERE student_id::text LIKE 'dede0000-0000-0000-0000-0000000000a%';

COMMIT;
