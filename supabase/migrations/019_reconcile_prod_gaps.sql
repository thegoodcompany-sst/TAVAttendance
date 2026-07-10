-- 019_reconcile_prod_gaps.sql
--
-- Triage of the drift detector's first full `supabase db diff` run (2026-07-10).
-- The prod-vs-files diff reduced to:
--
--   REAL GAPS (010 was never applied to prod as a file; the 2026-07-09
--   backfills missed these):
--     - audit triggers audit_profiles / audit_classes missing in prod
--     - four perf indexes from 010 missing in prod
--
--   FORMATTING-ONLY (verified semantically identical; the out-of-band applies
--   stripped comments/reflowed whitespace, and pg_proc stores literal text):
--     - _anonymise_student, anonymise_student, audit_trigger_func,
--       class_punctuality, export_student_personal_data,
--       purge_expired_personal_data, and the attendance_summary view
--
-- This migration creates the missing objects and re-pins the canonical text of
-- the formatting-drifted ones (prod's pg_get_functiondef output), so replaying
-- the chain converges byte-for-byte with prod and the diff goes quiet.

-- ── Real gap 1: audit triggers (from 010) ─────────────────────────────────
DROP TRIGGER IF EXISTS audit_profiles ON profiles;
CREATE TRIGGER audit_profiles
    AFTER INSERT OR UPDATE OR DELETE ON profiles
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_func();

DROP TRIGGER IF EXISTS audit_classes ON classes;
CREATE TRIGGER audit_classes
    AFTER INSERT OR UPDATE OR DELETE ON classes
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_func();

-- ── Real gap 2: perf indexes (from 010) ───────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_sessions_session_date
    ON sessions (session_date);
CREATE INDEX IF NOT EXISTS idx_attendance_records_student_id
    ON attendance_records (student_id);
CREATE INDEX IF NOT EXISTS idx_enrollments_class_id
    ON enrollments (class_id);
CREATE INDEX IF NOT EXISTS idx_enrollments_class_id_active
    ON enrollments (class_id)
    WHERE is_active = TRUE;

-- ── Formatting re-pins (semantic no-ops; canonical text = prod's) ─────────
CREATE OR REPLACE FUNCTION public._anonymise_student(p_student_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    PERFORM set_config('app.suppress_audit', 'on', true);
    UPDATE students SET full_name='Redacted Student', date_of_birth=NULL, school=NULL, year_of_study=NULL, notes=NULL, is_active=FALSE WHERE id = p_student_id;
    UPDATE attendance_records SET notes = NULL WHERE student_id = p_student_id;
    DELETE FROM result_slips        WHERE student_id = p_student_id;
    DELETE FROM consent_records      WHERE student_id = p_student_id;
    DELETE FROM correction_requests  WHERE student_id = p_student_id;
    UPDATE audit_log SET old_data = NULL, new_data = NULL WHERE table_name = 'students' AND record_id = p_student_id;
    DELETE FROM audit_log WHERE (old_data->>'student_id' = p_student_id::text OR new_data->>'student_id' = p_student_id::text);
END;
$function$;

CREATE OR REPLACE FUNCTION public.anonymise_student(p_student_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NOT is_admin() THEN RAISE EXCEPTION 'not authorized'; END IF;
    PERFORM _anonymise_student(p_student_id);
    INSERT INTO data_disclosures (student_id, disclosed_to, disclosure_type, disclosed_by, detail)
    VALUES (p_student_id, 'Internal', 'other', auth.uid(), jsonb_build_object('action', 'anonymise_student'));
END;
$function$;

CREATE OR REPLACE FUNCTION public.audit_trigger_func()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF current_setting('app.suppress_audit', true) = 'on' THEN
        RETURN CASE TG_OP WHEN 'DELETE' THEN OLD ELSE NEW END;
    END IF;
    IF TG_OP = 'INSERT' THEN
        INSERT INTO audit_log (table_name, record_id, action, new_data, changed_by)
        VALUES (TG_TABLE_NAME, NEW.id, 'INSERT', to_jsonb(NEW), auth.uid());
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit_log (table_name, record_id, action, old_data, new_data, changed_by)
        VALUES (TG_TABLE_NAME, NEW.id, 'UPDATE', to_jsonb(OLD), to_jsonb(NEW), auth.uid());
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO audit_log (table_name, record_id, action, old_data, changed_by)
        VALUES (TG_TABLE_NAME, OLD.id, 'DELETE', to_jsonb(OLD), auth.uid());
        RETURN OLD;
    END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.class_punctuality(p_class_id uuid, p_from date, p_to date)
 RETURNS TABLE(present_count bigint, late_count bigint, absent_count bigint, excused_count bigint, total_count bigint, on_time_rate numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NOT (is_admin() OR tutor_owns_class(p_class_id)) THEN
        RAISE EXCEPTION 'not authorized';
    END IF;

    RETURN QUERY
    SELECT
        COUNT(*) FILTER (WHERE ar.status = 'present')  AS present_count,
        COUNT(*) FILTER (WHERE ar.status = 'late')     AS late_count,
        COUNT(*) FILTER (WHERE ar.status = 'absent')   AS absent_count,
        COUNT(*) FILTER (WHERE ar.status = 'excused')  AS excused_count,
        COUNT(*)                                       AS total_count,
        CASE WHEN COUNT(*) = 0 THEN NULL
             ELSE ROUND(
                 COUNT(*) FILTER (WHERE ar.status = 'present')::NUMERIC / COUNT(*),
                 4
             )
        END                                            AS on_time_rate
    FROM attendance_records ar
    JOIN sessions s ON s.id = ar.session_id
    WHERE s.class_id = p_class_id
      AND s.session_date BETWEEN p_from AND p_to;
END;
$function$;

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
        'student',      (SELECT to_jsonb(s) FROM students s WHERE s.id = p_student_id),
        'enrollments',  (SELECT COALESCE(jsonb_agg(to_jsonb(e)), '[]') FROM enrollments e WHERE e.student_id = p_student_id),
        'attendance',   (SELECT COALESCE(jsonb_agg(to_jsonb(a)), '[]') FROM attendance_records a WHERE a.student_id = p_student_id),
        'parents',      (SELECT COALESCE(jsonb_agg(jsonb_build_object('parent', to_jsonb(p), 'link', to_jsonb(l))), '[]') FROM parent_student_links l JOIN profiles p ON p.id = l.parent_id WHERE l.student_id = p_student_id),
        'consent',      (SELECT COALESCE(jsonb_agg(to_jsonb(c)), '[]') FROM consent_records c WHERE c.student_id = p_student_id),
        'result_slips', (SELECT COALESCE(jsonb_agg(to_jsonb(r)), '[]') FROM result_slips r WHERE r.student_id = p_student_id),
        'dismissals',   (SELECT COALESCE(jsonb_agg(to_jsonb(d)), '[]') FROM dismissals d WHERE d.student_id = p_student_id),
        'awards',       (SELECT COALESCE(jsonb_agg(to_jsonb(w)), '[]') FROM awards w WHERE w.student_id = p_student_id),
        'generated_at', NOW()
    ) INTO result;
    INSERT INTO data_disclosures (student_id, disclosed_to, disclosure_type, disclosed_by, detail)
    VALUES (p_student_id, 'Subject access request', 'subject_access_export', auth.uid(), jsonb_build_object('via', 'export_student_personal_data'));
    RETURN result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.purge_expired_personal_data()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE r RECORD; n_anon INT := 0; n_audit INT := 0;
BEGIN
    FOR r IN
        SELECT s.id FROM students s
        WHERE s.is_active = FALSE AND s.full_name <> 'Redacted Student'
          AND NOT EXISTS (SELECT 1 FROM enrollments e WHERE e.student_id = s.id AND e.is_active = TRUE)
          AND COALESCE(s.deactivated_at, (SELECT MAX(e2.unenrolled_at) FROM enrollments e2 WHERE e2.student_id = s.id)) < NOW() - INTERVAL '7 years'
    LOOP
        PERFORM _anonymise_student(r.id);
        n_anon := n_anon + 1;
    END LOOP;
    DELETE FROM audit_log WHERE changed_at < NOW() - INTERVAL '7 years';
    GET DIAGNOSTICS n_audit = ROW_COUNT;
    RETURN jsonb_build_object('anonymised', n_anon, 'audit_purged', n_audit);
END;
$function$;

-- View re-pin. CREATE OR REPLACE VIEW resets options — security_invoker MUST
-- be restated every time this view is touched (the 015 regression).
CREATE OR REPLACE VIEW attendance_summary
WITH (security_invoker = true)
AS
SELECT s.student_id,
    st.full_name AS student_name,
    se.class_id,
    c.name AS class_name,
    count(*) AS total_sessions,
    count(*) FILTER (WHERE s.status = 'present') AS present_count,
    count(*) FILTER (WHERE s.status = 'late') AS late_count,
    count(*) FILTER (WHERE s.status = 'absent') AS absent_count,
    count(*) FILTER (WHERE s.status = 'excused') AS excused_count,
    round(100.0 * count(*) FILTER (WHERE s.status IN ('present','late','excused')) / NULLIF(count(*), 0), 1) AS attendance_pct
FROM attendance_records s
JOIN students st ON st.id = s.student_id
JOIN sessions se ON se.id = s.session_id
JOIN classes c ON c.id = se.class_id
WHERE st.is_active = TRUE
  AND c.is_active = TRUE
  AND c.is_study_space = FALSE
GROUP BY s.student_id, st.full_name, se.class_id, c.name;

-- Verification (DEVOPS-02): abort if this migration did not fully apply.
DO $$
BEGIN
    ASSERT (SELECT count(*) = 2 FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
            WHERE NOT t.tgisinternal AND tgname IN ('audit_profiles', 'audit_classes')),
           'audit triggers missing after 019';
    ASSERT (SELECT count(*) = 4 FROM pg_indexes WHERE schemaname = 'public'
            AND indexname IN ('idx_sessions_session_date', 'idx_attendance_records_student_id',
                              'idx_enrollments_class_id', 'idx_enrollments_class_id_active')),
           'perf indexes missing after 019';
    ASSERT (SELECT coalesce('security_invoker=true' = ANY (c.reloptions), false)
            FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'public' AND c.relname = 'attendance_summary'),
           'attendance_summary lost security_invoker';
END $$;

NOTIFY pgrst, 'reload schema';
