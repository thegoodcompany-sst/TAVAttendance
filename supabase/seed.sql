-- ============================================================
-- TAVA Attendance — Development Seed Data
-- Run ONLY against a local Supabase instance.
-- ============================================================
-- Creates three users (admin, tutor, parent) with known passwords,
-- two classes, five students, one session, and sample attendance.
-- ============================================================

-- Passwords for all seed users: TAVAdev123!

-- Guard: refuse to seed anything but a fresh local instance. This file creates a
-- known-UUID admin with a published password; running it against a populated
-- (e.g. production) database would plant a backdoor account.
DO $$
BEGIN
    IF (SELECT COUNT(*) FROM auth.users) > 3 THEN
        RAISE EXCEPTION 'seed.sql: refusing to run — auth.users already populated (not a fresh local instance)';
    END IF;
END $$;

-- ── Auth users (created via Supabase auth schema directly for seeding) ──

INSERT INTO auth.users (
    id, email, encrypted_password, email_confirmed_at, role, aud,
    raw_user_meta_data, created_at, updated_at
) VALUES
    (
        '00000000-0000-0000-0000-000000000001',
        'admin@tava.dev',
        crypt('TAVAdev123!', gen_salt('bf')),
        NOW(), 'authenticated', 'authenticated',
        '{"full_name": "TAVA Admin", "role": "admin"}',
        NOW(), NOW()
    ),
    (
        '00000000-0000-0000-0000-000000000002',
        'tutor@tava.dev',
        crypt('TAVAdev123!', gen_salt('bf')),
        NOW(), 'authenticated', 'authenticated',
        '{"full_name": "Jane Tutor", "role": "tutor"}',
        NOW(), NOW()
    ),
    (
        '00000000-0000-0000-0000-000000000003',
        'parent@tava.dev',
        crypt('TAVAdev123!', gen_salt('bf')),
        NOW(), 'authenticated', 'authenticated',
        '{"full_name": "Mary Parent", "role": "parent"}',
        NOW(), NOW()
    )
ON CONFLICT (id) DO NOTHING;

-- Profiles created by trigger; add phone numbers
UPDATE profiles SET phone = '+6591234567' WHERE id = '00000000-0000-0000-0000-000000000002';
UPDATE profiles SET phone = '+6598765432' WHERE id = '00000000-0000-0000-0000-000000000003';


-- ── Classes ──────────────────────────────────────────────────
-- Mirrors TAVA's real tuition: Math on Mondays, English & Reading on Thursdays,
-- both ~7:30pm, mixed primary + secondary (tava.sg/our-programs).
INSERT INTO classes (id, name, subject, level, schedule_day, schedule_time, duration_minutes) VALUES
    ('10000000-0000-0000-0000-000000000001', 'Math (Mon)',               'Mathematics', 'Mixed', 'Monday',   '19:30', 90),
    ('10000000-0000-0000-0000-000000000002', 'English (Thu)',            'English',     'Mixed', 'Thursday', '19:30', 90),
    ('10000000-0000-0000-0000-000000000003', 'Reading & Literacy (Thu)', 'Reading',     'Mixed', 'Thursday', '19:30', 90);


-- ── Assign tutor to all classes ──────────────────────────────
INSERT INTO class_tutor_assignments (class_id, tutor_id) VALUES
    ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002'),
    ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000002'),
    ('10000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000002');


-- ── Students (mix of primary and secondary) ──────────────────
INSERT INTO students (id, full_name, school, year_of_study) VALUES
    ('20000000-0000-0000-0000-000000000001', 'Alice Tan',   'Bukit Batok Primary',  'Pri 5'),
    ('20000000-0000-0000-0000-000000000002', 'Ben Lim',     'Bukit Batok Primary',  'Pri 6'),
    ('20000000-0000-0000-0000-000000000003', 'Chloe Wong',  'Bukit View Secondary', 'Sec 2'),
    ('20000000-0000-0000-0000-000000000004', 'David Ng',    'Bukit View Secondary', 'Sec 3'),
    ('20000000-0000-0000-0000-000000000005', 'Emma Koh',    'Bukit View Secondary', 'Sec 4');


-- ── Parent ↔ Student Link ─────────────────────────────────────
INSERT INTO parent_student_links (parent_id, student_id) VALUES
    ('00000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000001');


-- ── Enrollments ───────────────────────────────────────────────
INSERT INTO enrollments (student_id, class_id) VALUES
    ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001'),  -- Alice → Math
    ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001'),  -- Ben → Math
    ('20000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000001'),  -- Chloe → Math
    ('20000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000002'),  -- Chloe → English
    ('20000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000002'),  -- David → English
    ('20000000-0000-0000-0000-000000000005', '10000000-0000-0000-0000-000000000002'),  -- Emma → English
    ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000003'),  -- Alice → Reading
    ('20000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000003');  -- David → Reading


-- ── Sample Session ────────────────────────────────────────────
INSERT INTO sessions (id, class_id, session_date, topic) VALUES
    (
        '30000000-0000-0000-0000-000000000001',
        '10000000-0000-0000-0000-000000000001',
        CURRENT_DATE,
        'Algebra: Linear Equations'
    );


-- ── Sample Attendance ─────────────────────────────────────────
INSERT INTO attendance_records (session_id, student_id, status, marked_by, client_mutation_id) VALUES
    ('30000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'present', '00000000-0000-0000-0000-000000000002', 'seed-mut-001'),
    ('30000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000002', 'late',    '00000000-0000-0000-0000-000000000002', 'seed-mut-002'),
    ('30000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000003', 'absent',  '00000000-0000-0000-0000-000000000002', 'seed-mut-003');
