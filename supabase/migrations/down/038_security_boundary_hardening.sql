-- down/038_security_boundary_hardening.sql — reverse of 038.
--
-- WARNING: this emergency rollback restores the post-037 authorization model,
-- including the weaknesses fixed by 038. It cannot reconstruct child-linked
-- rows, scrubbed audit data, rotated anonymised student IDs, detached malformed
-- avatar/result-slip paths, or Storage objects already deleted while 038 was active.
-- Recover those only from a verified backup.
--
-- Security exception: the dedicated X-Notify-Secret notification protocol is
-- intentionally retained. Restoring the pre-038 Authorization/service-role
-- header would be incompatible with the deployed Edge Function and would turn
-- disclosure of one invocation credential into project-wide database access.

BEGIN;

-- Hold the durable-work/evidence tables exclusively while checking them.
-- Without the locks, an erasure, signed-upload reservation, or attendance
-- mutation could race the empty check and lose its only durable record.
DO $$
DECLARE
    v_has_rows BOOLEAN;
BEGIN
    IF to_regclass('public.student_storage_cleanup_queue') IS NOT NULL THEN
        EXECUTE 'LOCK TABLE public.student_storage_cleanup_queue IN ACCESS EXCLUSIVE MODE';
        EXECUTE 'SELECT EXISTS (SELECT 1 FROM public.student_storage_cleanup_queue)'
            INTO v_has_rows;
        IF v_has_rows THEN
            RAISE EXCEPTION
                'refusing 038 rollback: student storage cleanup queue is not empty';
        END IF;
    END IF;

    IF to_regclass('public.result_slip_upload_intents') IS NOT NULL THEN
        EXECUTE 'LOCK TABLE public.result_slip_upload_intents IN ACCESS EXCLUSIVE MODE';
        EXECUTE 'SELECT EXISTS (SELECT 1 FROM public.result_slip_upload_intents)'
            INTO v_has_rows;
        IF v_has_rows THEN
            RAISE EXCEPTION
                'refusing 038 rollback: result-slip upload intents are not empty';
        END IF;
    END IF;

    IF to_regclass('public.attendance_mutation_receipts') IS NOT NULL THEN
        EXECUTE 'LOCK TABLE public.attendance_mutation_receipts IN ACCESS EXCLUSIVE MODE';
        EXECUTE 'SELECT EXISTS (SELECT 1 FROM public.attendance_mutation_receipts)'
            INTO v_has_rows;
        IF v_has_rows THEN
            RAISE EXCEPTION
                'refusing 038 rollback: attendance mutation receipts are not empty';
        END IF;
    END IF;
END;
$$;

-- Scheduling teardown is fail-closed. Any permission error, false return, or
-- surviving duplicate job aborts the transaction before the invoker is lost.
DO $$
DECLARE
    cleanup_job RECORD;
    v_unscheduled BOOLEAN;
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        FOR cleanup_job IN
            SELECT jobid
            FROM cron.job
            WHERE jobname = 'student-storage-cleanup'
        LOOP
            SELECT cron.unschedule(cleanup_job.jobid) INTO v_unscheduled;
            IF v_unscheduled IS DISTINCT FROM TRUE THEN
                RAISE EXCEPTION
                    'could not unschedule student-storage-cleanup job %',
                    cleanup_job.jobid;
            END IF;
        END LOOP;

        IF EXISTS (
            SELECT 1 FROM cron.job
            WHERE jobname = 'student-storage-cleanup'
        ) THEN
            RAISE EXCEPTION
                'student-storage-cleanup cron job still exists after unschedule';
        END IF;
    END IF;
END;
$$;

DROP FUNCTION IF EXISTS public.invoke_student_storage_cleanup();

DROP POLICY IF EXISTS "students: direct delete denied" ON students;
DROP POLICY IF EXISTS "result_slips: direct delete denied" ON result_slips;

DROP POLICY IF EXISTS "feature_flags: superadmin writes" ON feature_flags;
CREATE POLICY "feature_flags: admin writes"
    ON feature_flags FOR ALL TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

DROP TRIGGER IF EXISTS enforce_profile_role_boundary ON profiles;
DROP FUNCTION IF EXISTS public.enforce_profile_role_boundary();
DROP FUNCTION IF EXISTS public.wipe_operational_data_secure(TEXT, UUID);
DROP FUNCTION IF EXISTS public.anonymise_student_secure(UUID, UUID);
DROP FUNCTION IF EXISTS public.erase_student_secure(UUID, UUID);
DROP FUNCTION IF EXISTS public.enqueue_student_storage_cleanup(UUID, TEXT);
DROP TABLE IF EXISTS public.student_storage_cleanup_queue;

-- Remove the signed-upload capability only after the locked empty-table guard
-- above. Drop the table policy first for compatibility with an earlier 038
-- draft that referenced has_result_slip_upload_intent().
DROP POLICY IF EXISTS "result_slips: parent uploads own child" ON result_slips;
DROP FUNCTION IF EXISTS public.finalize_result_slip_upload(
    UUID, UUID, TEXT, TEXT, TEXT, NUMERIC, NUMERIC
);
DROP FUNCTION IF EXISTS public.reserve_result_slip_upload(
    UUID, UUID, TEXT, BIGINT, TEXT
);
DROP FUNCTION IF EXISTS public.has_result_slip_upload_intent(TEXT, UUID);
DROP TABLE IF EXISTS public.result_slip_upload_intents;
-- Keep result_slip_upload rate_limit_events as non-sensitive abuse/audit
-- evidence; deleting them would make a rollback an upload-quota bypass.

DROP FUNCTION IF EXISTS public.is_superadmin();
DROP TABLE IF EXISTS public.security_principals;
GRANT EXECUTE ON FUNCTION public.wipe_operational_data(TEXT)
    TO authenticated;
REVOKE EXECUTE ON FUNCTION public.wipe_operational_data(TEXT)
    FROM PUBLIC, anon;

-- Deliberate non-rollback: retain 038's least-privilege Edge invocation
-- credential and request timeout. See the security exception in the header.
CREATE OR REPLACE FUNCTION public.notify_parent_on_attendance()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_secret TEXT;
BEGIN
    -- Retain 038's duplicate/non-alerting-status suppression with the
    -- least-privilege invocation credential. Rolling either protection back
    -- would recreate an avoidable push-amplification path.
    IF TG_OP = 'UPDATE' AND OLD.status IS NOT DISTINCT FROM NEW.status THEN
        RETURN NEW;
    END IF;
    IF NEW.status NOT IN ('late', 'absent') THEN
        RETURN NEW;
    END IF;

    SELECT decrypted_secret INTO v_secret
    FROM vault.decrypted_secrets
    WHERE name = 'notify_parent_invoke_secret';

    IF v_secret IS NULL OR char_length(v_secret) NOT BETWEEN 32 AND 512 THEN
        RAISE WARNING 'notify_parent_on_attendance invocation secret is missing or invalid';
        RETURN NEW;
    END IF;

    PERFORM net.http_post(
        url     := 'https://zgikcbsxzjgbigywxbbj.supabase.co/functions/v1/notify-parent',
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'X-Notify-Secret', v_secret
        ),
        body    := jsonb_build_object(
            'student_id', NEW.student_id,
            'status', NEW.status,
            'session_id', NEW.session_id
        ),
        timeout_milliseconds := 30000
    );
    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'notify_parent_on_attendance failed';
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_parent_on_dismissal()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_secret TEXT;
BEGIN
    SELECT decrypted_secret INTO v_secret
    FROM vault.decrypted_secrets
    WHERE name = 'notify_parent_invoke_secret';

    IF v_secret IS NULL OR char_length(v_secret) NOT BETWEEN 32 AND 512 THEN
        RAISE WARNING 'notify_parent_on_dismissal invocation secret is missing or invalid';
        RETURN NEW;
    END IF;

    PERFORM net.http_post(
        url     := 'https://zgikcbsxzjgbigywxbbj.supabase.co/functions/v1/notify-parent',
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'X-Notify-Secret', v_secret
        ),
        body    := jsonb_build_object(
            'student_id', NEW.student_id,
            'status', 'dismissed',
            'session_id', NEW.session_id,
            'dismissal_id', NEW.id
        ),
        timeout_milliseconds := 30000
    );
    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'notify_parent_on_dismissal failed';
    RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.notify_parent_on_attendance(),
    public.notify_parent_on_dismissal()
    FROM PUBLIC, anon, authenticated;

DROP FUNCTION IF EXISTS public.get_parent_attendance_summary(UUID);
DROP FUNCTION IF EXISTS public.get_parent_attendance_history(UUID, INTEGER, DATE);
DROP FUNCTION IF EXISTS public.get_parent_children();
DROP FUNCTION IF EXISTS public.get_parent_result_slips(UUID);
DROP FUNCTION IF EXISTS public.get_parent_messages(UUID);
DROP FUNCTION IF EXISTS public.get_parent_dismissals();
DROP FUNCTION IF EXISTS public.submit_parent_result_slip(
    UUID, TEXT, DATE, TEXT, NUMERIC, NUMERIC
);
DROP FUNCTION IF EXISTS public.send_parent_message(UUID, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.review_correction_request(UUID, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.record_admin_consent(UUID, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.consume_invite_rate_limit(UUID);
DROP FUNCTION IF EXISTS public.submit_app_events(JSONB);
DROP FUNCTION IF EXISTS public.register_device_token(TEXT, TEXT);

DROP POLICY IF EXISTS "app_events: authenticated insert own" ON app_events;
CREATE POLICY "app_events: authenticated insert own"
    ON app_events FOR INSERT TO authenticated
    WITH CHECK (user_id = auth.uid());
GRANT INSERT, SELECT ON app_events TO authenticated;

DROP POLICY IF EXISTS "device_tokens: owner manages own" ON device_tokens;
CREATE POLICY "device_tokens: owner manages own"
    ON device_tokens FOR ALL TO authenticated
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());
GRANT SELECT, INSERT, UPDATE, DELETE ON device_tokens TO authenticated;

DROP POLICY IF EXISTS "students: parent can read own children" ON students;
CREATE POLICY "students: parent can read own children"
    ON students FOR SELECT TO authenticated
    USING (is_parent() AND parent_owns_student(students.id));

DROP POLICY IF EXISTS "classes: parent reads children's classes" ON classes;
CREATE POLICY "classes: parent reads children's classes"
    ON classes FOR SELECT TO authenticated
    USING (
        is_parent() AND EXISTS (
            SELECT 1
            FROM enrollments e
            JOIN parent_student_links psl ON psl.student_id = e.student_id
            WHERE e.class_id = classes.id
              AND e.is_active = TRUE
              AND psl.parent_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "enrollments: parent reads own children" ON enrollments;
CREATE POLICY "enrollments: parent reads own children"
    ON enrollments FOR SELECT TO authenticated
    USING (is_parent() AND parent_owns_student(enrollments.student_id));

DROP POLICY IF EXISTS "sessions: parent reads children's sessions" ON sessions;
CREATE POLICY "sessions: parent reads children's sessions"
    ON sessions FOR SELECT TO authenticated
    USING (
        is_parent() AND EXISTS (
            SELECT 1
            FROM enrollments e
            JOIN parent_student_links psl ON psl.student_id = e.student_id
            WHERE e.class_id = sessions.class_id
              AND e.is_active = TRUE
              AND psl.parent_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "attendance_records: parent reads own children"
    ON attendance_records;
CREATE POLICY "attendance_records: parent reads own children"
    ON attendance_records FOR SELECT TO authenticated
    USING (
        is_parent()
        AND parent_owns_student(attendance_records.student_id)
        AND NOT EXISTS (
            SELECT 1
            FROM sessions s
            JOIN classes c ON c.id = s.class_id
            WHERE s.id = attendance_records.session_id
              AND c.is_study_space
        )
    );

-- Restore the post-037 direct parent reads. These deliberately reproduce the
-- older, broader base-table surface and are one reason this rollback is only
-- suitable for an emergency.
DROP POLICY IF EXISTS "parent_student_links: parent reads own"
    ON parent_student_links;
CREATE POLICY "parent_student_links: parent reads own"
    ON parent_student_links FOR SELECT TO authenticated
    USING (parent_id = auth.uid());

DROP POLICY IF EXISTS "result_slips: parent reads own child" ON result_slips;
CREATE POLICY "result_slips: parent reads own child"
    ON result_slips FOR SELECT TO authenticated
    USING (is_parent() AND parent_owns_student(student_id));

DROP POLICY IF EXISTS "messages: participant reads own" ON messages;
CREATE POLICY "messages: participant reads own"
    ON messages FOR SELECT TO authenticated
    USING (
        sender_id = auth.uid()
        OR recipient_id = auth.uid()
        OR is_admin()
    );

DROP POLICY IF EXISTS "dismissals: parent reads own child" ON dismissals;
CREATE POLICY "dismissals: parent reads own child"
    ON dismissals FOR SELECT TO authenticated
    USING (is_parent() AND parent_owns_student(student_id));

DROP POLICY IF EXISTS "consent_records: parent reads own child"
    ON consent_records;
CREATE POLICY "consent_records: parent reads own child"
    ON consent_records FOR SELECT TO authenticated
    USING (is_parent() AND parent_owns_student(student_id));
DROP POLICY IF EXISTS "consent_records: admin read" ON consent_records;
CREATE POLICY "consent_records: admin full"
    ON consent_records FOR ALL TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());
GRANT SELECT, INSERT ON consent_records TO authenticated;

DROP POLICY IF EXISTS "correction_requests: parent reads own child"
    ON correction_requests;
CREATE POLICY "correction_requests: parent reads own child"
    ON correction_requests FOR SELECT TO authenticated
    USING (is_parent() AND parent_owns_student(student_id));

DROP POLICY IF EXISTS "correction_requests: admin read" ON correction_requests;
CREATE POLICY "correction_requests: admin full"
    ON correction_requests FOR ALL TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());
GRANT SELECT, INSERT, UPDATE, DELETE ON correction_requests TO authenticated;

CREATE OR REPLACE FUNCTION public.mark_safely_home(p_dismissal_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT is_parent() THEN RAISE EXCEPTION 'not authorized'; END IF;

    UPDATE dismissals
    SET safely_home_at = NOW(),
        confirmed_by = auth.uid()
    WHERE id = p_dismissal_id
      AND safely_home_at IS NULL
      AND parent_owns_student(student_id);

    IF NOT FOUND THEN
        RAISE EXCEPTION 'dismissal not found, already confirmed, or not your child';
    END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.mark_safely_home(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_safely_home(UUID) TO authenticated;

DROP POLICY IF EXISTS "policy_documents: anon read current" ON policy_documents;
CREATE POLICY "policy_documents: anon read current"
    ON policy_documents FOR SELECT TO anon
    USING (is_current = TRUE);

DROP POLICY IF EXISTS "policy_documents: auth read" ON policy_documents;
CREATE POLICY "policy_documents: auth read"
    ON policy_documents FOR SELECT TO authenticated USING (TRUE);

DROP POLICY IF EXISTS "awards: admin only" ON awards;
CREATE POLICY "awards: admin only"
    ON awards FOR ALL TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());

DROP POLICY IF EXISTS "awards: parent reads own child" ON awards;
CREATE POLICY "awards: parent reads own child"
    ON awards FOR SELECT TO authenticated
    USING (is_parent() AND parent_owns_student(student_id));

DROP TRIGGER IF EXISTS enforce_session_notes_feature_flag ON sessions;
DROP FUNCTION IF EXISTS public.enforce_session_notes_feature_flag();
ALTER TABLE sessions DROP CONSTRAINT IF EXISTS sessions_notes_length_check;

DROP TRIGGER IF EXISTS enforce_student_avatar_feature_flag ON students;
DROP FUNCTION IF EXISTS public.enforce_student_avatar_feature_flag();
ALTER TABLE students
    DROP CONSTRAINT IF EXISTS students_avatar_url_path_check;

DROP POLICY IF EXISTS "result-slips: admin all" ON storage.objects;
CREATE POLICY "result-slips: admin all"
    ON storage.objects FOR ALL TO authenticated
    USING (bucket_id = 'result-slips' AND is_admin())
    WITH CHECK (bucket_id = 'result-slips' AND is_admin());

DROP POLICY IF EXISTS "result-slips: parent read" ON storage.objects;
CREATE POLICY "result-slips: parent read"
    ON storage.objects FOR SELECT TO authenticated
    USING (
        bucket_id = 'result-slips'
        AND is_parent()
        AND parent_owns_student(((storage.foldername(name))[1])::UUID)
    );

DROP POLICY IF EXISTS "result-slips: parent upload own child" ON storage.objects;
CREATE POLICY "result-slips: parent upload own child"
    ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (
        bucket_id = 'result-slips'
        AND is_parent()
        AND parent_owns_student(((storage.foldername(name))[1])::UUID)
    );

UPDATE storage.buckets
SET public = FALSE,
    file_size_limit = NULL,
    allowed_mime_types = NULL
WHERE id = 'result-slips';

DROP POLICY IF EXISTS "result_slips: parent uploads own child" ON result_slips;
CREATE POLICY "result_slips: parent uploads own child"
    ON result_slips FOR INSERT TO authenticated
    WITH CHECK (
        is_parent()
        AND parent_owns_student(student_id)
        AND uploaded_by = auth.uid()
    );

DROP POLICY IF EXISTS "messages: parent sends about own child" ON messages;
CREATE POLICY "messages: parent sends about own child"
    ON messages FOR INSERT TO authenticated
    WITH CHECK (
        is_parent()
        AND sender_id = auth.uid()
        AND student_id IS NOT NULL
        AND parent_owns_student(student_id)
    );

DROP POLICY IF EXISTS "correction_requests: parent creates own child"
    ON correction_requests;
CREATE POLICY "correction_requests: parent creates own child"
    ON correction_requests FOR INSERT TO authenticated
    WITH CHECK (
        is_parent()
        AND parent_owns_student(student_id)
        AND requested_by = auth.uid()
    );

DROP POLICY IF EXISTS "data_disclosures: admin read" ON data_disclosures;
DROP POLICY IF EXISTS "data_disclosures: admin insert" ON data_disclosures;
CREATE POLICY "data_disclosures: admin only"
    ON data_disclosures FOR ALL TO authenticated
    USING (is_admin())
    WITH CHECK (is_admin());
GRANT SELECT, INSERT, UPDATE, DELETE ON data_disclosures TO authenticated;

ALTER TABLE result_slips
    DROP CONSTRAINT IF EXISTS result_slips_exam_name_text_check,
    DROP CONSTRAINT IF EXISTS result_slips_subject_text_check,
    DROP CONSTRAINT IF EXISTS result_slips_scores_check,
    DROP CONSTRAINT IF EXISTS result_slips_file_path_check;

ALTER TABLE messages
    DROP CONSTRAINT IF EXISTS messages_subject_text_check,
    DROP CONSTRAINT IF EXISTS messages_body_text_check;

ALTER TABLE correction_requests
    DROP CONSTRAINT IF EXISTS correction_requests_field_name_text_check,
    DROP CONSTRAINT IF EXISTS correction_requests_current_value_text_check,
    DROP CONSTRAINT IF EXISTS correction_requests_requested_value_text_check,
    DROP CONSTRAINT IF EXISTS correction_requests_review_note_text_check;

CREATE OR REPLACE FUNCTION public._anonymise_student(p_student_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    PERFORM set_config('app.suppress_audit', 'on', TRUE);
    UPDATE students
    SET full_name = 'Redacted Student',
        date_of_birth = NULL,
        school = NULL,
        year_of_study = NULL,
        notes = NULL,
        is_active = FALSE
    WHERE id = p_student_id;
    UPDATE attendance_records SET notes = NULL WHERE student_id = p_student_id;
    DELETE FROM result_slips       WHERE student_id = p_student_id;
    DELETE FROM consent_records     WHERE student_id = p_student_id;
    DELETE FROM correction_requests WHERE student_id = p_student_id;
    UPDATE audit_log
    SET old_data = NULL, new_data = NULL
    WHERE table_name = 'students' AND record_id = p_student_id;
    DELETE FROM audit_log
    WHERE old_data->>'student_id' = p_student_id::TEXT
       OR new_data->>'student_id' = p_student_id::TEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.anonymise_student(p_student_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT is_admin() THEN RAISE EXCEPTION 'not authorized'; END IF;
    PERFORM _anonymise_student(p_student_id);
    INSERT INTO data_disclosures (
        student_id, disclosed_to, disclosure_type, disclosed_by, detail
    ) VALUES (
        p_student_id, 'Internal', 'other', auth.uid(),
        jsonb_build_object('action', 'anonymise_student')
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.erase_student(p_student_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT is_admin() THEN RAISE EXCEPTION 'not authorized'; END IF;
    PERFORM set_config('app.suppress_audit', 'on', TRUE);
    DELETE FROM messages            WHERE student_id = p_student_id;
    DELETE FROM dismissals          WHERE student_id = p_student_id;
    DELETE FROM food_poll_responses WHERE student_id = p_student_id;
    DELETE FROM students            WHERE id = p_student_id;
    DELETE FROM audit_log
    WHERE (table_name = 'students' AND record_id = p_student_id)
       OR old_data->>'student_id' = p_student_id::TEXT
       OR new_data->>'student_id' = p_student_id::TEXT;
END;
$$;

GRANT EXECUTE ON FUNCTION public.anonymise_student(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.erase_student(UUID) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.anonymise_student(UUID)
    FROM PUBLIC, anon, service_role;
REVOKE EXECUTE ON FUNCTION public.erase_student(UUID)
    FROM PUBLIC, anon, service_role;

-- Restore the exact post-037 attendance behavior. This removes the universal
-- actor/time/enrollment integrity trigger and the direct-write restrictions
-- introduced by 038; callers should understand that this is a security
-- regression, not merely a compatibility rollback.
DROP TRIGGER IF EXISTS archive_attendance_mutation_receipt
    ON attendance_records;
DROP FUNCTION IF EXISTS public.archive_attendance_mutation_receipt();
DROP FUNCTION IF EXISTS public.attendance_mutation_is_replay(TEXT, UUID, UUID);
DROP TABLE IF EXISTS public.attendance_mutation_receipts;

DROP TRIGGER IF EXISTS enforce_attendance_write_integrity
    ON attendance_records;
DROP FUNCTION IF EXISTS public.enforce_attendance_write_integrity();

ALTER TABLE attendance_records
    DROP CONSTRAINT IF EXISTS attendance_records_notes_length_check,
    DROP CONSTRAINT IF EXISTS attendance_records_late_reason_check,
    DROP CONSTRAINT IF EXISTS attendance_records_mutation_id_check;

-- Verbatim body from 037_retrospective_sessions.sql.
CREATE OR REPLACE FUNCTION public.check_session_not_ended()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    v_session_id UUID := COALESCE(NEW.session_id, OLD.session_id);
BEGIN
    IF EXISTS (
        SELECT 1 FROM sessions
        WHERE id = v_session_id AND ended_at IS NOT NULL
    ) AND COALESCE(current_setting('app.retrospective_attendance_write', TRUE), 'off') <> 'on' THEN
        RAISE EXCEPTION 'Cannot modify attendance for ended session %', v_session_id
            USING ERRCODE = 'TA001';
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$;

-- Verbatim body from 037_retrospective_sessions.sql.
CREATE OR REPLACE FUNCTION public.check_retrospective_session_changes()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    v_today DATE := (NOW() AT TIME ZONE 'Asia/Singapore')::DATE;
BEGIN
    IF TG_OP = 'INSERT' AND NEW.session_date < v_today
       AND COALESCE(current_setting('app.retrospective_session_create', TRUE), 'off') <> 'on' THEN
        RAISE EXCEPTION 'past sessions must be created through create_retrospective_session';
    END IF;
    IF TG_OP = 'UPDATE' AND OLD.session_date < v_today
       AND (NEW.class_id IS DISTINCT FROM OLD.class_id
            OR NEW.session_date IS DISTINCT FROM OLD.session_date) THEN
        RAISE EXCEPTION 'historical session class and date are immutable';
    END IF;
    IF TG_OP = 'DELETE' AND OLD.session_date < v_today THEN
        RAISE EXCEPTION 'historical sessions cannot be deleted';
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$;

-- Verbatim behavior from 037_retrospective_sessions.sql. Migration 038's
-- replacement sets app.retrospective_session_update so the hardened trigger
-- can distinguish its trusted path; the post-037 trigger does not use it.
CREATE OR REPLACE FUNCTION public.update_retrospective_session(
    session_id UUID,
    topic TEXT DEFAULT NULL,
    notes TEXT DEFAULT NULL,
    sub_tutor_id UUID DEFAULT NULL
)
RETURNS sessions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_session sessions%ROWTYPE;
    v_is_study_space BOOLEAN;
    v_today DATE := (NOW() AT TIME ZONE 'Asia/Singapore')::DATE;
BEGIN
    IF NOT is_feature_enabled('retrospective_sessions') THEN
        RAISE EXCEPTION 'retrospective sessions are disabled';
    END IF;

    SELECT s.* INTO v_session
    FROM sessions s
    WHERE s.id = update_retrospective_session.session_id;
    SELECT c.is_study_space INTO v_is_study_space
    FROM classes c WHERE c.id = v_session.class_id;
    IF NOT FOUND OR v_is_study_space OR v_session.session_date >= v_today THEN
        RAISE EXCEPTION 'session is not eligible for retrospective editing';
    END IF;
    IF NOT (is_admin() OR (is_tutor() AND tutor_owns_class(v_session.class_id))) THEN
        RAISE EXCEPTION 'not authorized';
    END IF;
    IF notes IS NOT NULL AND BTRIM(notes) <> '' AND NOT is_feature_enabled('session_notes') THEN
        RAISE EXCEPTION 'session notes are disabled';
    END IF;
    IF sub_tutor_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM profiles p WHERE p.id = sub_tutor_id AND p.role = 'tutor'
    ) THEN
        RAISE EXCEPTION 'invalid substitute tutor';
    END IF;

    UPDATE sessions s
    SET topic = NULLIF(BTRIM(update_retrospective_session.topic), ''),
        notes = NULLIF(BTRIM(update_retrospective_session.notes), ''),
        sub_tutor_id = update_retrospective_session.sub_tutor_id
    WHERE s.id = update_retrospective_session.session_id
    RETURNING s.* INTO v_session;

    RETURN v_session;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.update_retrospective_session(
    UUID, TEXT, TEXT, UUID
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_retrospective_session(
    UUID, TEXT, TEXT, UUID
) TO authenticated;

-- Verbatim body from 013_audit_fixes.sql, which remained current through 037.
CREATE OR REPLACE FUNCTION public.sync_attendance(records JSONB)
RETURNS JSONB LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    rec            JSONB;
    v_id           UUID;
    synced         INT := 0;
    skipped        INT := 0;
    blocked        INT := 0;
    v_marked_at    TIMESTAMPTZ;
BEGIN
    FOR rec IN SELECT * FROM jsonb_array_elements(records)
    LOOP
        -- Clamp: do not allow a client to record a marked_at more than 5 minutes in the future.
        v_marked_at := LEAST(
            COALESCE((rec->>'marked_at')::TIMESTAMPTZ, NOW()),
            NOW() + INTERVAL '5 minutes'
        );

        BEGIN
            INSERT INTO attendance_records (
                session_id,
                student_id,
                status,
                notes,
                client_mutation_id,
                marked_by,
                marked_at
            )
            VALUES (
                (rec->>'session_id')::UUID,
                (rec->>'student_id')::UUID,
                rec->>'status',
                rec->>'notes',
                rec->>'client_mutation_id',
                auth.uid(),
                v_marked_at
            )
            ON CONFLICT (session_id, student_id) DO UPDATE
                SET status             = EXCLUDED.status,
                    notes              = EXCLUDED.notes,
                    marked_by          = EXCLUDED.marked_by,
                    marked_at          = EXCLUDED.marked_at,
                    client_mutation_id = EXCLUDED.client_mutation_id
            -- Only overwrite if the incoming record is newer.
            WHERE attendance_records.marked_at <= EXCLUDED.marked_at
            RETURNING id INTO v_id;

            IF FOUND THEN
                synced := synced + 1;
            ELSE
                skipped := skipped + 1;
            END IF;
        EXCEPTION
            -- The open-session guard raises when the target session has ended.
            WHEN raise_exception THEN
                blocked := blocked + 1;
            -- A differing client_mutation_id for an already-updated row
            -- collides on the UNIQUE(client_mutation_id) constraint.
            WHEN unique_violation THEN
                skipped := skipped + 1;
        END;
    END LOOP;

    RETURN jsonb_build_object(
        'synced',                synced,
        'skipped',               skipped,
        'blocked_ended_session', blocked
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.sync_attendance(JSONB)
    TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.sync_attendance(JSONB) FROM PUBLIC, anon;

-- Verbatim behavior from 037_retrospective_sessions.sql.
CREATE OR REPLACE FUNCTION public.mark_retrospective_attendance(
    session_id UUID,
    student_id UUID,
    status TEXT
)
RETURNS attendance_records
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_session sessions%ROWTYPE;
    v_is_study_space BOOLEAN;
    v_record attendance_records%ROWTYPE;
    v_today DATE := (NOW() AT TIME ZONE 'Asia/Singapore')::DATE;
BEGIN
    IF NOT is_feature_enabled('retrospective_sessions') THEN
        RAISE EXCEPTION 'retrospective sessions are disabled';
    END IF;

    SELECT s.* INTO v_session
    FROM sessions s
    WHERE s.id = mark_retrospective_attendance.session_id;
    SELECT c.is_study_space INTO v_is_study_space
    FROM classes c WHERE c.id = v_session.class_id;
    IF NOT FOUND OR v_is_study_space OR v_session.session_date >= v_today THEN
        RAISE EXCEPTION 'session is not eligible for retrospective editing';
    END IF;
    IF NOT (is_admin() OR (is_tutor() AND tutor_owns_class(v_session.class_id))) THEN
        RAISE EXCEPTION 'not authorized';
    END IF;
    IF status NOT IN ('present', 'late', 'absent', 'excused') THEN
        RAISE EXCEPTION 'invalid attendance status';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM students st
        WHERE st.id = mark_retrospective_attendance.student_id AND st.is_active
    ) THEN
        RAISE EXCEPTION 'student is not active or visible';
    END IF;
    IF is_tutor() AND NOT EXISTS (
        SELECT 1
        FROM enrollments e
        JOIN class_tutor_assignments cta ON cta.class_id = e.class_id
        WHERE e.student_id = mark_retrospective_attendance.student_id
          AND e.is_active
          AND cta.tutor_id = auth.uid()
          AND (cta.assigned_until IS NULL OR cta.assigned_until >= CURRENT_DATE)
    ) THEN
        RAISE EXCEPTION 'student is not visible';
    END IF;

    PERFORM set_config('app.retrospective_attendance_write', 'on', TRUE);
    INSERT INTO attendance_records (
        session_id, student_id, status, marked_by, marked_at, client_mutation_id
    ) VALUES (
        mark_retrospective_attendance.session_id,
        mark_retrospective_attendance.student_id,
        mark_retrospective_attendance.status,
        auth.uid(), NOW(), gen_random_uuid()::TEXT
    )
    ON CONFLICT ON CONSTRAINT attendance_records_session_id_student_id_key DO UPDATE
    SET status = EXCLUDED.status,
        marked_by = EXCLUDED.marked_by,
        marked_at = NOW(),
        client_mutation_id = EXCLUDED.client_mutation_id
    RETURNING * INTO v_record;
    PERFORM set_config('app.retrospective_attendance_write', 'off', TRUE);

    RETURN v_record;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.mark_retrospective_attendance(UUID, UUID, TEXT)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_retrospective_attendance(UUID, UUID, TEXT)
    TO authenticated;

DROP FUNCTION IF EXISTS public.update_session_note(UUID, TEXT);
DROP FUNCTION IF EXISTS public.set_session_lifecycle(UUID, TEXT);
DROP FUNCTION IF EXISTS public.get_or_create_today_session(UUID);
DROP TRIGGER IF EXISTS enforce_session_lifecycle_boundary ON sessions;
DROP FUNCTION IF EXISTS public.enforce_session_lifecycle_boundary();
DROP FUNCTION IF EXISTS public.get_my_classes();

DROP POLICY IF EXISTS "attendance_records: tutor reads/writes their sessions"
    ON attendance_records;
CREATE POLICY "attendance_records: tutor reads/writes their sessions"
    ON attendance_records FOR ALL TO authenticated
    USING (
        is_tutor() AND EXISTS (
            SELECT 1 FROM sessions s
            WHERE s.id = attendance_records.session_id
              AND tutor_owns_class(s.class_id)
        )
    )
    WITH CHECK (
        is_tutor() AND EXISTS (
            SELECT 1 FROM sessions s
            WHERE s.id = attendance_records.session_id
              AND tutor_owns_class(s.class_id)
        )
    );

DROP POLICY IF EXISTS "substitute_can_mark_attendance" ON attendance_records;
CREATE POLICY "substitute_can_mark_attendance"
    ON attendance_records FOR ALL TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM sessions s
            WHERE s.id = attendance_records.session_id
              AND s.sub_tutor_id = auth.uid()
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM sessions s
            WHERE s.id = attendance_records.session_id
              AND s.sub_tutor_id = auth.uid()
        )
    );

DROP FUNCTION IF EXISTS public.student_is_enrolled_for_session(UUID, UUID);

-- Restore the post-014 SECURITY INVOKER roster. This intentionally recreates
-- the broader pre-038 behavior for an emergency rollback.
CREATE OR REPLACE FUNCTION public.get_session_roster(p_session_id UUID)
RETURNS TABLE (
    student_id UUID,
    full_name TEXT,
    attendance_id UUID,
    status TEXT,
    marked_at TIMESTAMPTZ,
    notes TEXT,
    late_reason TEXT,
    avatar_url TEXT
)
LANGUAGE SQL
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
    SELECT st.id, st.full_name, ar.id, ar.status, ar.marked_at,
           ar.notes, ar.late_reason, st.avatar_url
    FROM sessions se
    JOIN enrollments e
      ON e.class_id = se.class_id AND e.is_active = TRUE
    JOIN students st
      ON st.id = e.student_id AND st.is_active = TRUE
    LEFT JOIN attendance_records ar
      ON ar.session_id = se.id AND ar.student_id = st.id
    WHERE se.id = p_session_id
    ORDER BY st.full_name
$$;

GRANT EXECUTE ON FUNCTION public.get_session_roster(UUID)
    TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.get_session_roster(UUID)
    FROM PUBLIC, anon;

DROP POLICY IF EXISTS "substitute_can_read_session" ON sessions;
CREATE POLICY "substitute_can_read_session"
    ON sessions FOR SELECT TO authenticated
    USING (sub_tutor_id = auth.uid());

DROP TRIGGER IF EXISTS validate_session_sub_tutor ON sessions;
DROP FUNCTION IF EXISTS public.validate_session_sub_tutor();

ALTER TABLE class_tutor_assignments
    ALTER COLUMN assigned_from SET DEFAULT CURRENT_DATE;

DROP POLICY IF EXISTS "student_results: tutor manages enrolled students"
    ON student_results;
CREATE POLICY "student_results: tutor manages enrolled students"
    ON student_results FOR ALL TO authenticated
    USING (
        is_tutor() AND EXISTS (
            SELECT 1
            FROM enrollments e
            JOIN classes c ON c.id = e.class_id
            JOIN class_tutor_assignments cta ON cta.class_id = e.class_id
            WHERE e.student_id = student_results.student_id
              AND e.is_active = TRUE AND c.is_active = TRUE
              AND cta.tutor_id = auth.uid()
              AND cta.assigned_from <= CURRENT_DATE
              AND (cta.assigned_until IS NULL OR cta.assigned_until >= CURRENT_DATE)
              AND ((student_results.subject = 'Math'
                    AND LOWER(BTRIM(c.subject)) LIKE 'math%')
                OR (student_results.subject = 'English'
                    AND LOWER(BTRIM(c.subject)) LIKE 'eng%'))
        )
    )
    WITH CHECK (
        is_tutor() AND EXISTS (
            SELECT 1
            FROM enrollments e
            JOIN classes c ON c.id = e.class_id
            JOIN class_tutor_assignments cta ON cta.class_id = e.class_id
            WHERE e.student_id = student_results.student_id
              AND e.is_active = TRUE AND c.is_active = TRUE
              AND cta.tutor_id = auth.uid()
              AND cta.assigned_from <= CURRENT_DATE
              AND (cta.assigned_until IS NULL OR cta.assigned_until >= CURRENT_DATE)
              AND ((student_results.subject = 'Math'
                    AND LOWER(BTRIM(c.subject)) LIKE 'math%')
                OR (student_results.subject = 'English'
                    AND LOWER(BTRIM(c.subject)) LIKE 'eng%'))
        )
    );

DROP POLICY IF EXISTS "student-photos: admin all" ON storage.objects;
CREATE POLICY "student-photos: admin all"
    ON storage.objects FOR ALL TO authenticated
    USING (bucket_id = 'student-photos' AND is_admin())
    WITH CHECK (bucket_id = 'student-photos' AND is_admin());

DROP POLICY IF EXISTS "student-photos: tutor read" ON storage.objects;
CREATE POLICY "student-photos: tutor read"
    ON storage.objects FOR SELECT TO authenticated
    USING (
        bucket_id = 'student-photos'
        AND is_tutor()
        AND EXISTS (
            SELECT 1
            FROM enrollments e
            JOIN class_tutor_assignments cta ON cta.class_id = e.class_id
            WHERE e.student_id = ((storage.foldername(name))[1])::UUID
              AND e.is_active = TRUE
              AND cta.tutor_id = auth.uid()
              AND (cta.assigned_until IS NULL OR cta.assigned_until >= CURRENT_DATE)
        )
    );

DROP POLICY IF EXISTS "student-photos: parent read" ON storage.objects;
CREATE POLICY "student-photos: parent read"
    ON storage.objects FOR SELECT TO authenticated
    USING (
        bucket_id = 'student-photos'
        AND is_parent()
        AND parent_owns_student(((storage.foldername(name))[1])::UUID)
    );

UPDATE storage.buckets
SET public = FALSE,
    file_size_limit = NULL,
    allowed_mime_types = NULL
WHERE id = 'student-photos';

DROP POLICY IF EXISTS "students: tutor can read enrolled students" ON students;
CREATE POLICY "students: tutor can read enrolled students"
    ON students FOR SELECT TO authenticated
    USING (
        is_tutor() AND EXISTS (
            SELECT 1
            FROM enrollments e
            JOIN class_tutor_assignments cta ON cta.class_id = e.class_id
            WHERE e.student_id = students.id
              AND e.is_active = TRUE
              AND cta.tutor_id = auth.uid()
              AND (cta.assigned_until IS NULL OR cta.assigned_until >= CURRENT_DATE)
        )
    );

DROP FUNCTION IF EXISTS public.substitute_covers_session(UUID);

CREATE OR REPLACE FUNCTION public.tutor_owns_class(p_class_id UUID)
RETURNS BOOLEAN
LANGUAGE SQL
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1 FROM class_tutor_assignments
        WHERE class_id = p_class_id
          AND tutor_id = auth.uid()
          AND (assigned_until IS NULL OR assigned_until >= CURRENT_DATE)
    )
$$;

DROP FUNCTION IF EXISTS public.canonical_storage_student_id(TEXT);

-- Fail the rollback if a critical teardown/restoration step was skipped. These
-- are explicit exceptions rather than ASSERTs so plpgsql.check_asserts cannot
-- disable them in production.
DO $$
BEGIN
    IF to_regclass('public.student_storage_cleanup_queue') IS NOT NULL
       OR to_regclass('public.result_slip_upload_intents') IS NOT NULL
       OR to_regclass('public.attendance_mutation_receipts') IS NOT NULL THEN
        RAISE EXCEPTION '038 rollback left a durable-work table behind';
    END IF;
    IF to_regprocedure('public.invoke_student_storage_cleanup()') IS NOT NULL
       OR to_regprocedure(
            'public.reserve_result_slip_upload(uuid,uuid,text,bigint,text)'
          ) IS NOT NULL
       OR to_regprocedure(
            'public.finalize_result_slip_upload(uuid,uuid,text,text,text,numeric,numeric)'
          ) IS NOT NULL
       OR to_regprocedure(
            'public.has_result_slip_upload_intent(text,uuid)'
          ) IS NOT NULL
       OR to_regprocedure(
            'public.attendance_mutation_is_replay(text,uuid,uuid)'
          ) IS NOT NULL
       OR to_regprocedure(
            'public.archive_attendance_mutation_receipt()'
          ) IS NOT NULL
       OR to_regprocedure('public.get_parent_result_slips(uuid)') IS NOT NULL
       OR to_regprocedure('public.get_parent_messages(uuid)') IS NOT NULL
       OR to_regprocedure('public.get_parent_dismissals()') IS NOT NULL
       OR to_regprocedure(
            'public.submit_parent_result_slip(uuid,text,date,text,numeric,numeric)'
          ) IS NOT NULL
       OR to_regprocedure(
            'public.send_parent_message(uuid,text,text)'
          ) IS NOT NULL
       OR to_regprocedure('public.get_my_classes()') IS NOT NULL
       OR to_regprocedure(
            'public.get_or_create_today_session(uuid)'
          ) IS NOT NULL
       OR to_regprocedure(
            'public.set_session_lifecycle(uuid,text)'
          ) IS NOT NULL
       OR to_regprocedure('public.update_session_note(uuid,text)') IS NOT NULL
       OR to_regprocedure(
            'public.enforce_session_lifecycle_boundary()'
          ) IS NOT NULL
       OR to_regprocedure('public.substitute_covers_session(uuid)') IS NOT NULL
       OR to_regprocedure(
            'public.record_admin_consent(uuid,text,text,text)'
          ) IS NOT NULL
       OR to_regprocedure('public.consume_invite_rate_limit(uuid)') IS NOT NULL
       OR to_regprocedure('public.submit_app_events(jsonb)') IS NOT NULL
       OR to_regprocedure('public.register_device_token(text,text)') IS NOT NULL
       OR to_regprocedure('public.enforce_attendance_write_integrity()') IS NOT NULL THEN
        RAISE EXCEPTION '038 rollback left a hardened helper behind';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgrelid = 'attendance_records'::REGCLASS
          AND tgname IN (
              'enforce_attendance_write_integrity',
              'archive_attendance_mutation_receipt'
          )
          AND NOT tgisinternal
    ) THEN
        RAISE EXCEPTION '038 rollback left the attendance integrity trigger behind';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgrelid = 'sessions'::REGCLASS
          AND tgname = 'enforce_session_lifecycle_boundary'
          AND NOT tgisinternal
    ) THEN
        RAISE EXCEPTION '038 rollback left the session lifecycle trigger behind';
    END IF;
    IF (
        SELECT prosecdef
        FROM pg_proc
        WHERE oid = 'public.get_session_roster(uuid)'::REGPROCEDURE
    ) THEN
        RAISE EXCEPTION '038 rollback left get_session_roster SECURITY DEFINER';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'attendance_records'::REGCLASS
          AND conname IN (
              'attendance_records_notes_length_check',
              'attendance_records_late_reason_check',
              'attendance_records_mutation_id_check'
          )
    ) THEN
        RAISE EXCEPTION '038 rollback left an attendance constraint behind';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'sessions'::REGCLASS
          AND conname = 'sessions_notes_length_check'
    ) THEN
        RAISE EXCEPTION '038 rollback left the session note constraint behind';
    END IF;
    IF POSITION(
        'retrospective_session_update' IN LOWER(
            pg_get_functiondef(
                'public.update_retrospective_session(uuid,text,text,uuid)'::REGPROCEDURE
            )
        )
    ) > 0 OR POSITION(
        'retrospective_session_update' IN LOWER(
            pg_get_functiondef(
                'public.check_retrospective_session_changes()'::REGPROCEDURE
            )
        )
    ) > 0 THEN
        RAISE EXCEPTION '038 rollback left the hardened retrospective update path behind';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'storage'
          AND tablename = 'objects'
          AND policyname = 'result-slips: parent upload own child'
    ) OR NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'messages'
          AND policyname = 'messages: participant reads own'
    ) OR NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'parent_student_links'
          AND policyname = 'parent_student_links: parent reads own'
    ) THEN
        RAISE EXCEPTION '038 rollback did not restore the post-037 parent policies';
    END IF;
    IF POSITION(
        'x-notify-secret' IN LOWER(
            pg_get_functiondef(
                'public.notify_parent_on_attendance()'::REGPROCEDURE
            )
        )
    ) = 0 OR POSITION(
        'authorization' IN LOWER(
            pg_get_functiondef(
                'public.notify_parent_on_attendance()'::REGPROCEDURE
            )
        )
    ) > 0 THEN
        RAISE EXCEPTION 'notification invocation regressed from dedicated-secret auth';
    END IF;
    IF POSITION(
        'x-notify-secret' IN LOWER(
            pg_get_functiondef(
                'public.notify_parent_on_dismissal()'::REGPROCEDURE
            )
        )
    ) = 0 OR POSITION(
        'authorization' IN LOWER(
            pg_get_functiondef(
                'public.notify_parent_on_dismissal()'::REGPROCEDURE
            )
        )
    ) > 0 THEN
        RAISE EXCEPTION 'dismissal notification regressed from dedicated-secret auth';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        IF EXISTS (
            SELECT 1 FROM cron.job
            WHERE jobname = 'student-storage-cleanup'
        ) THEN
            RAISE EXCEPTION 'student-storage-cleanup cron job survived rollback';
        END IF;
    END IF;
END;
$$;

NOTIFY pgrst, 'reload schema';

COMMIT;
