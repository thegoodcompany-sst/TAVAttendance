-- Migration 047: make the student identifier binding unambiguous inside the
-- SQL security-definer predicate.

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
        WHERE e.student_id = $1
          AND (
                (
                    e.is_active
                    AND EXISTS (
                        SELECT 1 FROM class_tutor_assignments cta
                        WHERE cta.class_id = e.class_id
                          AND cta.tutor_id = auth.uid()
                          AND cta.assigned_from <=
                              (NOW() AT TIME ZONE 'Asia/Singapore')::DATE
                          AND (cta.assigned_until IS NULL OR cta.assigned_until >=
                              (NOW() AT TIME ZONE 'Asia/Singapore')::DATE)
                    )
                )
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

DO $$
BEGIN
    ASSERT POSITION(
        'e.student_id = $1'
        IN LOWER(pg_get_functiondef(
            'public.tutor_can_read_student_photo(uuid)'::REGPROCEDURE
        ))
    ) > 0, 'student-photo predicate argument is not positionally bound';
END
$$;

COMMIT;
