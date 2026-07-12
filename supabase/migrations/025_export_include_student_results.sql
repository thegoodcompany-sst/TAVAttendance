-- 025: subject-access export must include student_results (added in 023, after the
-- export function shipped in 011) — found by the 2026-07-12 PDPA runtime QA pass.
CREATE OR REPLACE FUNCTION public.export_student_personal_data(p_student_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE result JSONB;
BEGIN
    IF NOT is_admin() THEN RAISE EXCEPTION 'not authorized'; END IF;
    SELECT jsonb_build_object(
        'student',         (SELECT to_jsonb(s) FROM students s WHERE s.id = p_student_id),
        'enrollments',     (SELECT COALESCE(jsonb_agg(to_jsonb(e)), '[]') FROM enrollments e WHERE e.student_id = p_student_id),
        'attendance',      (SELECT COALESCE(jsonb_agg(to_jsonb(a)), '[]') FROM attendance_records a WHERE a.student_id = p_student_id),
        'parents',         (SELECT COALESCE(jsonb_agg(jsonb_build_object('parent', to_jsonb(p), 'link', to_jsonb(l))), '[]') FROM parent_student_links l JOIN profiles p ON p.id = l.parent_id WHERE l.student_id = p_student_id),
        'consent',         (SELECT COALESCE(jsonb_agg(to_jsonb(c)), '[]') FROM consent_records c WHERE c.student_id = p_student_id),
        'result_slips',    (SELECT COALESCE(jsonb_agg(to_jsonb(r)), '[]') FROM result_slips r WHERE r.student_id = p_student_id),
        'student_results', (SELECT COALESCE(jsonb_agg(to_jsonb(sr)), '[]') FROM student_results sr WHERE sr.student_id = p_student_id),
        'dismissals',      (SELECT COALESCE(jsonb_agg(to_jsonb(d)), '[]') FROM dismissals d WHERE d.student_id = p_student_id),
        'awards',          (SELECT COALESCE(jsonb_agg(to_jsonb(w)), '[]') FROM awards w WHERE w.student_id = p_student_id),
        'generated_at',    NOW()
    ) INTO result;
    INSERT INTO data_disclosures (student_id, disclosed_to, disclosure_type, disclosed_by, detail)
    VALUES (p_student_id, 'Subject access request', 'subject_access_export', auth.uid(), jsonb_build_object('via', 'export_student_personal_data'));
    RETURN result;
END;
$function$;

NOTIFY pgrst, 'reload schema';

DO $$
BEGIN
    ASSERT (SELECT prosrc LIKE '%student_results%'
            FROM pg_proc WHERE oid = 'export_student_personal_data(uuid)'::regprocedure),
           'export_student_personal_data does not include student_results';
END $$;
