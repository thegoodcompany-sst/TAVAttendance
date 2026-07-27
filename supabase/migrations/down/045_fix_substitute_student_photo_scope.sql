-- down/045_fix_substitute_student_photo_scope.sql — reverse of 045.

BEGIN;

DROP POLICY IF EXISTS "student-photos: tutor read" ON storage.objects;
CREATE POLICY "student-photos: tutor read"
    ON storage.objects FOR SELECT TO authenticated
    USING (
        bucket_id = 'student-photos'
        AND is_feature_enabled('student_photos')
        AND is_tutor()
        AND EXISTS (
            SELECT 1
            FROM enrollments e
            WHERE e.student_id = canonical_storage_student_id(name)
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
    );

DROP FUNCTION public.tutor_can_read_student_photo(UUID);

COMMIT;
