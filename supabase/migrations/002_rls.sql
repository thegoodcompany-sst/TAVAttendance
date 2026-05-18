-- ============================================================
-- TAVA Attendance Platform — Row Level Security
-- ============================================================
-- Role hierarchy:
--   admin  → full access to everything
--   tutor  → their classes and students only
--   parent → their own children only
-- ============================================================

-- ── Helper functions ─────────────────────────────────────────

CREATE OR REPLACE FUNCTION get_my_role()
RETURNS TEXT LANGUAGE SQL SECURITY DEFINER STABLE AS $$
    SELECT role FROM profiles WHERE id = auth.uid()
$$;

CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN LANGUAGE SQL SECURITY DEFINER STABLE AS $$
    SELECT get_my_role() = 'admin'
$$;

CREATE OR REPLACE FUNCTION is_tutor()
RETURNS BOOLEAN LANGUAGE SQL SECURITY DEFINER STABLE AS $$
    SELECT get_my_role() = 'tutor'
$$;

CREATE OR REPLACE FUNCTION is_parent()
RETURNS BOOLEAN LANGUAGE SQL SECURITY DEFINER STABLE AS $$
    SELECT get_my_role() = 'parent'
$$;

-- Returns true if the current user is a tutor assigned to the given class.
CREATE OR REPLACE FUNCTION tutor_owns_class(p_class_id UUID)
RETURNS BOOLEAN LANGUAGE SQL SECURITY DEFINER STABLE AS $$
    SELECT EXISTS (
        SELECT 1 FROM class_tutor_assignments
        WHERE class_id = p_class_id
          AND tutor_id = auth.uid()
          AND (assigned_until IS NULL OR assigned_until >= CURRENT_DATE)
    )
$$;

-- Returns true if the current user is a parent of the given student.
CREATE OR REPLACE FUNCTION parent_owns_student(p_student_id UUID)
RETURNS BOOLEAN LANGUAGE SQL SECURITY DEFINER STABLE AS $$
    SELECT EXISTS (
        SELECT 1 FROM parent_student_links
        WHERE parent_id  = auth.uid()
          AND student_id = p_student_id
    )
$$;


-- ── profiles ─────────────────────────────────────────────────
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "profiles: any auth user can read"
    ON profiles FOR SELECT
    TO authenticated
    USING (TRUE);

CREATE POLICY "profiles: user can update own"
    ON profiles FOR UPDATE
    TO authenticated
    USING (id = auth.uid())
    WITH CHECK (id = auth.uid());

CREATE POLICY "profiles: admin can update any"
    ON profiles FOR UPDATE
    TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

-- Inserts handled by trigger handle_new_user (SECURITY DEFINER).


-- ── students ─────────────────────────────────────────────────
ALTER TABLE students ENABLE ROW LEVEL SECURITY;

CREATE POLICY "students: admin full access"
    ON students FOR ALL
    TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

CREATE POLICY "students: tutor can read enrolled students"
    ON students FOR SELECT
    TO authenticated
    USING (
        is_tutor() AND EXISTS (
            SELECT 1
            FROM enrollments e
            JOIN class_tutor_assignments cta ON cta.class_id = e.class_id
            WHERE e.student_id = students.id
              AND e.is_active   = TRUE
              AND cta.tutor_id  = auth.uid()
              AND (cta.assigned_until IS NULL OR cta.assigned_until >= CURRENT_DATE)
        )
    );

CREATE POLICY "students: parent can read own children"
    ON students FOR SELECT
    TO authenticated
    USING (
        is_parent() AND parent_owns_student(students.id)
    );


-- ── parent_student_links ──────────────────────────────────────
ALTER TABLE parent_student_links ENABLE ROW LEVEL SECURITY;

CREATE POLICY "parent_student_links: admin full access"
    ON parent_student_links FOR ALL
    TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

CREATE POLICY "parent_student_links: parent reads own"
    ON parent_student_links FOR SELECT
    TO authenticated
    USING (parent_id = auth.uid());


-- ── classes ───────────────────────────────────────────────────
ALTER TABLE classes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "classes: admin full access"
    ON classes FOR ALL
    TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

CREATE POLICY "classes: tutor reads assigned classes"
    ON classes FOR SELECT
    TO authenticated
    USING (
        is_tutor() AND tutor_owns_class(classes.id)
    );

CREATE POLICY "classes: parent reads children's classes"
    ON classes FOR SELECT
    TO authenticated
    USING (
        is_parent() AND EXISTS (
            SELECT 1
            FROM enrollments e
            JOIN parent_student_links psl ON psl.student_id = e.student_id
            WHERE e.class_id   = classes.id
              AND e.is_active   = TRUE
              AND psl.parent_id = auth.uid()
        )
    );


-- ── class_tutor_assignments ───────────────────────────────────
ALTER TABLE class_tutor_assignments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "class_tutor_assignments: admin full access"
    ON class_tutor_assignments FOR ALL
    TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

CREATE POLICY "class_tutor_assignments: tutor reads own"
    ON class_tutor_assignments FOR SELECT
    TO authenticated
    USING (is_tutor() AND tutor_id = auth.uid());


-- ── enrollments ───────────────────────────────────────────────
ALTER TABLE enrollments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "enrollments: admin full access"
    ON enrollments FOR ALL
    TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

CREATE POLICY "enrollments: tutor reads for their classes"
    ON enrollments FOR SELECT
    TO authenticated
    USING (
        is_tutor() AND tutor_owns_class(enrollments.class_id)
    );

CREATE POLICY "enrollments: parent reads own children"
    ON enrollments FOR SELECT
    TO authenticated
    USING (
        is_parent() AND parent_owns_student(enrollments.student_id)
    );


-- ── sessions ─────────────────────────────────────────────────
ALTER TABLE sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "sessions: admin full access"
    ON sessions FOR ALL
    TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

CREATE POLICY "sessions: tutor reads/writes their class sessions"
    ON sessions FOR ALL
    TO authenticated
    USING (
        is_tutor() AND tutor_owns_class(sessions.class_id)
    )
    WITH CHECK (
        is_tutor() AND tutor_owns_class(sessions.class_id)
    );

CREATE POLICY "sessions: parent reads children's sessions"
    ON sessions FOR SELECT
    TO authenticated
    USING (
        is_parent() AND EXISTS (
            SELECT 1
            FROM enrollments e
            JOIN parent_student_links psl ON psl.student_id = e.student_id
            WHERE e.class_id   = sessions.class_id
              AND e.is_active   = TRUE
              AND psl.parent_id = auth.uid()
        )
    );


-- ── attendance_records ────────────────────────────────────────
ALTER TABLE attendance_records ENABLE ROW LEVEL SECURITY;

CREATE POLICY "attendance_records: admin full access"
    ON attendance_records FOR ALL
    TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

CREATE POLICY "attendance_records: tutor reads/writes their sessions"
    ON attendance_records FOR ALL
    TO authenticated
    USING (
        is_tutor() AND EXISTS (
            SELECT 1 FROM sessions s
            WHERE s.id = attendance_records.session_id
              AND tutor_owns_class(s.class_id)
        )
    )
    WITH CHECK (
        is_tutor() AND EXISTS (
            SELECT 1 FROM sessions s
            WHERE s.id = attendance_records.session_id
              AND tutor_owns_class(s.class_id)
        )
    );

CREATE POLICY "attendance_records: parent reads own children"
    ON attendance_records FOR SELECT
    TO authenticated
    USING (
        is_parent() AND parent_owns_student(attendance_records.student_id)
    );


-- ── audit_log ─────────────────────────────────────────────────
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "audit_log: admin read only"
    ON audit_log FOR SELECT
    TO authenticated
    USING (is_admin());

-- No INSERT/UPDATE/DELETE policies — only trigger functions (SECURITY DEFINER) write to this table.


-- ── Phase 2/3 stubs: open to admins only for now ─────────────
ALTER TABLE result_slips        ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages            ENABLE ROW LEVEL SECURITY;
ALTER TABLE awards              ENABLE ROW LEVEL SECURITY;
ALTER TABLE dismissals          ENABLE ROW LEVEL SECURITY;
ALTER TABLE food_polls          ENABLE ROW LEVEL SECURITY;
ALTER TABLE food_poll_responses ENABLE ROW LEVEL SECURITY;

CREATE POLICY "result_slips: admin only"        ON result_slips        FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY "messages: admin only"            ON messages            FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY "awards: admin only"              ON awards              FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY "dismissals: admin only"          ON dismissals          FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY "food_polls: admin only"          ON food_polls          FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY "food_poll_responses: admin only" ON food_poll_responses FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());
