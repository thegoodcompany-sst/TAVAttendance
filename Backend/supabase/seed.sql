-- ============================================================
-- TAVA Attendance — Development Seed Data
-- Run ONLY against a local Supabase instance.
-- ============================================================
-- Creates three users (admin, tutor, parent) with known passwords,
-- two classes, five students, one session, and sample attendance.
-- ============================================================

-- Passwords for all seed users: TAVAdev123!

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
INSERT INTO classes (id, name, subject, level, schedule_day, schedule_time, duration_minutes) VALUES
    ('10000000-0000-0000-0000-000000000001', 'Sec 2 Math Tues',  'Mathematics', 'Sec 2', 'Tuesday',   '19:00', 90),
    ('10000000-0000-0000-0000-000000000002', 'Sec 3 English Thu', 'English',     'Sec 3', 'Thursday',  '18:00', 90);


-- ── Assign tutor to both classes ─────────────────────────────
INSERT INTO class_tutor_assignments (class_id, tutor_id) VALUES
    ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002'),
    ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000002');


-- ── Students ─────────────────────────────────────────────────
INSERT INTO students (id, full_name, school, year_of_study) VALUES
    ('20000000-0000-0000-0000-000000000001', 'Alice Tan',   'Riverside Secondary', 'Sec 2'),
    ('20000000-0000-0000-0000-000000000002', 'Ben Lim',     'Riverside Secondary', 'Sec 2'),
    ('20000000-0000-0000-0000-000000000003', 'Chloe Wong',  'Riverside Secondary', 'Sec 2'),
    ('20000000-0000-0000-0000-000000000004', 'David Ng',    'Lakeside Secondary',  'Sec 3'),
    ('20000000-0000-0000-0000-000000000005', 'Emma Koh',    'Lakeside Secondary',  'Sec 3');


-- ── Parent ↔ Student Link ─────────────────────────────────────
INSERT INTO parent_student_links (parent_id, student_id) VALUES
    ('00000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000001');


-- ── Enrollments ───────────────────────────────────────────────
INSERT INTO enrollments (student_id, class_id) VALUES
    ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001'),
    ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001'),
    ('20000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000001'),
    ('20000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000002'),
    ('20000000-0000-0000-0000-000000000005', '10000000-0000-0000-0000-000000000002');


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
