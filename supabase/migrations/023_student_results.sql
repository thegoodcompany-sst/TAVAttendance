-- 023_student_results.sql
--
-- Tutor-entered subject grades: one current grade per student per subject.
-- Entered from the iOS tutor Students tab. Grade bands: PSLE AL1–AL8 for
-- primary students, O-Level A1–F9 for secondary. Subject values match the
-- result_slips convention ('Math' / 'English', see 005).

CREATE TABLE student_results (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id  UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    subject     TEXT NOT NULL CHECK (subject IN ('Math', 'English')),
    grade       TEXT NOT NULL CHECK (grade IN (
        'AL1','AL2','AL3','AL4','AL5','AL6','AL7','AL8',
        'A1','A2','B3','B4','C5','C6','D7','E8','F9')),
    updated_by  UUID REFERENCES auth.users(id),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (student_id, subject)
);

CREATE TRIGGER set_updated_at_student_results
    BEFORE UPDATE ON student_results
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE student_results ENABLE ROW LEVEL SECURITY;

CREATE POLICY "student_results: admin full access"
    ON student_results FOR ALL
    TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

-- Tutors manage grades for students enrolled in one of their assigned classes
-- (same shape as "students: tutor can read enrolled students" in 002).
-- ponytail: tutor-subject vs class-subject matching is enforced in the app UI
-- only (classes.subject is free text in prod); tighten here if that changes.
CREATE POLICY "student_results: tutor manages enrolled students"
    ON student_results FOR ALL
    TO authenticated
    USING (
        is_tutor() AND EXISTS (
            SELECT 1
            FROM enrollments e
            JOIN class_tutor_assignments cta ON cta.class_id = e.class_id
            WHERE e.student_id = student_results.student_id
              AND e.is_active   = TRUE
              AND cta.tutor_id  = auth.uid()
              AND (cta.assigned_until IS NULL OR cta.assigned_until >= CURRENT_DATE)
        )
    )
    WITH CHECK (
        is_tutor() AND EXISTS (
            SELECT 1
            FROM enrollments e
            JOIN class_tutor_assignments cta ON cta.class_id = e.class_id
            WHERE e.student_id = student_results.student_id
              AND e.is_active   = TRUE
              AND cta.tutor_id  = auth.uid()
              AND (cta.assigned_until IS NULL OR cta.assigned_until >= CURRENT_DATE)
        )
    );

-- Verification (DEVOPS-02): abort if this migration did not fully apply.
DO $$
BEGIN
    ASSERT (SELECT EXISTS (
        SELECT FROM pg_tables
        WHERE schemaname = 'public' AND tablename = 'student_results'
          AND rowsecurity = TRUE)),
        'student_results missing or RLS disabled after 023';
    ASSERT (SELECT COUNT(*) = 2 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'student_results'),
        'expected 2 policies on student_results after 023';
END $$;
