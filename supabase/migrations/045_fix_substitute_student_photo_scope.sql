-- Migration 045: evaluate tutor/substitute photo scope behind a data-free
-- security-definer predicate. Direct enrollment RLS otherwise hides the row
-- that a valid substitute needs the Storage policy to evaluate.

BEGIN;

CREATE FUNCTION public.tutor_can_read_student_photo(p_student_id UUID)
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
                    SELECT 1
                    FROM sessions s
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

REVOKE EXECUTE ON FUNCTION public.tutor_can_read_student_photo(UUID)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tutor_can_read_student_photo(UUID)
    TO authenticated, service_role;

DROP POLICY IF EXISTS "student-photos: tutor read" ON storage.objects;
CREATE POLICY "student-photos: tutor read"
    ON storage.objects FOR SELECT TO authenticated
    USING (
        bucket_id = 'student-photos'
        AND is_feature_enabled('student_photos')
        AND tutor_can_read_student_photo(canonical_storage_student_id(name))
    );

DO $$
DECLARE
    v_scope TEXT := LOWER(pg_get_functiondef(
        'public.tutor_can_read_student_photo(uuid)'::REGPROCEDURE
    ));
BEGIN
    ASSERT POSITION('security definer' IN v_scope) > 0
       AND POSITION('tutor_owns_class' IN v_scope) > 0
       AND POSITION('substitute_covers_session' IN v_scope) > 0
       AND POSITION('e.enrolled_at' IN v_scope) > 0
       AND POSITION('e.unenrolled_at' IN v_scope) > 0,
        'student-photo scope lost tutor/substitute enrollment boundaries';
    ASSERT (
        SELECT LOWER(qual) LIKE '%tutor_can_read_student_photo%'
           AND LOWER(qual) LIKE '%canonical_storage_student_id%'
        FROM pg_policies
        WHERE schemaname = 'storage'
          AND tablename = 'objects'
          AND policyname = 'student-photos: tutor read'
    ), 'student-photo Storage policy does not use the bounded predicate';
END
$$;

COMMIT;
