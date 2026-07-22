-- down/047_bind_student_photo_scope_argument.sql — reverse of 047.

BEGIN;

CREATE OR REPLACE FUNCTION public.tutor_can_read_student_photo(p_student_id UUID)
RETURNS BOOLEAN
LANGUAGE SQL
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1 FROM profiles p
        WHERE p.id = auth.uid() AND p.role = 'tutor'
    ) AND EXISTS (
        SELECT 1
        FROM enrollments e
        WHERE e.student_id = p_student_id
          AND (
                (e.is_active AND EXISTS (
                    SELECT 1 FROM class_tutor_assignments cta
                    WHERE cta.class_id = e.class_id
                      AND cta.tutor_id = auth.uid()
                      AND cta.assigned_from <=
                          (NOW() AT TIME ZONE 'Asia/Singapore')::DATE
                      AND (cta.assigned_until IS NULL OR cta.assigned_until >=
                          (NOW() AT TIME ZONE 'Asia/Singapore')::DATE)
                ))
                OR EXISTS (
                    SELECT 1 FROM sessions s
                    WHERE s.class_id = e.class_id
                      AND s.sub_tutor_id = auth.uid()
                      AND s.session_date BETWEEN
                          (NOW() AT TIME ZONE 'Asia/Singapore')::DATE - 7
                          AND (NOW() AT TIME ZONE 'Asia/Singapore')::DATE
                      AND (e.enrolled_at AT TIME ZONE 'Asia/Singapore')::DATE
                          <= s.session_date
                      AND (e.unenrolled_at IS NULL OR
                          (e.unenrolled_at AT TIME ZONE 'Asia/Singapore')::DATE
                          >= s.session_date)
                )
              )
    )
$$;

COMMIT;
