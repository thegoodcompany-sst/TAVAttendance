-- Reverse of 059_nfc_arrival_station.sql.

NOTIFY pgrst, 'reload schema';

CREATE OR REPLACE FUNCTION export_student_personal_data(p_student_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE result JSONB;
BEGIN
    IF NOT is_admin() THEN RAISE EXCEPTION 'not authorized'; END IF;
    SELECT jsonb_build_object(
        'student',         (SELECT to_jsonb(s) FROM students s WHERE s.id = p_student_id),
        'enrollments',     (SELECT COALESCE(jsonb_agg(to_jsonb(e)), '[]') FROM enrollments e WHERE e.student_id = p_student_id),
        'attendance',      (SELECT COALESCE(jsonb_agg(to_jsonb(a)), '[]')
                            FROM attendance_records a
                            JOIN sessions se ON se.id = a.session_id
                            JOIN classes c ON c.id = se.class_id
                            WHERE a.student_id = p_student_id AND c.is_study_space = FALSE),
        'parents',         (SELECT COALESCE(jsonb_agg(jsonb_build_object('parent', to_jsonb(p), 'link', to_jsonb(l))), '[]') FROM parent_student_links l JOIN profiles p ON p.id = l.parent_id WHERE l.student_id = p_student_id),
        'consent',         (SELECT COALESCE(jsonb_agg(to_jsonb(c)), '[]') FROM consent_records c WHERE c.student_id = p_student_id),
        'result_slips',    (SELECT COALESCE(jsonb_agg(to_jsonb(r)), '[]') FROM result_slips r WHERE r.student_id = p_student_id),
        'student_results', (SELECT COALESCE(jsonb_agg(to_jsonb(sr)), '[]') FROM student_results sr WHERE sr.student_id = p_student_id),
        'dismissals',      (SELECT COALESCE(jsonb_agg(to_jsonb(d)), '[]') FROM dismissals d WHERE d.student_id = p_student_id),
        'awards',          (SELECT COALESCE(jsonb_agg(to_jsonb(w)), '[]') FROM awards w WHERE w.student_id = p_student_id),
        'generated_at',    NOW()
    ) INTO result;
    INSERT INTO data_disclosures (student_id, disclosed_to, disclosure_type, disclosed_by, detail)
    VALUES (p_student_id, 'Subject access request', 'subject_access_export', auth.uid(),
            jsonb_build_object('via', 'export_student_personal_data'));
    RETURN result;
END;
$$;

DROP FUNCTION IF EXISTS public.arrival_station_tap(TEXT);
DROP FUNCTION IF EXISTS public.get_student_nfc_binding(UUID);
DROP FUNCTION IF EXISTS public.revoke_nfc_chip_for_student(UUID);
DROP FUNCTION IF EXISTS public.pair_nfc_chip(UUID, TEXT);
DROP FUNCTION IF EXISTS public.nfc_sign_in_status(TIME, TIMESTAMPTZ, TIMESTAMPTZ);
DROP FUNCTION IF EXISTS public.class_meets_on_singapore_date(TEXT, TEXT, DATE);
DROP FUNCTION IF EXISTS public.normalize_nfc_chip_uid(TEXT);
DROP FUNCTION IF EXISTS public.is_arrival_station();

DROP TABLE IF EXISTS public.nfc_tag_bindings;

UPDATE profiles SET role = 'parent' WHERE role = 'arrival_station';

ALTER TABLE profiles DROP CONSTRAINT profiles_role_check;
ALTER TABLE profiles ADD CONSTRAINT profiles_role_check
    CHECK (role IN ('admin', 'tutor', 'parent'));

DELETE FROM feature_flags WHERE key = 'nfc_sign_in';
