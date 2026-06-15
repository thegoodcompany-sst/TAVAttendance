-- ============================================================
-- 011_pdpa_compliance.sql
-- Singapore PDPA 2012 remediation — shared backend contract.
-- See PDPA_COMPLIANCE.md (findings) and docs/pdpa/ (governance docs).
-- Applied: 2026-06-15
--
-- Obligations addressed at the DB layer:
--   N1   policy_documents (privacy notice storage + versioning)
--   C1/C2 consent_records ledger + current_consent view
--   P1   NRIC/sensitive-data guard on free-text notes
--   A1   correction_requests
--   A2/A3 export_student_personal_data() + data_disclosures log
--   R1/R2 retention: unenrolled_at/deactivated_at stamping, anonymise/erase,
--         purge_expired_personal_data() (pg_cron), audit-log scrub + purge
--   PR1  result-slips private bucket + scoped storage RLS
--   PR3  rate_limit_events (backs the invite rate limiter in web)
--   PR4  parent-read-own RLS baseline for Phase 2/3 tables
--
-- Conventions follow 009_security_hardening.sql: SECURITY DEFINER functions
-- pin search_path; internal helpers are revoked from anon/PUBLIC/authenticated;
-- admin-facing RPCs are granted to authenticated and guard with is_admin().
-- ============================================================


-- ════════════════════════════════════════════════════════════════
-- audit_trigger_func — add a suppression flag
-- ════════════════════════════════════════════════════════════════
-- Lets anonymise_student()/erase_student() mutate or delete a student's
-- rows without re-writing their PII into audit_log. Body otherwise identical
-- to 003_functions_triggers.sql:10-27.
CREATE OR REPLACE FUNCTION audit_trigger_func()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    -- Skip auditing inside trusted erasure/anonymisation transactions.
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
$$;


-- ════════════════════════════════════════════════════════════════
-- N1 — policy_documents (privacy notice, retention schedule, breach plan)
-- ════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS policy_documents (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    doc_type     TEXT NOT NULL CHECK (doc_type IN
                   ('data_protection_notice','retention_schedule','breach_plan')),
    version      TEXT NOT NULL,
    title        TEXT NOT NULL,
    body         TEXT NOT NULL,
    is_current   BOOLEAN NOT NULL DEFAULT TRUE,
    published_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (doc_type, version)
);

ALTER TABLE policy_documents ENABLE ROW LEVEL SECURITY;

CREATE POLICY "policy_documents: auth read"
    ON policy_documents FOR SELECT TO authenticated USING (TRUE);
CREATE POLICY "policy_documents: admin write"
    ON policy_documents FOR ALL TO authenticated
    USING (is_admin()) WITH CHECK (is_admin());

-- Seed the current Data Protection Notice (v1.0). Full text lives in
-- docs/pdpa/DATA_PROTECTION_NOTICE.md; this is the in-app summary the
-- apps display. Replace after DPO/legal sign-off (see HUMANS.md).
INSERT INTO policy_documents (doc_type, version, title, body)
VALUES (
  'data_protection_notice',
  '1.0',
  'TAVA Attendance — Data Protection Notice',
  E'TAVA (the tuition centre) collects and uses personal data of students and their parents/guardians to administer tuition: enrolment, attendance, results, dismissals and centre communications.\n\nFor students who are minors, we rely on consent given by a parent or legal guardian.\n\nWe retain personal data for as long as necessary for these purposes and to meet legal record-keeping obligations (up to 7 years after a student leaves), after which it is anonymised or erased.\n\nYou may request access to, or correction of, the personal data we hold, or withdraw consent, by contacting our Data Protection Officer (see the centre''s published DPO contact).\n\nData is stored in Singapore (Supabase, ap-southeast-1) and protected with encryption in transit and at rest.'
)
ON CONFLICT (doc_type, version) DO NOTHING;


-- ════════════════════════════════════════════════════════════════
-- C1/C2 — consent_records ledger
-- ════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS consent_records (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id     UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    consent_type   TEXT NOT NULL DEFAULT 'data_collection'
                     CHECK (consent_type IN
                       ('data_collection','result_slips','messaging','photos')),
    status         TEXT NOT NULL CHECK (status IN ('granted','withdrawn')),
    method         TEXT NOT NULL CHECK (method IN ('admin_attestation','parent_in_app')),
    notice_version TEXT,
    parent_id      UUID REFERENCES auth.users(id),   -- future: in-app parent consent
    granted_by     UUID REFERENCES auth.users(id),   -- admin who attested
    source_note    TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_consent_records_student
    ON consent_records (student_id, consent_type, created_at DESC);

ALTER TABLE consent_records ENABLE ROW LEVEL SECURITY;

CREATE POLICY "consent_records: admin full"
    ON consent_records FOR ALL TO authenticated
    USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY "consent_records: parent reads own child"
    ON consent_records FOR SELECT TO authenticated
    USING (is_parent() AND parent_owns_student(student_id));

-- Current consent = most recent row per (student, consent_type).
CREATE OR REPLACE VIEW current_consent WITH (security_invoker = true) AS
SELECT DISTINCT ON (student_id, consent_type)
       student_id, consent_type, status, method, notice_version,
       granted_by, parent_id, created_at
FROM consent_records
ORDER BY student_id, consent_type, created_at DESC;


-- ════════════════════════════════════════════════════════════════
-- A1 — correction_requests
-- ════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS correction_requests (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id      UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    requested_by    UUID REFERENCES auth.users(id),
    field_name      TEXT NOT NULL,
    current_value   TEXT,
    requested_value TEXT,
    status          TEXT NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending','applied','rejected')),
    reviewed_by     UUID REFERENCES auth.users(id),
    reviewed_at     TIMESTAMPTZ,
    review_note     TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_correction_requests_status
    ON correction_requests (status, created_at DESC);

ALTER TABLE correction_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "correction_requests: admin full"
    ON correction_requests FOR ALL TO authenticated
    USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY "correction_requests: parent reads own child"
    ON correction_requests FOR SELECT TO authenticated
    USING (is_parent() AND parent_owns_student(student_id));
CREATE POLICY "correction_requests: parent creates own child"
    ON correction_requests FOR INSERT TO authenticated
    WITH CHECK (is_parent() AND parent_owns_student(student_id)
                AND requested_by = auth.uid());


-- ════════════════════════════════════════════════════════════════
-- A2/A3 — data_disclosures log + subject-access export
-- ════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS data_disclosures (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id      UUID REFERENCES students(id) ON DELETE SET NULL,
    disclosed_to    TEXT,
    disclosure_type TEXT NOT NULL CHECK (disclosure_type IN
                      ('subject_access_export','csv_export','correction_response','other')),
    disclosed_by    UUID REFERENCES auth.users(id),
    disclosed_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    detail          JSONB
);
CREATE INDEX IF NOT EXISTS idx_data_disclosures_student
    ON data_disclosures (student_id, disclosed_at DESC);

ALTER TABLE data_disclosures ENABLE ROW LEVEL SECURITY;
CREATE POLICY "data_disclosures: admin only"
    ON data_disclosures FOR ALL TO authenticated
    USING (is_admin()) WITH CHECK (is_admin());

-- Returns one JSONB bundle of everything held about a student, and logs the
-- disclosure. Admin-guarded.
CREATE OR REPLACE FUNCTION export_student_personal_data(p_student_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE result JSONB;
BEGIN
    IF NOT is_admin() THEN RAISE EXCEPTION 'not authorized'; END IF;

    SELECT jsonb_build_object(
        'student',      (SELECT to_jsonb(s) FROM students s WHERE s.id = p_student_id),
        'enrollments',  (SELECT COALESCE(jsonb_agg(to_jsonb(e)), '[]') FROM enrollments e WHERE e.student_id = p_student_id),
        'attendance',   (SELECT COALESCE(jsonb_agg(to_jsonb(a)), '[]') FROM attendance_records a WHERE a.student_id = p_student_id),
        'parents',      (SELECT COALESCE(jsonb_agg(jsonb_build_object('parent', to_jsonb(p), 'link', to_jsonb(l))), '[]')
                         FROM parent_student_links l JOIN profiles p ON p.id = l.parent_id WHERE l.student_id = p_student_id),
        'consent',      (SELECT COALESCE(jsonb_agg(to_jsonb(c)), '[]') FROM consent_records c WHERE c.student_id = p_student_id),
        'result_slips', (SELECT COALESCE(jsonb_agg(to_jsonb(r)), '[]') FROM result_slips r WHERE r.student_id = p_student_id),
        'dismissals',   (SELECT COALESCE(jsonb_agg(to_jsonb(d)), '[]') FROM dismissals d WHERE d.student_id = p_student_id),
        'awards',       (SELECT COALESCE(jsonb_agg(to_jsonb(w)), '[]') FROM awards w WHERE w.student_id = p_student_id),
        'generated_at', NOW()
    ) INTO result;

    INSERT INTO data_disclosures (student_id, disclosed_to, disclosure_type, disclosed_by, detail)
    VALUES (p_student_id, 'Subject access request', 'subject_access_export', auth.uid(),
            jsonb_build_object('via', 'export_student_personal_data'));

    RETURN result;
END;
$$;
GRANT EXECUTE ON FUNCTION export_student_personal_data(UUID) TO authenticated;
REVOKE EXECUTE ON FUNCTION export_student_personal_data(UUID) FROM PUBLIC, anon;


-- ════════════════════════════════════════════════════════════════
-- P1 — reject NRIC/FIN in free-text notes
-- ════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION reject_nric_in_notes()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
    IF COALESCE(NEW.notes, '') ~* '\m[STFGM][0-9]{7}[A-Z]\M' THEN
        RAISE EXCEPTION 'Notes appear to contain an NRIC/FIN. Do not store national identifiers (PDPA purpose limitation).';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_reject_nric_students   ON students;
DROP TRIGGER IF EXISTS trg_reject_nric_sessions   ON sessions;
DROP TRIGGER IF EXISTS trg_reject_nric_attendance ON attendance_records;
CREATE TRIGGER trg_reject_nric_students   BEFORE INSERT OR UPDATE ON students           FOR EACH ROW EXECUTE FUNCTION reject_nric_in_notes();
CREATE TRIGGER trg_reject_nric_sessions   BEFORE INSERT OR UPDATE ON sessions           FOR EACH ROW EXECUTE FUNCTION reject_nric_in_notes();
CREATE TRIGGER trg_reject_nric_attendance BEFORE INSERT OR UPDATE ON attendance_records FOR EACH ROW EXECUTE FUNCTION reject_nric_in_notes();


-- ════════════════════════════════════════════════════════════════
-- R1 — retention stamping (fixes dead columns unenrolled_at / adds deactivated_at)
-- ════════════════════════════════════════════════════════════════
ALTER TABLE students ADD COLUMN IF NOT EXISTS deactivated_at TIMESTAMPTZ;

CREATE OR REPLACE FUNCTION stamp_enrollment_unenrolled()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
    IF NEW.is_active = FALSE AND OLD.is_active = TRUE AND NEW.unenrolled_at IS NULL THEN
        NEW.unenrolled_at := NOW();
    ELSIF NEW.is_active = TRUE THEN
        NEW.unenrolled_at := NULL;
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_stamp_enrollment_unenrolled ON enrollments;
CREATE TRIGGER trg_stamp_enrollment_unenrolled
    BEFORE UPDATE ON enrollments FOR EACH ROW EXECUTE FUNCTION stamp_enrollment_unenrolled();

CREATE OR REPLACE FUNCTION stamp_student_deactivated()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
    IF NEW.is_active = FALSE AND OLD.is_active = TRUE THEN
        NEW.deactivated_at := NOW();
    ELSIF NEW.is_active = TRUE THEN
        NEW.deactivated_at := NULL;
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_stamp_student_deactivated ON students;
CREATE TRIGGER trg_stamp_student_deactivated
    BEFORE UPDATE ON students FOR EACH ROW EXECUTE FUNCTION stamp_student_deactivated();


-- ════════════════════════════════════════════════════════════════
-- R2 — anonymise / erase / audit scrub
-- ════════════════════════════════════════════════════════════════

-- Internal core (no auth check) — callable by anonymise_student() and the cron purge.
CREATE OR REPLACE FUNCTION _anonymise_student(p_student_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    PERFORM set_config('app.suppress_audit', 'on', true);  -- tx-local

    UPDATE students SET
        full_name     = 'Redacted Student',
        date_of_birth = NULL,
        school        = NULL,
        year_of_study = NULL,
        notes         = NULL,
        is_active     = FALSE
    WHERE id = p_student_id;

    -- Keep attendance rows (anonymous stats) but strip free-text PII.
    UPDATE attendance_records SET notes = NULL WHERE student_id = p_student_id;
    DELETE FROM result_slips        WHERE student_id = p_student_id;
    DELETE FROM consent_records      WHERE student_id = p_student_id;
    DELETE FROM correction_requests  WHERE student_id = p_student_id;

    -- Scrub historical audit snapshots that contain this student's PII.
    UPDATE audit_log SET old_data = NULL, new_data = NULL
        WHERE table_name = 'students' AND record_id = p_student_id;
    DELETE FROM audit_log
        WHERE (old_data->>'student_id' = p_student_id::text
            OR new_data->>'student_id' = p_student_id::text);
END;
$$;
REVOKE EXECUTE ON FUNCTION _anonymise_student(UUID) FROM PUBLIC, anon, authenticated;

-- Admin-facing wrapper.
CREATE OR REPLACE FUNCTION anonymise_student(p_student_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NOT is_admin() THEN RAISE EXCEPTION 'not authorized'; END IF;
    PERFORM _anonymise_student(p_student_id);
    INSERT INTO data_disclosures (student_id, disclosed_to, disclosure_type, disclosed_by, detail)
    VALUES (p_student_id, 'Internal', 'other', auth.uid(),
            jsonb_build_object('action', 'anonymise_student'));
END;
$$;
GRANT EXECUTE ON FUNCTION anonymise_student(UUID) TO authenticated;
REVOKE EXECUTE ON FUNCTION anonymise_student(UUID) FROM PUBLIC, anon;

-- Hard erase (right-to-erasure path). Removes all of a student's data.
CREATE OR REPLACE FUNCTION erase_student(p_student_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NOT is_admin() THEN RAISE EXCEPTION 'not authorized'; END IF;
    PERFORM set_config('app.suppress_audit', 'on', true);  -- tx-local

    -- dismissals / food_poll_responses have no ON DELETE CASCADE → remove first.
    DELETE FROM dismissals          WHERE student_id = p_student_id;
    DELETE FROM food_poll_responses WHERE student_id = p_student_id;
    DELETE FROM students            WHERE id = p_student_id;  -- cascades to the rest

    -- Purge any audit snapshots referencing this student.
    DELETE FROM audit_log
        WHERE (table_name = 'students' AND record_id = p_student_id)
           OR (old_data->>'student_id' = p_student_id::text)
           OR (new_data->>'student_id' = p_student_id::text);
END;
$$;
GRANT EXECUTE ON FUNCTION erase_student(UUID) TO authenticated;
REVOKE EXECUTE ON FUNCTION erase_student(UUID) FROM PUBLIC, anon;


-- ════════════════════════════════════════════════════════════════
-- R1/R2 — scheduled retention purge (7 years)
-- ════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION purge_expired_personal_data()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    r   RECORD;
    n_anon  INT := 0;
    n_audit INT := 0;
BEGIN
    -- Students with no active enrolment whose last unenrolment (or deactivation)
    -- was more than 7 years ago, not already anonymised.
    FOR r IN
        SELECT s.id
        FROM students s
        WHERE s.is_active = FALSE
          AND s.full_name <> 'Redacted Student'
          AND NOT EXISTS (SELECT 1 FROM enrollments e
                          WHERE e.student_id = s.id AND e.is_active = TRUE)
          AND COALESCE(
                s.deactivated_at,
                (SELECT MAX(e2.unenrolled_at) FROM enrollments e2 WHERE e2.student_id = s.id)
              ) < NOW() - INTERVAL '7 years'
    LOOP
        PERFORM _anonymise_student(r.id);
        n_anon := n_anon + 1;
    END LOOP;

    -- Audit log older than 7 years.
    DELETE FROM audit_log WHERE changed_at < NOW() - INTERVAL '7 years';
    GET DIAGNOSTICS n_audit = ROW_COUNT;

    RETURN jsonb_build_object('anonymised', n_anon, 'audit_purged', n_audit);
END;
$$;
REVOKE EXECUTE ON FUNCTION purge_expired_personal_data() FROM PUBLIC, anon, authenticated;

-- Enable pg_cron (best-effort) and schedule the daily purge.
DO $$
BEGIN
    CREATE EXTENSION IF NOT EXISTS pg_cron;
EXCEPTION WHEN OTHERS THEN
    NULL; -- not permitted via SQL on this plan; see HUMANS.md
END;
$$;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        PERFORM cron.schedule('pdpa-daily-purge', '20 18 * * *',
                              'SELECT purge_expired_personal_data();');
    END IF;
EXCEPTION WHEN OTHERS THEN
    -- pg_cron not enabled / insufficient privilege: leave for manual scheduling.
    NULL;
END;
$$;


-- ════════════════════════════════════════════════════════════════
-- PR1 — result-slips private bucket + scoped storage RLS
-- ════════════════════════════════════════════════════════════════
INSERT INTO storage.buckets (id, name, public)
VALUES ('result-slips', 'result-slips', FALSE)
ON CONFLICT (id) DO UPDATE SET public = FALSE;

DROP POLICY IF EXISTS "result-slips: admin all"   ON storage.objects;
DROP POLICY IF EXISTS "result-slips: parent read" ON storage.objects;

CREATE POLICY "result-slips: admin all"
    ON storage.objects FOR ALL TO authenticated
    USING (bucket_id = 'result-slips' AND is_admin())
    WITH CHECK (bucket_id = 'result-slips' AND is_admin());

-- Parents may read result-slip files for their own children. Path convention:
-- the first path segment is the student_id (e.g. "<student_id>/<file>").
CREATE POLICY "result-slips: parent read"
    ON storage.objects FOR SELECT TO authenticated
    USING (
        bucket_id = 'result-slips'
        AND is_parent()
        AND parent_owns_student(((storage.foldername(name))[1])::uuid)
    );


-- ════════════════════════════════════════════════════════════════
-- PR3 — rate_limit_events (backs invite rate limiter in web)
-- ════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS rate_limit_events (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_id   UUID,
    action     TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_rate_limit_events_lookup
    ON rate_limit_events (actor_id, action, created_at DESC);

-- RLS on, no policies → only service_role (used by the server action) can touch it.
ALTER TABLE rate_limit_events ENABLE ROW LEVEL SECURITY;


-- ════════════════════════════════════════════════════════════════
-- PR4 — parent-read-own baseline RLS for Phase 2/3 tables
-- ════════════════════════════════════════════════════════════════
-- Admin-only ALL policies from 002_rls.sql remain; these add scoped parent reads
-- so the features cannot over-expose when surfaced later.

CREATE POLICY "result_slips: parent reads own child"
    ON result_slips FOR SELECT TO authenticated
    USING (is_parent() AND parent_owns_student(student_id));

CREATE POLICY "dismissals: parent reads own child"
    ON dismissals FOR SELECT TO authenticated
    USING (is_parent() AND parent_owns_student(student_id));

CREATE POLICY "awards: parent reads own child"
    ON awards FOR SELECT TO authenticated
    USING (is_parent() AND parent_owns_student(student_id));

CREATE POLICY "messages: participant reads own"
    ON messages FOR SELECT TO authenticated
    USING (sender_id = auth.uid() OR recipient_id = auth.uid()
           OR (is_parent() AND student_id IS NOT NULL AND parent_owns_student(student_id)));
