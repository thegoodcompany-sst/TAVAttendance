-- down/046_pin_student_photo_scope_to_actor.sql — reverse of 046.

BEGIN;

CREATE OR REPLACE FUNCTION public.tutor_can_read_student_photo(p_student_id UUID)
RETURNS BOOLEAN
LANGUAGE SQL
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
    SELECT is_tutor() AND EXISTS (
        SELECT 1
        FROM enrollments e
        WHERE e.student_id = p_student_id
          AND (
                (e.is_active AND tutor_owns_class(e.class_id))
                OR EXISTS (
                    SELECT 1 FROM sessions s
                    WHERE s.class_id = e.class_id
                      AND substitute_covers_session(s.id)
                      AND (e.enrolled_at AT TIME ZONE 'Asia/Singapore')::DATE
                            <= s.session_date
                      AND (
                            e.unenrolled_at IS NULL
                            OR (e.unenrolled_at AT TIME ZONE 'Asia/Singapore')::DATE
                                >= s.session_date
                          )
                )
              )
    )
$$;

COMMIT;
