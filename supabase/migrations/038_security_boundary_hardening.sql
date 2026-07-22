-- ============================================================
-- 038 — Security boundary hardening
-- ============================================================
-- Close authorization and data-retention gaps found during the pre-production
-- review.  This migration is additive: earlier migrations remain immutable.

-- ── Canonical student storage paths ──────────────────────────
-- Accepted shape: "<lowercase UUID>/<single safe filename>".  Returning NULL
-- instead of casting arbitrary input keeps storage RLS fail-closed.
CREATE FUNCTION public.canonical_storage_student_id(p_name TEXT)
RETURNS UUID
LANGUAGE SQL
IMMUTABLE
PARALLEL SAFE
SET search_path = public, pg_temp
AS $$
    SELECT CASE
        WHEN p_name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[A-Za-z0-9][A-Za-z0-9._-]{0,254}$'
        THEN split_part(p_name, '/', 1)::UUID
        ELSE NULL
    END
$$;

REVOKE EXECUTE ON FUNCTION public.canonical_storage_student_id(TEXT)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.canonical_storage_student_id(TEXT)
    TO authenticated, service_role;

-- ── Tutor assignment start dates ─────────────────────────────
-- A future assignment must not grant access before assigned_from.
CREATE OR REPLACE FUNCTION public.tutor_owns_class(p_class_id UUID)
RETURNS BOOLEAN
LANGUAGE SQL
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM class_tutor_assignments
        WHERE class_id = p_class_id
          AND tutor_id = auth.uid()
          AND assigned_from <= (NOW() AT TIME ZONE 'Asia/Singapore')::DATE
          AND (
                assigned_until IS NULL
                OR assigned_until >= (NOW() AT TIME ZONE 'Asia/Singapore')::DATE
              )
    )
$$;

-- A substitute appointment is authority for one recent session, not a
-- permanent second class assignment. Keep enough history for the bounded
-- offline-sync window, then remove session/roster/attendance visibility.
CREATE FUNCTION public.substitute_covers_session(p_session_id UUID)
RETURNS BOOLEAN
LANGUAGE SQL
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
    SELECT is_tutor() AND EXISTS (
        SELECT 1
        FROM sessions s
        WHERE s.id = p_session_id
          AND s.sub_tutor_id = auth.uid()
          AND s.session_date BETWEEN
                (NOW() AT TIME ZONE 'Asia/Singapore')::DATE - 7
                AND (NOW() AT TIME ZONE 'Asia/Singapore')::DATE
    )
$$;

REVOKE EXECUTE ON FUNCTION public.substitute_covers_session(UUID)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.substitute_covers_session(UUID)
    TO authenticated, service_role;

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
              AND cta.assigned_from <= (NOW() AT TIME ZONE 'Asia/Singapore')::DATE
              AND (
                    cta.assigned_until IS NULL
                    OR cta.assigned_until >= (NOW() AT TIME ZONE 'Asia/Singapore')::DATE
                  )
        )
    );

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

-- Admins may still select/delete a malformed legacy object for cleanup, while
-- every inserted/updated path must be flag-enabled, canonical, and point to an
-- existing student.
DROP POLICY IF EXISTS "student-photos: admin all" ON storage.objects;
CREATE POLICY "student-photos: admin all"
    ON storage.objects FOR ALL TO authenticated
    USING (bucket_id = 'student-photos' AND is_admin())
    WITH CHECK (
        bucket_id = 'student-photos'
        AND is_admin()
        AND is_feature_enabled('student_photos')
        AND canonical_storage_student_id(name) IS NOT NULL
        AND EXISTS (
            SELECT 1 FROM students st
            WHERE st.id = canonical_storage_student_id(name)
        )
    );

DROP POLICY IF EXISTS "student-photos: parent read" ON storage.objects;
-- Parent clients do not consume photos today. Keep Storage object metadata
-- closed; a future UI should receive a server-minted signed URL rather than a
-- broad storage.objects SELECT policy.

-- Every tutor-facing assignment boundary uses the centre's civil date. Using
-- PostgreSQL's UTC CURRENT_DATE would extend an expired assignment until
-- 08:00 Singapore time and could grant a newly scheduled assignment early.
ALTER TABLE class_tutor_assignments
    ALTER COLUMN assigned_from
    SET DEFAULT ((NOW() AT TIME ZONE 'Asia/Singapore')::DATE);

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
              AND e.is_active = TRUE
              AND c.is_active = TRUE
              AND cta.tutor_id = auth.uid()
              AND cta.assigned_from <= (NOW() AT TIME ZONE 'Asia/Singapore')::DATE
              AND (
                    cta.assigned_until IS NULL
                    OR cta.assigned_until >= (NOW() AT TIME ZONE 'Asia/Singapore')::DATE
                  )
              AND (
                    (student_results.subject = 'Math'
                     AND LOWER(BTRIM(c.subject)) LIKE 'math%')
                    OR (student_results.subject = 'English'
                        AND LOWER(BTRIM(c.subject)) LIKE 'eng%')
                  )
        )
    )
    WITH CHECK (
        is_tutor() AND EXISTS (
            SELECT 1
            FROM enrollments e
            JOIN classes c ON c.id = e.class_id
            JOIN class_tutor_assignments cta ON cta.class_id = e.class_id
            WHERE e.student_id = student_results.student_id
              AND e.is_active = TRUE
              AND c.is_active = TRUE
              AND cta.tutor_id = auth.uid()
              AND cta.assigned_from <= (NOW() AT TIME ZONE 'Asia/Singapore')::DATE
              AND (
                    cta.assigned_until IS NULL
                    OR cta.assigned_until >= (NOW() AT TIME ZONE 'Asia/Singapore')::DATE
                  )
              AND (
                    (student_results.subject = 'Math'
                     AND LOWER(BTRIM(c.subject)) LIKE 'math%')
                    OR (student_results.subject = 'English'
                        AND LOWER(BTRIM(c.subject)) LIKE 'eng%')
                  )
        )
    );

UPDATE storage.buckets
SET public = FALSE,
    file_size_limit = 5242880,
    allowed_mime_types = ARRAY['image/jpeg', 'image/png']::TEXT[]
WHERE id = 'student-photos';

-- Existing non-canonical paths cannot safely survive the new invariant: a
-- NOT VALID constraint would still reject every unrelated UPDATE of those
-- rows. Detach them first (the private object remains available to admins for
-- cleanup), then enforce the invariant for the whole table.
UPDATE students
SET avatar_url = NULL
WHERE avatar_url IS NOT NULL
  AND canonical_storage_student_id(avatar_url) IS DISTINCT FROM id;

ALTER TABLE students
    ADD CONSTRAINT students_avatar_url_path_check
        CHECK (
            avatar_url IS NULL
            OR (
                canonical_storage_student_id(avatar_url) IS NOT NULL
                AND canonical_storage_student_id(avatar_url) = id
            )
        );

-- ── Substitute tutor integrity ───────────────────────────────
-- sessions.sub_tutor_id used to accept any auth user, allowing an assigned
-- tutor to delegate attendance access to a parent account.
CREATE FUNCTION public.validate_session_sub_tutor()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NEW.sub_tutor_id IS NOT NULL AND NOT EXISTS (
        SELECT 1
        FROM auth.users u
        JOIN profiles p ON p.id = u.id
        WHERE u.id = NEW.sub_tutor_id
          AND p.role = 'tutor'
    ) THEN
        RAISE EXCEPTION 'invalid substitute tutor'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.validate_session_sub_tutor()
    FROM PUBLIC, anon, authenticated;

CREATE TRIGGER validate_session_sub_tutor
BEFORE INSERT OR UPDATE OF sub_tutor_id ON sessions
FOR EACH ROW EXECUTE FUNCTION public.validate_session_sub_tutor();

DROP POLICY IF EXISTS "substitute_can_read_session" ON sessions;
CREATE POLICY "substitute_can_read_session"
    ON sessions FOR SELECT TO authenticated
    USING (substitute_covers_session(id));

-- ── Attendance must belong to the session's class ────────────
-- SECURITY DEFINER is required because a substitute can see the covered
-- session but does not necessarily have ordinary RLS access to enrollments.
CREATE FUNCTION public.student_is_enrolled_for_session(
    p_session_id UUID,
    p_student_id UUID
)
RETURNS BOOLEAN
LANGUAGE SQL
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM sessions s
        JOIN enrollments e
          ON e.class_id = s.class_id
         AND e.student_id = p_student_id
        WHERE s.id = p_session_id
          AND (is_admin() OR (
                is_tutor()
                AND (
                    tutor_owns_class(s.class_id)
                    OR substitute_covers_session(s.id)
                )
              ))
          AND (e.enrolled_at AT TIME ZONE 'Asia/Singapore')::DATE <= s.session_date
          AND (
                e.unenrolled_at IS NULL
                OR (e.unenrolled_at AT TIME ZONE 'Asia/Singapore')::DATE >= s.session_date
              )
    )
$$;

REVOKE EXECUTE ON FUNCTION public.student_is_enrolled_for_session(UUID, UUID)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.student_is_enrolled_for_session(UUID, UUID)
    TO authenticated, service_role;

-- A current attendance row can store only its latest client mutation ID. Keep
-- replaced IDs in an RLS-hidden receipt ledger so a delayed retry of an older
-- accepted write cannot overwrite a newer correction.
CREATE TABLE public.attendance_mutation_receipts (
    -- New IDs are bounded by the attendance trigger. This ledger intentionally
    -- accepts any legacy ID already present so hardening an old row cannot be
    -- blocked merely because its previous client violated today's limit.
    mutation_id TEXT PRIMARY KEY,
    session_id UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    actor_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    accepted_at TIMESTAMPTZ NOT NULL
);

ALTER TABLE public.attendance_mutation_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.attendance_mutation_receipts
    FROM PUBLIC, anon, authenticated;
GRANT SELECT, DELETE ON public.attendance_mutation_receipts TO service_role;

-- Attendance facts are audit evidence. RLS decides which class a caller may
-- operate, while this universal trigger enforces row integrity for admins,
-- tutors, substitutes and direct Data API calls alike.
CREATE FUNCTION public.enforce_attendance_write_integrity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_session_date DATE;
    v_class_id UUID;
    v_class_active BOOLEAN;
    v_study_space BOOLEAN;
    v_student_active BOOLEAN;
    v_historical BOOLEAN := COALESCE(
        current_setting('app.retrospective_attendance_write', TRUE), 'off'
    ) = 'on';
BEGIN
    IF COALESCE(current_setting('app.suppress_audit', TRUE), 'off') = 'on' THEN
        RETURN NEW;
    END IF;

    IF TG_OP = 'UPDATE' AND (
        NEW.id IS DISTINCT FROM OLD.id
        OR NEW.session_id IS DISTINCT FROM OLD.session_id
        OR NEW.student_id IS DISTINCT FROM OLD.student_id
    ) THEN
        RAISE EXCEPTION 'attendance identity fields are immutable'
            USING ERRCODE = '23514';
    END IF;

    NEW.notes := NULLIF(BTRIM(NEW.notes), '');
    NEW.late_reason := NULLIF(BTRIM(NEW.late_reason), '');
    IF NEW.status <> 'late' THEN NEW.late_reason := NULL; END IF;

    IF NEW.notes IS NOT NULL AND char_length(NEW.notes) > 4000 THEN
        RAISE EXCEPTION 'attendance notes are too long' USING ERRCODE = '22001';
    END IF;
    IF NEW.late_reason IS NOT NULL AND char_length(NEW.late_reason) > 1000 THEN
        RAISE EXCEPTION 'late reason is too long' USING ERRCODE = '22001';
    END IF;
    IF COALESCE(NEW.late_reason, '') ~* '\m[STFGM][0-9]{7}[A-Z]\M' THEN
        RAISE EXCEPTION 'Late reason appears to contain an NRIC/FIN.'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.client_mutation_id IS NOT NULL THEN
        NEW.client_mutation_id := BTRIM(NEW.client_mutation_id);
    END IF;
    IF auth.uid() IS NOT NULL AND (
        NEW.client_mutation_id IS NULL
        OR NEW.client_mutation_id = ''
        OR char_length(NEW.client_mutation_id) > 128
    ) THEN
        RAISE EXCEPTION 'invalid attendance mutation identifier'
            USING ERRCODE = '23514';
    END IF;
    IF NEW.client_mutation_id IS NOT NULL
       AND (TG_OP = 'INSERT'
            OR NEW.client_mutation_id IS DISTINCT FROM OLD.client_mutation_id)
       AND EXISTS (
            SELECT 1 FROM attendance_mutation_receipts receipt
            WHERE receipt.mutation_id = NEW.client_mutation_id
       ) THEN
        RAISE EXCEPTION 'attendance mutation identifier collision'
            USING ERRCODE = '23505';
    END IF;

    IF auth.uid() IS NOT NULL THEN NEW.marked_by := auth.uid(); END IF;
    NEW.marked_at := clock_timestamp();

    SELECT s.session_date, s.class_id, c.is_active, c.is_study_space,
           st.is_active
    INTO v_session_date, v_class_id, v_class_active, v_study_space,
         v_student_active
    FROM sessions s
    JOIN classes c ON c.id = s.class_id
    JOIN students st ON st.id = NEW.student_id
    WHERE s.id = NEW.session_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'attendance session or student does not exist'
            USING ERRCODE = '23503';
    END IF;

    IF v_study_space THEN
        IF NOT v_class_active
           OR NOT v_student_active
           OR NEW.status NOT IN ('present', 'excused')
           OR NOT is_feature_enabled('study_space_tracking')
           OR (auth.uid() IS NOT NULL AND NOT is_admin()) THEN
            RAISE EXCEPTION 'invalid Study Space attendance'
                USING ERRCODE = '23514';
        END IF;
    ELSIF NOT EXISTS (
        SELECT 1
        FROM enrollments e
        WHERE e.class_id = v_class_id
          AND e.student_id = NEW.student_id
          AND (e.enrolled_at AT TIME ZONE 'Asia/Singapore')::DATE
                <= v_session_date
          AND (
                e.unenrolled_at IS NULL
                OR (e.unenrolled_at AT TIME ZONE 'Asia/Singapore')::DATE
                    >= v_session_date
              )
    ) THEN
        RAISE EXCEPTION 'student was not enrolled for this session'
            USING ERRCODE = '23514';
    ELSIF NOT v_historical AND (NOT v_class_active OR NOT v_student_active) THEN
        RAISE EXCEPTION 'inactive class or student cannot receive current attendance'
            USING ERRCODE = '23514';
    END IF;

    RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.enforce_attendance_write_integrity()
    FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS enforce_attendance_write_integrity
    ON attendance_records;
CREATE TRIGGER enforce_attendance_write_integrity
BEFORE INSERT OR UPDATE ON attendance_records
FOR EACH ROW EXECUTE FUNCTION public.enforce_attendance_write_integrity();

CREATE FUNCTION public.archive_attendance_mutation_receipt()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF COALESCE(current_setting('app.suppress_audit', TRUE), 'off') = 'on'
       OR OLD.client_mutation_id IS NULL
       OR OLD.client_mutation_id IS NOT DISTINCT FROM NEW.client_mutation_id THEN
        RETURN NEW;
    END IF;

    INSERT INTO attendance_mutation_receipts (
        mutation_id, session_id, student_id, actor_id, accepted_at
    ) VALUES (
        OLD.client_mutation_id, OLD.session_id, OLD.student_id,
        OLD.marked_by, OLD.marked_at
    );
    RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.archive_attendance_mutation_receipt()
    FROM PUBLIC, anon, authenticated;

CREATE TRIGGER archive_attendance_mutation_receipt
AFTER UPDATE OF client_mutation_id ON attendance_records
FOR EACH ROW EXECUTE FUNCTION public.archive_attendance_mutation_receipt();

ALTER TABLE attendance_records
    ADD CONSTRAINT attendance_records_notes_length_check
        CHECK (notes IS NULL OR char_length(notes) <= 4000) NOT VALID,
    ADD CONSTRAINT attendance_records_late_reason_check
        CHECK (
            late_reason IS NULL
            OR (
                status = 'late'
                AND char_length(BTRIM(late_reason)) BETWEEN 1 AND 1000
            )
        ) NOT VALID,
    ADD CONSTRAINT attendance_records_mutation_id_check
        CHECK (
            client_mutation_id IS NULL
            OR char_length(BTRIM(client_mutation_id)) BETWEEN 1 AND 128
        ) NOT VALID;

-- Ordinary Data API writes are current-session operations. Historical edits
-- and offline replay each enter through a dedicated RPC that sets a tx-local
-- flag; ended sessions remain immutable even to offline replay. Erasure uses
-- suppress_audit so cascades cannot be blocked by an ended attendance row.
CREATE OR REPLACE FUNCTION public.check_session_not_ended()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    v_session_id UUID := COALESCE(NEW.session_id, OLD.session_id);
    v_session_date DATE;
    v_ended_at TIMESTAMPTZ;
    v_today DATE := (NOW() AT TIME ZONE 'Asia/Singapore')::DATE;
    v_retrospective BOOLEAN := COALESCE(
        current_setting('app.retrospective_attendance_write', TRUE), 'off'
    ) = 'on';
    v_offline BOOLEAN := COALESCE(
        current_setting('app.attendance_offline_sync', TRUE), 'off'
    ) = 'on';
BEGIN
    IF COALESCE(current_setting('app.suppress_audit', TRUE), 'off') = 'on' THEN
        RETURN COALESCE(NEW, OLD);
    END IF;
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'attendance rows cannot be deleted directly'
            USING ERRCODE = '42501';
    END IF;

    SELECT session_date, ended_at INTO v_session_date, v_ended_at
    FROM sessions WHERE id = v_session_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'attendance session does not exist'
            USING ERRCODE = '23503';
    END IF;
    IF v_ended_at IS NOT NULL AND NOT v_retrospective THEN
        RAISE EXCEPTION 'Cannot modify attendance for ended session %', v_session_id
            USING ERRCODE = 'TA001';
    END IF;
    IF v_session_date > v_today THEN
        RAISE EXCEPTION 'future attendance is not allowed'
            USING ERRCODE = '23514';
    END IF;
    IF v_session_date < v_today AND NOT v_retrospective THEN
        IF NOT v_offline OR v_session_date < v_today - 7 THEN
            RAISE EXCEPTION 'historical attendance requires the dedicated workflow'
                USING ERRCODE = '42501';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.check_retrospective_session_changes()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    v_today DATE := (NOW() AT TIME ZONE 'Asia/Singapore')::DATE;
    v_historical_update BOOLEAN := COALESCE(
        current_setting('app.retrospective_session_update', TRUE), 'off'
    ) = 'on';
BEGIN
    IF COALESCE(current_setting('app.suppress_audit', TRUE), 'off') = 'on' THEN
        RETURN COALESCE(NEW, OLD);
    END IF;
    IF TG_OP = 'DELETE' AND auth.uid() IS NOT NULL THEN
        RAISE EXCEPTION 'sessions cannot be deleted directly'
            USING ERRCODE = '42501';
    END IF;
    IF TG_OP = 'INSERT' AND NEW.session_date < v_today
       AND COALESCE(current_setting('app.retrospective_session_create', TRUE), 'off') <> 'on' THEN
        RAISE EXCEPTION 'past sessions must be created through create_retrospective_session';
    END IF;
    IF TG_OP = 'UPDATE'
       AND (OLD.session_date < v_today OR NEW.session_date < v_today)
       AND NOT v_historical_update THEN
        RAISE EXCEPTION 'past sessions must be updated through update_retrospective_session';
    END IF;
    IF TG_OP = 'UPDATE' AND OLD.session_date < v_today
       AND (NEW.class_id IS DISTINCT FROM OLD.class_id
            OR NEW.session_date IS DISTINCT FROM OLD.session_date) THEN
        RAISE EXCEPTION 'historical session class and date are immutable';
    END IF;
    IF TG_OP = 'UPDATE'
       AND auth.uid() IS NOT NULL
       AND (
            NEW.id IS DISTINCT FROM OLD.id
            OR NEW.class_id IS DISTINCT FROM OLD.class_id
            OR NEW.session_date IS DISTINCT FROM OLD.session_date
            OR NEW.created_by IS DISTINCT FROM OLD.created_by
            OR NEW.created_at IS DISTINCT FROM OLD.created_at
       ) THEN
        RAISE EXCEPTION 'session identity fields are immutable'
            USING ERRCODE = '23514';
    END IF;
    IF TG_OP = 'UPDATE'
       AND (NEW.class_id IS DISTINCT FROM OLD.class_id
            OR NEW.session_date IS DISTINCT FROM OLD.session_date)
       AND EXISTS (
            SELECT 1 FROM attendance_records ar
            WHERE ar.session_id = OLD.id
       ) THEN
        RAISE EXCEPTION 'sessions with attendance cannot change class or date';
    END IF;
    IF TG_OP = 'UPDATE'
       AND OLD.ended_at IS NOT NULL AND NEW.ended_at IS NULL THEN
        RAISE EXCEPTION 'ended sessions cannot be reopened';
    END IF;
    IF TG_OP = 'DELETE' AND OLD.session_date < v_today THEN
        RAISE EXCEPTION 'historical sessions cannot be deleted';
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$;

-- The historical update API is the only path that receives the trigger's
-- transaction-local capability. Its authorization and feature checks are
-- repeated here so direct table writes cannot bypass a disabled workflow.
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
    IF NOT (
        is_admin()
        OR (is_tutor() AND tutor_owns_class(v_session.class_id))
    ) THEN
        RAISE EXCEPTION 'not authorized';
    END IF;
    IF notes IS NOT NULL AND BTRIM(notes) <> ''
       AND NOT is_feature_enabled('session_notes') THEN
        RAISE EXCEPTION 'session notes are disabled';
    END IF;
    IF sub_tutor_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM profiles p
        WHERE p.id = sub_tutor_id AND p.role = 'tutor'
    ) THEN
        RAISE EXCEPTION 'invalid substitute tutor';
    END IF;

    PERFORM set_config('app.retrospective_session_update', 'on', TRUE);
    PERFORM set_config('app.session_note_write', 'on', TRUE);
    UPDATE sessions s
    SET topic = NULLIF(BTRIM(update_retrospective_session.topic), ''),
        notes = NULLIF(BTRIM(update_retrospective_session.notes), ''),
        sub_tutor_id = update_retrospective_session.sub_tutor_id
    WHERE s.id = update_retrospective_session.session_id
    RETURNING s.* INTO v_session;
    PERFORM set_config('app.session_note_write', 'off', TRUE);
    PERFORM set_config('app.retrospective_session_update', 'off', TRUE);

    RETURN v_session;
END;
$$;

CREATE FUNCTION public.attendance_mutation_is_replay(
    p_mutation_id TEXT,
    p_session_id UUID,
    p_student_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
    v_session_id UUID;
    v_student_id UUID;
    v_actor_id UUID;
BEGIN
    -- This helper is executable only as an internal step of sync_attendance.
    -- A separate PostgREST call receives a new transaction and cannot inherit
    -- the tx-local capability, so mutation receipts are not a probing API.
    IF COALESCE(
        current_setting('app.attendance_offline_sync', TRUE), 'off'
    ) <> 'on' THEN
        RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
    END IF;

    SELECT mutation.session_id, mutation.student_id, mutation.actor_id
    INTO v_session_id, v_student_id, v_actor_id
    FROM (
        SELECT ar.session_id, ar.student_id, ar.marked_by AS actor_id
        FROM attendance_records ar
        WHERE ar.client_mutation_id = p_mutation_id
        UNION ALL
        SELECT receipt.session_id, receipt.student_id, receipt.actor_id
        FROM attendance_mutation_receipts receipt
        WHERE receipt.mutation_id = p_mutation_id
    ) mutation
    LIMIT 1;

    IF NOT FOUND THEN RETURN FALSE; END IF;
    IF v_session_id = p_session_id
       AND v_student_id = p_student_id
       AND v_actor_id IS NOT DISTINCT FROM auth.uid() THEN
        RETURN TRUE;
    END IF;

    RAISE EXCEPTION 'attendance mutation identifier collision'
        USING ERRCODE = '23505';
END;
$$;

REVOKE EXECUTE ON FUNCTION public.attendance_mutation_is_replay(
    TEXT, UUID, UUID
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.attendance_mutation_is_replay(
    TEXT, UUID, UUID
) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.sync_attendance(records JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    rec JSONB;
    v_id UUID;
    v_mutation_id TEXT;
    synced INTEGER := 0;
    skipped INTEGER := 0;
    blocked INTEGER := 0;
BEGIN
    IF jsonb_typeof(records) IS DISTINCT FROM 'array'
       OR jsonb_array_length(records) > 500 THEN
        RAISE EXCEPTION 'invalid attendance sync batch' USING ERRCODE = '22023';
    END IF;

    PERFORM set_config('app.attendance_offline_sync', 'on', TRUE);
    FOR rec IN SELECT * FROM jsonb_array_elements(records)
    LOOP
        v_mutation_id := NULLIF(BTRIM(rec->>'client_mutation_id'), '');
        IF v_mutation_id IS NULL OR char_length(v_mutation_id) > 128 THEN
            RAISE EXCEPTION 'invalid attendance mutation identifier'
                USING ERRCODE = '23514';
        END IF;
        -- Serialize identical mutation IDs so two concurrent retries cannot
        -- both pass the replay check before either write becomes visible.
        PERFORM pg_advisory_xact_lock(hashtextextended(v_mutation_id, 1));
        IF attendance_mutation_is_replay(
            v_mutation_id,
            (rec->>'session_id')::UUID,
            (rec->>'student_id')::UUID
        ) THEN
            skipped := skipped + 1;
            CONTINUE;
        END IF;

        BEGIN
            INSERT INTO attendance_records (
                session_id, student_id, status, notes,
                client_mutation_id, marked_by, marked_at
            ) VALUES (
                (rec->>'session_id')::UUID,
                (rec->>'student_id')::UUID,
                rec->>'status',
                rec->>'notes',
                v_mutation_id,
                auth.uid(),
                clock_timestamp()
            )
            ON CONFLICT (session_id, student_id) DO UPDATE
            SET status = EXCLUDED.status,
                notes = EXCLUDED.notes,
                marked_by = EXCLUDED.marked_by,
                marked_at = EXCLUDED.marked_at,
                client_mutation_id = EXCLUDED.client_mutation_id
            RETURNING id INTO v_id;
            synced := synced + 1;
        EXCEPTION
            WHEN SQLSTATE 'TA001' THEN
                blocked := blocked + 1;
        END;
    END LOOP;
    PERFORM set_config('app.attendance_offline_sync', 'off', TRUE);

    RETURN jsonb_build_object(
        'synced', synced,
        'skipped', skipped,
        'blocked_ended_session', blocked
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.sync_attendance(JSONB)
    TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.sync_attendance(JSONB) FROM PUBLIC, anon;

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
        AND student_is_enrolled_for_session(
            attendance_records.session_id,
            attendance_records.student_id
        )
    )
    WITH CHECK (
        is_tutor()
        AND EXISTS (
            SELECT 1 FROM sessions s
            WHERE s.id = attendance_records.session_id
              AND tutor_owns_class(s.class_id)
        )
        AND student_is_enrolled_for_session(
            attendance_records.session_id,
            attendance_records.student_id
        )
    );

DROP POLICY IF EXISTS "substitute_can_mark_attendance" ON attendance_records;
CREATE POLICY "substitute_can_mark_attendance"
    ON attendance_records FOR ALL TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM sessions s
            WHERE s.id = attendance_records.session_id
              AND substitute_covers_session(s.id)
        )
        AND student_is_enrolled_for_session(
            attendance_records.session_id,
            attendance_records.student_id
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM sessions s
            WHERE s.id = attendance_records.session_id
              AND substitute_covers_session(s.id)
        )
        AND student_is_enrolled_for_session(
            attendance_records.session_id,
            attendance_records.student_id
        )
    );

-- Staff class discovery is shaped so a substitute sees only classes attached
-- to a currently covered session. Explicit capabilities keep recent roster
-- visibility from being mistaken for permission to operate today's session.
CREATE FUNCTION public.get_my_classes()
RETURNS TABLE (
    id UUID,
    name TEXT,
    subject TEXT,
    level TEXT,
    schedule_day TEXT,
    schedule_time TIME,
    duration_minutes INTEGER,
    is_active BOOLEAN,
    recurrence_rule TEXT,
    recurrence_end_date DATE,
    is_study_space BOOLEAN,
    can_manage_sessions BOOLEAN,
    can_operate_today_session BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
    v_today DATE := (NOW() AT TIME ZONE 'Asia/Singapore')::DATE;
BEGIN
    IF NOT is_admin() AND NOT is_tutor() THEN
        RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT c.id, c.name, c.subject, c.level, c.schedule_day,
           c.schedule_time, c.duration_minutes, c.is_active,
           c.recurrence_rule, c.recurrence_end_date, c.is_study_space,
           (is_admin() OR tutor_owns_class(c.id)) AS can_manage_sessions,
           (
                is_admin()
                OR tutor_owns_class(c.id)
                OR EXISTS (
                    SELECT 1 FROM sessions current_session
                    WHERE current_session.class_id = c.id
                      AND current_session.session_date = v_today
                      AND substitute_covers_session(current_session.id)
                )
           ) AS can_operate_today_session
    FROM classes c
    WHERE c.is_active
      AND NOT c.is_study_space
      AND (
            is_admin()
            OR tutor_owns_class(c.id)
            OR EXISTS (
                SELECT 1 FROM sessions s
                WHERE s.class_id = c.id
                  AND substitute_covers_session(s.id)
            )
          )
    ORDER BY c.name;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_my_classes()
    FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_my_classes() TO authenticated;

-- Session creation/lifecycle is a server-time capability. A substitute can be
-- assigned only to an existing session, so this RPC returns that covered row
-- without granting class-wide INSERT/UPDATE. Assigned tutors/admins may create
-- today's row atomically. Historical sessions keep their dedicated workflow.
CREATE FUNCTION public.get_or_create_today_session(p_class_id UUID)
RETURNS sessions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_session sessions%ROWTYPE;
    v_today DATE := (clock_timestamp() AT TIME ZONE 'Asia/Singapore')::DATE;
BEGIN
    IF auth.uid() IS NULL OR (NOT is_admin() AND NOT is_tutor()) THEN
        RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
    END IF;

    SELECT s.* INTO v_session
    FROM sessions s
    WHERE s.class_id = p_class_id AND s.session_date = v_today
    FOR UPDATE;

    IF FOUND THEN
        IF NOT (
            is_admin()
            OR (is_tutor() AND tutor_owns_class(v_session.class_id))
            OR substitute_covers_session(v_session.id)
        ) THEN
            RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
        END IF;
        RETURN v_session;
    END IF;

    -- A substitute appointment refers to a pre-existing session and cannot be
    -- used to mint a new class session. Only the current owner/admin may create.
    IF NOT EXISTS (
        SELECT 1 FROM classes c
        WHERE c.id = p_class_id
          AND c.is_active
          AND (NOT c.is_study_space OR (
                is_admin() AND is_feature_enabled('study_space_tracking')
              ))
          AND (is_admin() OR (is_tutor() AND tutor_owns_class(c.id)))
    ) THEN
        RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
    END IF;

    PERFORM set_config('app.session_create_write', 'on', TRUE);
    INSERT INTO sessions (class_id, session_date, created_by)
    VALUES (p_class_id, v_today, auth.uid())
    ON CONFLICT (class_id, session_date) DO NOTHING;
    PERFORM set_config('app.session_create_write', 'off', TRUE);

    SELECT s.* INTO v_session
    FROM sessions s
    WHERE s.class_id = p_class_id AND s.session_date = v_today
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'session could not be created';
    END IF;
    RETURN v_session;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_or_create_today_session(UUID)
    FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_or_create_today_session(UUID)
    TO authenticated;

-- Authenticated callers cannot forge lifecycle timestamps through the base
-- table. The narrow RPC below supplies a transaction-local capability and the
-- server clock. This also makes the existing no-reopen rule explicit in the API.
CREATE FUNCTION public.enforce_session_lifecycle_boundary()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    v_current_create BOOLEAN := COALESCE(
        current_setting('app.session_create_write', TRUE), 'off'
    ) = 'on';
    v_retrospective_create BOOLEAN := COALESCE(
        current_setting('app.retrospective_session_create', TRUE), 'off'
    ) = 'on';
BEGIN
    IF auth.uid() IS NOT NULL THEN
        IF TG_OP = 'INSERT' AND NOT v_current_create
           AND NOT v_retrospective_create THEN
            RAISE EXCEPTION 'session creation requires the dedicated workflow'
                USING ERRCODE = '42501';
        END IF;
        IF TG_OP = 'INSERT' AND v_current_create
           AND (NEW.started_at IS NOT NULL OR NEW.ended_at IS NOT NULL) THEN
            RAISE EXCEPTION 'session lifecycle timestamps are server-managed'
                USING ERRCODE = '42501';
        END IF;
        IF TG_OP = 'UPDATE'
           AND COALESCE(
                current_setting('app.session_lifecycle_write', TRUE), 'off'
           ) <> 'on'
           AND (
                NEW.started_at IS DISTINCT FROM OLD.started_at
                OR NEW.ended_at IS DISTINCT FROM OLD.ended_at
           ) THEN
            RAISE EXCEPTION 'session lifecycle requires the dedicated workflow'
                USING ERRCODE = '42501';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.enforce_session_lifecycle_boundary()
    FROM PUBLIC, anon, authenticated;
CREATE TRIGGER enforce_session_lifecycle_boundary
BEFORE INSERT OR UPDATE ON sessions
FOR EACH ROW EXECUTE FUNCTION public.enforce_session_lifecycle_boundary();

CREATE FUNCTION public.set_session_lifecycle(
    p_session_id UUID,
    p_action TEXT
)
RETURNS sessions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_session sessions%ROWTYPE;
    v_action TEXT := LOWER(BTRIM(COALESCE(p_action, '')));
    v_today DATE := (clock_timestamp() AT TIME ZONE 'Asia/Singapore')::DATE;
    v_class_active BOOLEAN;
    v_is_study_space BOOLEAN;
BEGIN
    IF auth.uid() IS NULL OR (NOT is_admin() AND NOT is_tutor()) THEN
        RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
    END IF;

    SELECT s.* INTO v_session
    FROM sessions s
    WHERE s.id = p_session_id
    FOR UPDATE;
    IF NOT FOUND OR v_session.session_date <> v_today THEN
        RAISE EXCEPTION 'session is not eligible for lifecycle changes'
            USING ERRCODE = '42501';
    END IF;
    SELECT c.is_active, c.is_study_space
    INTO v_class_active, v_is_study_space
    FROM classes c WHERE c.id = v_session.class_id;
    IF NOT FOUND OR NOT v_class_active THEN
        RAISE EXCEPTION 'session is not eligible for lifecycle changes'
            USING ERRCODE = '42501';
    END IF;
    IF v_is_study_space AND NOT (
        is_admin() AND is_feature_enabled('study_space_tracking')
    ) THEN
        RAISE EXCEPTION 'session is not eligible for lifecycle changes'
            USING ERRCODE = '42501';
    END IF;
    IF NOT (
        is_admin()
        OR (is_tutor() AND tutor_owns_class(v_session.class_id))
        OR substitute_covers_session(v_session.id)
    ) THEN
        RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
    END IF;

    IF v_action = 'start' THEN
        IF v_session.ended_at IS NOT NULL THEN
            RAISE EXCEPTION 'ended sessions cannot be reopened'
                USING ERRCODE = '42501';
        END IF;
        IF v_session.started_at IS NULL THEN
            PERFORM set_config('app.session_lifecycle_write', 'on', TRUE);
            UPDATE sessions s SET started_at = clock_timestamp()
            WHERE s.id = p_session_id RETURNING s.* INTO v_session;
            PERFORM set_config('app.session_lifecycle_write', 'off', TRUE);
        END IF;
    ELSIF v_action = 'end' THEN
        IF v_session.started_at IS NULL THEN
            RAISE EXCEPTION 'session has not started' USING ERRCODE = '23514';
        END IF;
        IF v_session.ended_at IS NULL THEN
            PERFORM set_config('app.session_lifecycle_write', 'on', TRUE);
            UPDATE sessions s SET ended_at = clock_timestamp()
            WHERE s.id = p_session_id RETURNING s.* INTO v_session;
            PERFORM set_config('app.session_lifecycle_write', 'off', TRUE);
        END IF;
    ELSE
        RAISE EXCEPTION 'invalid lifecycle action' USING ERRCODE = '22023';
    END IF;

    RETURN v_session;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.set_session_lifecycle(UUID, TEXT)
    FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.set_session_lifecycle(UUID, TEXT)
    TO authenticated;

-- Covered substitutes also need the notes control shown on the shared roster.
-- Keep this as a shaped current-session write rather than broad session UPDATE.
CREATE FUNCTION public.update_session_note(
    p_session_id UUID,
    p_notes TEXT
)
RETURNS sessions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_session sessions%ROWTYPE;
    v_notes TEXT := NULLIF(BTRIM(p_notes), '');
    v_today DATE := (clock_timestamp() AT TIME ZONE 'Asia/Singapore')::DATE;
BEGIN
    IF auth.uid() IS NULL OR NOT is_feature_enabled('session_notes') THEN
        RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
    END IF;
    IF v_notes IS NOT NULL AND (
        char_length(v_notes) > 4000
        OR v_notes ~* '\m[STFGM][0-9]{7}[A-Z]\M'
    ) THEN
        RAISE EXCEPTION 'invalid session note' USING ERRCODE = '23514';
    END IF;

    SELECT s.* INTO v_session
    FROM sessions s
    WHERE s.id = p_session_id
    FOR UPDATE;
    IF NOT FOUND OR v_session.session_date <> v_today
       OR v_session.ended_at IS NOT NULL
       OR NOT (
            is_admin()
            OR (is_tutor() AND tutor_owns_class(v_session.class_id))
            OR substitute_covers_session(v_session.id)
       ) THEN
        RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
    END IF;

    PERFORM set_config('app.session_note_write', 'on', TRUE);
    UPDATE sessions s SET notes = v_notes
    WHERE s.id = p_session_id RETURNING s.* INTO v_session;
    PERFORM set_config('app.session_note_write', 'off', TRUE);
    RETURN v_session;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.update_session_note(UUID, TEXT)
    FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.update_session_note(UUID, TEXT)
    TO authenticated;

-- SECURITY INVOKER made the legacy roster silently empty for substitutes,
-- because they intentionally have no broad students/enrollments table policy.
-- Authorize the session first, then return only the established roster shape.
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
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM sessions s
        WHERE s.id = p_session_id
          AND (
                is_admin()
                OR (is_tutor() AND tutor_owns_class(s.class_id))
                OR substitute_covers_session(s.id)
              )
    ) THEN
        RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT st.id, st.full_name, ar.id, ar.status, ar.marked_at,
           ar.notes, ar.late_reason, st.avatar_url
    FROM sessions se
    JOIN enrollments e
      ON e.class_id = se.class_id
     AND (e.enrolled_at AT TIME ZONE 'Asia/Singapore')::DATE <= se.session_date
     AND (
            e.unenrolled_at IS NULL
            OR (e.unenrolled_at AT TIME ZONE 'Asia/Singapore')::DATE
                >= se.session_date
         )
    JOIN students st ON st.id = e.student_id AND st.is_active
    LEFT JOIN attendance_records ar
      ON ar.session_id = se.id AND ar.student_id = st.id
    WHERE se.id = p_session_id
    ORDER BY st.full_name;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_session_roster(UUID)
    FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_session_roster(UUID) TO authenticated;

-- Migration 037's tutor visibility check accepted enrollment in any class.
-- Bind the student to the retrospective session's class instead.
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
    -- Bind every caller, including admins, to an enrollment that covered the
    -- historical session date. Current is_active state is not a valid proxy:
    -- departed students may legitimately need a correction, while students
    -- enrolled only later must never be added to an earlier class record.
    IF NOT student_is_enrolled_for_session(
        mark_retrospective_attendance.session_id,
        mark_retrospective_attendance.student_id
    ) THEN
        RAISE EXCEPTION 'student was not enrolled for this session';
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

-- ── One DB-managed superadmin authority ──────────────────────
-- App environment email checks and the legacy wipe's hard-coded email could
-- drift apart. Bind privileged capabilities to an immutable auth user UUID in
-- the database and make both web gates and destructive RPCs consult it.
CREATE TABLE public.security_principals (
    capability  TEXT NOT NULL CHECK (capability IN ('superadmin')),
    user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    assigned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (capability, user_id),
    UNIQUE (capability)
);

ALTER TABLE public.security_principals ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.security_principals FROM PUBLIC, anon, authenticated;

-- Production already uses this identity. A fresh local reset has no auth users
-- until seed.sql runs, so seed.sql installs its deterministic local principal.
INSERT INTO public.security_principals (capability, user_id)
SELECT 'superadmin', u.id
FROM auth.users u
JOIN profiles p ON p.id = u.id AND p.role = 'admin'
WHERE LOWER(u.email) = 'edmund@thegoodcompanysg.dev'
ON CONFLICT (capability) DO NOTHING;

CREATE FUNCTION public.is_superadmin()
RETURNS BOOLEAN
LANGUAGE SQL
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
    SELECT is_admin() AND EXISTS (
        SELECT 1
        FROM security_principals sp
        WHERE sp.capability = 'superadmin'
          AND sp.user_id = auth.uid()
    )
$$;

REVOKE EXECUTE ON FUNCTION public.is_superadmin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_superadmin() TO authenticated, service_role;

-- RLS previously allowed every user to UPDATE their own profile row, including
-- its role, and allowed ordinary admins to update every profile. Enforce role
-- transitions below RLS so a direct PostgREST request cannot self-promote or
-- bypass the superadmin-only admin-management flow. The service role remains
-- available to the trusted invite action. The active principal must be rotated
-- in security_principals before that account can be demoted.
CREATE FUNCTION public.enforce_profile_role_boundary()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NEW.role IS NOT DISTINCT FROM OLD.role THEN
        RETURN NEW;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM security_principals sp
        WHERE sp.capability = 'superadmin'
          AND sp.user_id = OLD.id
    ) AND NEW.role <> 'admin' THEN
        RAISE EXCEPTION 'rotate the superadmin principal before demotion'
            USING ERRCODE = '42501';
    END IF;

    -- auth.uid() is NULL for migration/maintenance and service-role requests;
    -- authenticated callers must be the database-managed principal.
    IF auth.uid() IS NOT NULL AND NOT is_superadmin() THEN
        RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
    END IF;

    RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.enforce_profile_role_boundary()
    FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS enforce_profile_role_boundary ON profiles;
CREATE TRIGGER enforce_profile_role_boundary
BEFORE UPDATE OF role ON profiles
FOR EACH ROW EXECUTE FUNCTION public.enforce_profile_role_boundary();

-- Feature flags control server and RLS behavior. An ordinary admin must not be
-- able to bypass the superadmin-only application gate through the Data API.
DROP POLICY IF EXISTS "feature_flags: admin writes" ON feature_flags;
CREATE POLICY "feature_flags: superadmin writes"
    ON feature_flags FOR ALL TO authenticated
    USING (is_superadmin())
    WITH CHECK (is_superadmin());

-- Browser uploads use a server-minted, path-scoped Storage token instead of a
-- blanket parent INSERT policy. The intent binds that random path to the
-- authenticated parent, child, size and MIME type, and gives the cleanup
-- worker enough durable state to delete abandoned uploads after the signed
-- token's documented two-hour lifetime.
CREATE TABLE public.result_slip_upload_intents (
    path          TEXT PRIMARY KEY,
    -- Preserve the exact object path as a cleanup tombstone if either identity
    -- is deleted while Storage's signed upload token is still alive.
    student_id    UUID REFERENCES students(id) ON DELETE SET NULL,
    actor_id      UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    expected_size BIGINT NOT NULL CHECK (
        expected_size BETWEEN 1 AND 10485760
    ),
    expected_mime TEXT NOT NULL CHECK (
        expected_mime IN ('application/pdf', 'image/jpeg', 'image/png')
    ),
    finalized_result_id UUID REFERENCES result_slips(id) ON DELETE SET NULL,
    finalized_at TIMESTAMPTZ,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at    TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '2 hours 15 minutes'),
    cleanup_claimed_at TIMESTAMPTZ,
    CHECK (char_length(path) <= 292),
    CHECK (canonical_storage_student_id(path) = student_id),
    CHECK (finalized_result_id IS NULL OR finalized_at IS NOT NULL)
);

CREATE INDEX result_slip_upload_intents_expiry_idx
    ON public.result_slip_upload_intents (expires_at);

ALTER TABLE public.result_slip_upload_intents ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.result_slip_upload_intents
    FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.result_slip_upload_intents
    TO service_role;

CREATE FUNCTION public.reserve_result_slip_upload(
    p_actor_id UUID,
    p_student_id UUID,
    p_path TEXT,
    p_expected_size BIGINT,
    p_expected_mime TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_recent BIGINT;
BEGIN
    IF NOT is_feature_enabled('parent_portal')
       OR canonical_storage_student_id(p_path) IS DISTINCT FROM p_student_id
       OR p_expected_size NOT BETWEEN 1 AND 10485760
       OR p_expected_mime NOT IN (
            'application/pdf', 'image/jpeg', 'image/png'
       )
       OR NOT EXISTS (
            SELECT 1
            FROM profiles p
            JOIN parent_student_links psl ON psl.parent_id = p.id
            WHERE p.id = p_actor_id
              AND p.role = 'parent'
              AND psl.student_id = p_student_id
       ) THEN
        RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
    END IF;

    -- Serialize the rolling quota so parallel requests cannot race the count.
    PERFORM pg_advisory_xact_lock(hashtextextended(p_actor_id::TEXT, 0));
    DELETE FROM rate_limit_events
    WHERE actor_id = p_actor_id
      AND action = 'result_slip_upload'
      AND created_at < NOW() - INTERVAL '7 days';

    SELECT COUNT(*) INTO v_recent
    FROM rate_limit_events
    WHERE actor_id = p_actor_id
      AND action = 'result_slip_upload'
      AND created_at >= NOW() - INTERVAL '24 hours';

    IF v_recent >= 10 THEN
        RAISE EXCEPTION 'result-slip upload limit reached'
            USING ERRCODE = '54000';
    END IF;

    INSERT INTO rate_limit_events (actor_id, action)
    VALUES (p_actor_id, 'result_slip_upload');
    INSERT INTO result_slip_upload_intents (
        path, student_id, actor_id, expected_size, expected_mime
    ) VALUES (
        p_path, p_student_id, p_actor_id, p_expected_size, p_expected_mime
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.reserve_result_slip_upload(
    UUID, UUID, TEXT, BIGINT, TEXT
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reserve_result_slip_upload(
    UUID, UUID, TEXT, BIGINT, TEXT
) TO service_role;

-- File inspection happens in the trusted web service. Once it succeeds, this
-- RPC locks and marks the upload intent in the same transaction that creates
-- the result row. The retained tombstone prevents both an expiry-worker race
-- and replay of a still-live signed upload token after an erasure.
CREATE FUNCTION public.finalize_result_slip_upload(
    p_actor_id UUID,
    p_student_id UUID,
    p_path TEXT,
    p_exam_name TEXT,
    p_subject TEXT,
    p_score NUMERIC,
    p_max_score NUMERIC
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_path TEXT;
    v_finalized_result_id UUID;
    v_finalized_at TIMESTAMPTZ;
    v_new_result_id UUID;
BEGIN
    IF NOT is_feature_enabled('parent_portal')
       OR NULLIF(BTRIM(p_exam_name), '') IS NULL
       OR char_length(BTRIM(p_exam_name)) > 200
       OR (p_subject IS NOT NULL AND char_length(BTRIM(p_subject)) > 100)
       OR NOT EXISTS (
            SELECT 1
            FROM profiles p
            JOIN parent_student_links psl ON psl.parent_id = p.id
            WHERE p.id = p_actor_id
              AND p.role = 'parent'
              AND psl.student_id = p_student_id
       ) THEN
        RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
    END IF;

    SELECT intent.path, intent.finalized_result_id, intent.finalized_at
    INTO v_path, v_finalized_result_id, v_finalized_at
    FROM result_slip_upload_intents intent
    WHERE intent.path = p_path
      AND intent.student_id = p_student_id
      AND intent.actor_id = p_actor_id
      AND intent.expires_at > NOW()
      AND intent.cleanup_claimed_at IS NULL
    FOR UPDATE;

    IF NOT FOUND THEN
        -- A transport failure can hide a successful prior commit from the web
        -- action. Treat an exact retry as success so it never deletes or
        -- duplicates a result slip after an ambiguous response.
        IF EXISTS (
            SELECT 1
            FROM result_slips rs
            WHERE rs.student_id = p_student_id
              AND rs.file_path = p_path
              AND rs.uploaded_by = p_actor_id
              AND rs.exam_name = BTRIM(p_exam_name)
              AND rs.subject IS NOT DISTINCT FROM NULLIF(BTRIM(p_subject), '')
              AND rs.score IS NOT DISTINCT FROM p_score
              AND rs.max_score IS NOT DISTINCT FROM p_max_score
        ) THEN
            RETURN;
        END IF;
        RAISE EXCEPTION 'upload authorization is invalid or expired'
            USING ERRCODE = '42501';
    END IF;

    IF v_finalized_at IS NOT NULL THEN
        IF v_finalized_result_id IS NOT NULL AND EXISTS (
            SELECT 1
            FROM result_slips rs
            WHERE rs.id = v_finalized_result_id
              AND rs.student_id = p_student_id
              AND rs.file_path = p_path
              AND rs.uploaded_by = p_actor_id
              AND rs.exam_name = BTRIM(p_exam_name)
              AND rs.subject IS NOT DISTINCT FROM NULLIF(BTRIM(p_subject), '')
              AND rs.score IS NOT DISTINCT FROM p_score
              AND rs.max_score IS NOT DISTINCT FROM p_max_score
        ) THEN
            RETURN;
        END IF;
        RAISE EXCEPTION 'upload authorization was already consumed'
            USING ERRCODE = '23505';
    END IF;

    INSERT INTO result_slips (
        student_id, exam_name, subject, score, max_score, file_path, uploaded_by
    ) VALUES (
        p_student_id, BTRIM(p_exam_name), NULLIF(BTRIM(p_subject), ''),
        p_score, p_max_score, v_path, p_actor_id
    ) RETURNING id INTO v_new_result_id;

    -- Keep the path-scoped token tombstone through its full lifetime. If the
    -- result/student is erased first, ON DELETE SET NULL lets the expiry worker
    -- remove an object recreated with the still-live signed token.
    UPDATE result_slip_upload_intents
    SET finalized_result_id = v_new_result_id,
        finalized_at = NOW()
    WHERE path = v_path;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.finalize_result_slip_upload(
    UUID, UUID, TEXT, TEXT, TEXT, NUMERIC, NUMERIC
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.finalize_result_slip_upload(
    UUID, UUID, TEXT, TEXT, TEXT, NUMERIC, NUMERIC
) TO service_role;

-- PostgreSQL cannot remove Storage backing objects. Every database erasure
-- therefore records durable work before deleting the student/link rows. The
-- bounded cleanup Edge worker retries this queue with the service role and
-- deletes each queue row only after both private prefixes are empty.
CREATE TABLE public.student_storage_cleanup_queue (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id      UUID NOT NULL UNIQUE,
    reason          TEXT NOT NULL CHECK (reason IN ('anonymise', 'erase', 'wipe')),
    requested_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    attempts        INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    last_attempt_at TIMESTAMPTZ,
    last_error      TEXT CHECK (last_error IS NULL OR char_length(last_error) <= 500),
    completed_at    TIMESTAMPTZ
);

ALTER TABLE public.student_storage_cleanup_queue ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.student_storage_cleanup_queue
    FROM PUBLIC, anon, authenticated;
GRANT SELECT, UPDATE, DELETE ON public.student_storage_cleanup_queue
    TO service_role;

CREATE FUNCTION public.enqueue_student_storage_cleanup(
    p_student_id UUID,
    p_reason TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    INSERT INTO student_storage_cleanup_queue (student_id, reason)
    VALUES (p_student_id, p_reason)
    ON CONFLICT (student_id) DO UPDATE
    SET reason = EXCLUDED.reason,
        requested_at = NOW(),
        attempts = 0,
        last_attempt_at = NULL,
        last_error = NULL,
        completed_at = NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.enqueue_student_storage_cleanup(UUID, TEXT)
    FROM PUBLIC, anon, authenticated, service_role;

-- Disable the email-only legacy entry point. It remains as rollback history but
-- is not reachable through the Data API after this migration.
REVOKE EXECUTE ON FUNCTION public.wipe_operational_data(TEXT)
    FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.wipe_operational_data_secure(
    confirmation TEXT,
    p_actor_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_counts JSONB := '{}'::JSONB;
    v_n BIGINT;
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM security_principals sp
        JOIN profiles p ON p.id = sp.user_id AND p.role = 'admin'
        WHERE sp.capability = 'superadmin'
          AND sp.user_id = p_actor_id
    ) THEN
        RAISE EXCEPTION 'not authorized';
    END IF;
    IF confirmation IS DISTINCT FROM 'WIPE ALL DATA' THEN
        RAISE EXCEPTION 'confirmation mismatch';
    END IF;

    INSERT INTO student_storage_cleanup_queue (student_id, reason)
    SELECT id, 'wipe' FROM students
    ON CONFLICT (student_id) DO UPDATE
    SET reason = EXCLUDED.reason,
        requested_at = NOW(),
        attempts = 0,
        last_attempt_at = NULL,
        last_error = NULL,
        completed_at = NULL;

    PERFORM set_config('app.suppress_audit', 'on', TRUE);
    ALTER TABLE attendance_records
        DISABLE TRIGGER enforce_attendance_on_open_session;

    DELETE FROM dismissals;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_counts := v_counts || jsonb_build_object('dismissals', v_n);
    DELETE FROM messages;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_counts := v_counts || jsonb_build_object('messages', v_n);
    DELETE FROM result_slips;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_counts := v_counts || jsonb_build_object('result_slips', v_n);
    DELETE FROM awards;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_counts := v_counts || jsonb_build_object('awards', v_n);
    DELETE FROM food_poll_responses;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_counts := v_counts || jsonb_build_object('food_poll_responses', v_n);
    DELETE FROM food_polls;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_counts := v_counts || jsonb_build_object('food_polls', v_n);
    DELETE FROM attendance_records;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_counts := v_counts || jsonb_build_object('attendance_records', v_n);
    DELETE FROM sessions;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_counts := v_counts || jsonb_build_object('sessions', v_n);
    DELETE FROM student_results;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_counts := v_counts || jsonb_build_object('student_results', v_n);
    DELETE FROM correction_requests;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_counts := v_counts || jsonb_build_object('correction_requests', v_n);
    DELETE FROM data_disclosures;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_counts := v_counts || jsonb_build_object('data_disclosures', v_n);
    DELETE FROM consent_records;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_counts := v_counts || jsonb_build_object('consent_records', v_n);
    DELETE FROM parent_student_links;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_counts := v_counts || jsonb_build_object('parent_student_links', v_n);
    DELETE FROM enrollments;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_counts := v_counts || jsonb_build_object('enrollments', v_n);
    DELETE FROM students;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_counts := v_counts || jsonb_build_object('students', v_n);
    DELETE FROM classes WHERE is_study_space IS NOT TRUE;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_counts := v_counts || jsonb_build_object('classes', v_n);
    DELETE FROM app_events;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_counts := v_counts || jsonb_build_object('app_events', v_n);

    ALTER TABLE attendance_records
        ENABLE TRIGGER enforce_attendance_on_open_session;

    DELETE FROM audit_log WHERE table_name IN (
        'dismissals', 'messages', 'result_slips', 'awards',
        'food_poll_responses', 'food_polls', 'attendance_records', 'sessions',
        'student_results', 'correction_requests', 'data_disclosures',
        'consent_records', 'parent_student_links', 'enrollments', 'students',
        'classes', 'app_events'
    );
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_counts := v_counts || jsonb_build_object('audit_log', v_n);

    RETURN v_counts;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.wipe_operational_data_secure(TEXT, UUID)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.wipe_operational_data_secure(TEXT, UUID)
    TO service_role;

-- ── Least-privilege notification invocation ─────────────────
-- Never send the project-wide service-role JWT over pg_net. A dedicated
-- high-entropy invocation secret can authorize this one Edge Function without
-- granting database access if a request/header is exposed.
CREATE OR REPLACE FUNCTION public.notify_parent_on_attendance()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_secret TEXT;
BEGIN
    -- UPDATE OF status also fires when an upsert repeats the same value. Do not
    -- turn harmless retries/taps into duplicate parent notifications.
    IF TG_OP = 'UPDATE' AND OLD.status IS NOT DISTINCT FROM NEW.status THEN
        RETURN NEW;
    END IF;
    -- The Edge endpoint intentionally accepts only statuses that warrant a
    -- parent alert. Avoid needless network calls for present/excused writes and
    -- for corrections back to those non-alerting states.
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

CREATE FUNCTION public.invoke_student_storage_cleanup()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_secret TEXT;
BEGIN
    SELECT decrypted_secret INTO v_secret
    FROM vault.decrypted_secrets
    WHERE name = 'storage_cleanup_invoke_secret';

    IF v_secret IS NULL OR char_length(v_secret) NOT BETWEEN 32 AND 512 THEN
        RAISE EXCEPTION 'storage cleanup invocation secret is missing or invalid';
    END IF;

    PERFORM net.http_post(
        url     := 'https://zgikcbsxzjgbigywxbbj.supabase.co/functions/v1/cleanup-student-storage',
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'X-Storage-Cleanup-Secret', v_secret
        ),
        body    := '{}'::JSONB,
        timeout_milliseconds := 120000
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.invoke_student_storage_cleanup()
    FROM PUBLIC, anon, authenticated, service_role;

-- The existing retention migration enables pg_cron best-effort. If this
-- project supports it, drive the durable queue every 15 minutes; otherwise the
-- same function can be scheduled from the Supabase Dashboard.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron')
       AND NOT EXISTS (
            SELECT 1 FROM cron.job
            WHERE jobname = 'student-storage-cleanup'
       ) THEN
        PERFORM cron.schedule(
            'student-storage-cleanup',
            '*/15 * * * *',
            'SELECT invoke_student_storage_cleanup();'
        );
    END IF;
EXCEPTION WHEN OTHERS THEN
    NULL;
END;
$$;

-- ── Parent-safe core reads ───────────────────────────────────
-- Row policies expose every column selected through PostgREST. The historical
-- parent policies therefore disclosed staff-only student/session/attendance
-- notes, actor UUIDs, and client mutation IDs even though the UIs requested a
-- narrow projection. Replace direct table access with deliberately shaped RPCs.
CREATE FUNCTION public.get_parent_children()
RETURNS TABLE (
    id UUID,
    full_name TEXT,
    school TEXT,
    year_of_study TEXT,
    is_active BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT is_parent() OR NOT is_feature_enabled('parent_portal') THEN
        RAISE EXCEPTION 'not authorized';
    END IF;

    RETURN QUERY
    SELECT st.id, st.full_name, st.school, st.year_of_study, st.is_active
    FROM students st
    JOIN parent_student_links psl ON psl.student_id = st.id
    WHERE psl.parent_id = auth.uid()
      AND st.is_active = TRUE
    ORDER BY st.full_name;
END;
$$;

CREATE FUNCTION public.get_parent_attendance_history(
    p_student_id UUID,
    p_limit INTEGER DEFAULT 100,
    p_since DATE DEFAULT NULL
)
RETURNS TABLE (
    id UUID,
    status TEXT,
    marked_at TIMESTAMPTZ,
    session JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT is_parent()
       OR NOT is_feature_enabled('parent_portal')
       OR NOT parent_owns_student(p_student_id) THEN
        RAISE EXCEPTION 'not authorized';
    END IF;

    RETURN QUERY
    SELECT ar.id,
           ar.status,
           ar.marked_at,
           jsonb_build_object(
               'session_date', s.session_date::TEXT,
               'class', jsonb_build_object('name', c.name)
           ) AS session
    FROM attendance_records ar
    JOIN sessions s ON s.id = ar.session_id
    JOIN classes c ON c.id = s.class_id
    WHERE ar.student_id = p_student_id
      AND c.is_study_space = FALSE
      AND (p_since IS NULL OR s.session_date >= p_since)
    ORDER BY ar.marked_at DESC
    LIMIT LEAST(GREATEST(COALESCE(p_limit, 100), 1), 100);
END;
$$;

CREATE FUNCTION public.get_parent_attendance_summary(p_student_id UUID)
RETURNS TABLE (
    class_id UUID,
    class_name TEXT,
    total_sessions BIGINT,
    present_count BIGINT,
    late_count BIGINT,
    absent_count BIGINT,
    excused_count BIGINT,
    attendance_pct NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT is_parent()
       OR NOT is_feature_enabled('parent_portal')
       OR NOT parent_owns_student(p_student_id) THEN
        RAISE EXCEPTION 'not authorized';
    END IF;

    RETURN QUERY
    SELECT s.class_id,
           c.name,
           COUNT(*),
           COUNT(*) FILTER (WHERE ar.status = 'present'),
           COUNT(*) FILTER (WHERE ar.status = 'late'),
           COUNT(*) FILTER (WHERE ar.status = 'absent'),
           COUNT(*) FILTER (WHERE ar.status = 'excused'),
           ROUND(
               100.0 * COUNT(*) FILTER (
                   WHERE ar.status IN ('present', 'late', 'excused')
               ) / NULLIF(COUNT(*), 0),
               1
           )
    FROM attendance_records ar
    JOIN students st ON st.id = ar.student_id
    JOIN sessions s ON s.id = ar.session_id
    JOIN classes c ON c.id = s.class_id
    WHERE ar.student_id = p_student_id
      AND st.is_active = TRUE
      AND c.is_active = TRUE
      AND c.is_study_space = FALSE
    GROUP BY s.class_id, c.name
    ORDER BY c.name;
END;
$$;

CREATE FUNCTION public.get_parent_result_slips(p_student_id UUID)
RETURNS TABLE (
    id UUID,
    student_id UUID,
    exam_name TEXT,
    exam_date DATE,
    subject TEXT,
    score NUMERIC,
    max_score NUMERIC,
    file_path TEXT,
    uploaded_at TIMESTAMPTZ,
    acknowledged_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT is_parent()
       OR NOT is_feature_enabled('parent_portal')
       OR NOT parent_owns_student(p_student_id) THEN
        RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT rs.id, rs.student_id, rs.exam_name, rs.exam_date, rs.subject,
           rs.score, rs.max_score, rs.file_path, rs.uploaded_at,
           rs.acknowledged_at
    FROM result_slips rs
    WHERE rs.student_id = p_student_id
    ORDER BY rs.uploaded_at DESC;
END;
$$;

CREATE FUNCTION public.get_parent_messages(p_student_id UUID)
RETURNS TABLE (
    id UUID,
    student_id UUID,
    subject TEXT,
    body TEXT,
    sent_at TIMESTAMPTZ,
    read_at TIMESTAMPTZ,
    is_from_parent BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT is_parent()
       OR NOT is_feature_enabled('parent_portal')
       OR NOT parent_owns_student(p_student_id) THEN
        RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT m.id, m.student_id, m.subject, m.body, m.sent_at, m.read_at,
           m.sender_id = auth.uid()
    FROM messages m
    WHERE m.student_id = p_student_id
      AND (m.sender_id = auth.uid() OR m.recipient_id = auth.uid())
    ORDER BY m.sent_at;
END;
$$;

CREATE FUNCTION public.get_parent_dismissals()
RETURNS TABLE (
    id UUID,
    student_id UUID,
    dismissed_at TIMESTAMPTZ,
    safely_home_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
    v_today_start TIMESTAMPTZ := (
        (NOW() AT TIME ZONE 'Asia/Singapore')::DATE::TIMESTAMP
        AT TIME ZONE 'Asia/Singapore'
    );
BEGIN
    IF NOT is_parent()
       OR NOT is_feature_enabled('parent_portal')
       OR NOT is_feature_enabled('push_notifications') THEN
        RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT d.id, d.student_id, d.dismissed_at, d.safely_home_at
    FROM dismissals d
    WHERE d.dismissed_at >= v_today_start
      AND parent_owns_student(d.student_id)
    ORDER BY d.dismissed_at DESC;
END;
$$;

CREATE FUNCTION public.submit_parent_result_slip(
    p_student_id UUID,
    p_exam_name TEXT,
    p_exam_date DATE,
    p_subject TEXT,
    p_score NUMERIC,
    p_max_score NUMERIC
)
RETURNS TABLE (
    id UUID,
    student_id UUID,
    exam_name TEXT,
    exam_date DATE,
    subject TEXT,
    score NUMERIC,
    max_score NUMERIC,
    file_path TEXT,
    uploaded_at TIMESTAMPTZ,
    acknowledged_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_recent BIGINT;
BEGIN
    IF NOT is_parent()
       OR NOT is_feature_enabled('parent_portal')
       OR NOT parent_owns_student(p_student_id) THEN
        RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
    END IF;
    IF NULLIF(BTRIM(p_exam_name), '') IS NULL
       OR char_length(BTRIM(p_exam_name)) > 200
       OR (p_subject IS NOT NULL AND char_length(BTRIM(p_subject)) > 100)
       OR (p_score IS NOT NULL AND (p_score = 'NaN'::NUMERIC OR p_score < 0))
       OR (p_max_score IS NOT NULL AND (
            p_max_score = 'NaN'::NUMERIC OR p_max_score <= 0
       ))
       OR (p_score IS NOT NULL AND p_max_score IS NOT NULL
           AND p_score > p_max_score) THEN
        RAISE EXCEPTION 'invalid result slip' USING ERRCODE = '23514';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended(auth.uid()::TEXT, 2));
    DELETE FROM rate_limit_events
    WHERE actor_id = auth.uid()
      AND action = 'parent_result_slip'
      AND created_at < NOW() - INTERVAL '7 days';
    SELECT COUNT(*) INTO v_recent
    FROM rate_limit_events
    WHERE actor_id = auth.uid()
      AND action = 'parent_result_slip'
      AND created_at >= NOW() - INTERVAL '24 hours';
    IF v_recent >= 10 THEN
        RAISE EXCEPTION 'result-slip submission limit reached'
            USING ERRCODE = '54000';
    END IF;
    INSERT INTO rate_limit_events (actor_id, action)
    VALUES (auth.uid(), 'parent_result_slip');

    RETURN QUERY
    WITH inserted AS (
        INSERT INTO result_slips (
            student_id, exam_name, exam_date, subject, score, max_score,
            file_path, uploaded_by
        ) VALUES (
            p_student_id, BTRIM(p_exam_name), p_exam_date,
            NULLIF(BTRIM(p_subject), ''), p_score, p_max_score,
            NULL, auth.uid()
        )
        RETURNING *
    )
    SELECT i.id, i.student_id, i.exam_name, i.exam_date, i.subject,
           i.score, i.max_score, i.file_path, i.uploaded_at,
           i.acknowledged_at
    FROM inserted i;
END;
$$;

CREATE FUNCTION public.send_parent_message(
    p_student_id UUID,
    p_subject TEXT,
    p_body TEXT
)
RETURNS TABLE (
    id UUID,
    student_id UUID,
    subject TEXT,
    body TEXT,
    sent_at TIMESTAMPTZ,
    read_at TIMESTAMPTZ,
    is_from_parent BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_recent BIGINT;
BEGIN
    IF NOT is_parent()
       OR NOT is_feature_enabled('parent_portal')
       OR NOT parent_owns_student(p_student_id) THEN
        RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
    END IF;
    IF NULLIF(BTRIM(p_body), '') IS NULL
       OR char_length(BTRIM(p_body)) > 10000
       OR (p_subject IS NOT NULL AND (
            NULLIF(BTRIM(p_subject), '') IS NULL
            OR char_length(BTRIM(p_subject)) > 200
       )) THEN
        RAISE EXCEPTION 'invalid message' USING ERRCODE = '23514';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended(auth.uid()::TEXT, 3));
    DELETE FROM rate_limit_events
    WHERE actor_id = auth.uid()
      AND action = 'parent_message'
      AND created_at < NOW() - INTERVAL '7 days';
    SELECT COUNT(*) INTO v_recent
    FROM rate_limit_events
    WHERE actor_id = auth.uid()
      AND action = 'parent_message'
      AND created_at >= NOW() - INTERVAL '1 hour';
    IF v_recent >= 30 THEN
        RAISE EXCEPTION 'parent message limit reached'
            USING ERRCODE = '54000';
    END IF;
    INSERT INTO rate_limit_events (actor_id, action)
    VALUES (auth.uid(), 'parent_message');

    RETURN QUERY
    WITH inserted AS (
        INSERT INTO messages (
            sender_id, recipient_id, student_id, subject, body, read_at
        ) VALUES (
            auth.uid(), NULL, p_student_id, NULLIF(BTRIM(p_subject), ''),
            BTRIM(p_body), NULL
        )
        RETURNING *
    )
    SELECT i.id, i.student_id, i.subject, i.body, i.sent_at, i.read_at,
           TRUE
    FROM inserted i;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_parent_children()
    FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_parent_attendance_history(UUID, INTEGER, DATE)
    FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_parent_attendance_summary(UUID)
    FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_parent_result_slips(UUID),
    public.get_parent_messages(UUID),
    public.get_parent_dismissals(),
    public.submit_parent_result_slip(UUID, TEXT, DATE, TEXT, NUMERIC, NUMERIC),
    public.send_parent_message(UUID, TEXT, TEXT)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_parent_children(),
    public.get_parent_attendance_history(UUID, INTEGER, DATE),
    public.get_parent_attendance_summary(UUID),
    public.get_parent_result_slips(UUID),
    public.get_parent_messages(UUID),
    public.get_parent_dismissals(),
    public.submit_parent_result_slip(UUID, TEXT, DATE, TEXT, NUMERIC, NUMERIC),
    public.send_parent_message(UUID, TEXT, TEXT)
    TO authenticated, service_role;

DROP POLICY IF EXISTS "students: parent can read own children" ON students;
DROP POLICY IF EXISTS "classes: parent reads children's classes" ON classes;
DROP POLICY IF EXISTS "enrollments: parent reads own children" ON enrollments;
DROP POLICY IF EXISTS "sessions: parent reads children's sessions" ON sessions;
DROP POLICY IF EXISTS "attendance_records: parent reads own children"
    ON attendance_records;

-- Keep the link table scoped to the caller. Specialty rows contain staff and
-- co-parent UUIDs, so parent access goes only through the projections above.
DROP POLICY IF EXISTS "parent_student_links: parent reads own"
    ON parent_student_links;
CREATE POLICY "parent_student_links: parent reads own"
    ON parent_student_links FOR SELECT TO authenticated
    USING (
        is_feature_enabled('parent_portal')
        AND is_parent()
        AND parent_id = auth.uid()
    );

DROP POLICY IF EXISTS "result_slips: parent reads own child" ON result_slips;
DROP POLICY IF EXISTS "messages: participant reads own" ON messages;
DROP POLICY IF EXISTS "dismissals: parent reads own child" ON dismissals;

-- Internal provenance/reviewer notes and actor IDs must not be exposed through
-- base-table SELECT. No current parent client consumes these policies; add a
-- deliberately shaped RPC if those histories become a product feature.
DROP POLICY IF EXISTS "consent_records: parent reads own child"
    ON consent_records;
DROP POLICY IF EXISTS "correction_requests: parent reads own child"
    ON correction_requests;
DROP POLICY IF EXISTS "awards: parent reads own child" ON awards;

CREATE OR REPLACE FUNCTION public.mark_safely_home(p_dismissal_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT is_parent()
       OR NOT is_feature_enabled('parent_portal')
       OR NOT is_feature_enabled('push_notifications') THEN
        RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
    END IF;

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

-- ── Complete anonymisation boundary ──────────────────────────
-- Preserve anonymous attendance facts, but remove every remaining relationship
-- or child-linked operational record and clear free-text/avatar fields.
CREATE OR REPLACE FUNCTION public._anonymise_student(p_student_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_anonymous_student_id UUID := gen_random_uuid();
    v_previous_audit TEXT := COALESCE(
        NULLIF(current_setting('app.suppress_audit', TRUE), ''), 'off'
    );
    v_previous_retrospective TEXT := COALESCE(
        NULLIF(current_setting('app.retrospective_attendance_write', TRUE), ''), 'off'
    );
BEGIN
    IF NOT EXISTS (SELECT 1 FROM students WHERE id = p_student_id) THEN
        RAISE EXCEPTION 'student not found';
    END IF;

    PERFORM enqueue_student_storage_cleanup(p_student_id, 'anonymise');
    PERFORM set_config('app.suppress_audit', 'on', TRUE);
    PERFORM set_config('app.retrospective_attendance_write', 'on', TRUE);

    -- Preserve aggregate facts under a fresh, unlinked identity. Rotating both
    -- the student and attendance primary keys prevents staff who knew the old
    -- UUIDs from correlating the retained facts after anonymisation.
    INSERT INTO students (
        id, full_name, is_active, deactivated_at
    ) VALUES (
        v_anonymous_student_id, 'Redacted Student', FALSE, NOW()
    );

    UPDATE attendance_records
    SET id = gen_random_uuid(),
        student_id = v_anonymous_student_id,
        notes = NULL,
        late_reason = NULL,
        marked_by = NULL,
        client_mutation_id = NULL
    WHERE student_id = p_student_id;

    DELETE FROM messages            WHERE student_id = p_student_id;
    DELETE FROM result_slips         WHERE student_id = p_student_id;
    DELETE FROM student_results      WHERE student_id = p_student_id;
    DELETE FROM dismissals           WHERE student_id = p_student_id;
    DELETE FROM awards               WHERE student_id = p_student_id;
    DELETE FROM food_poll_responses  WHERE student_id = p_student_id;
    DELETE FROM consent_records      WHERE student_id = p_student_id;
    DELETE FROM correction_requests  WHERE student_id = p_student_id;
    DELETE FROM parent_student_links WHERE student_id = p_student_id;
    DELETE FROM enrollments          WHERE student_id = p_student_id;
    DELETE FROM app_events
    WHERE properties::TEXT LIKE '%' || p_student_id::TEXT || '%'
       OR session_id LIKE '%' || p_student_id::TEXT || '%'
       OR name LIKE '%' || p_student_id::TEXT || '%'
       OR COALESCE(role, '') LIKE '%' || p_student_id::TEXT || '%'
       OR COALESCE(app_version, '') LIKE '%' || p_student_id::TEXT || '%'
       OR COALESCE(device, '') LIKE '%' || p_student_id::TEXT || '%';

    -- Retain the disclosure event as compliance evidence, but remove both its
    -- direct student link and correction/export payloads that may hold PII.
    UPDATE data_disclosures
    SET student_id = NULL,
        disclosed_to = '[redacted]',
        detail = NULL
    WHERE student_id = p_student_id
       OR detail::TEXT LIKE '%' || p_student_id::TEXT || '%';

    DELETE FROM students WHERE id = p_student_id;

    UPDATE audit_log
    SET old_data = NULL,
        new_data = NULL
    WHERE table_name = 'students'
      AND record_id = p_student_id;
    DELETE FROM audit_log
    WHERE old_data->>'student_id' = p_student_id::TEXT
       OR new_data->>'student_id' = p_student_id::TEXT;

    PERFORM set_config(
        'app.retrospective_attendance_write', v_previous_retrospective, TRUE
    );
    PERFORM set_config('app.suppress_audit', v_previous_audit, TRUE);
END;
$$;

-- Log the administrative action without recreating a link to the anonymised
-- child.  The actor and timestamp remain useful audit evidence.
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
        NULL, 'Internal', 'other', auth.uid(),
        jsonb_build_object('action', 'anonymise_student')
    );
END;
$$;

-- Hard erasure has the same indirect-ledger/analytics obligations as
-- anonymisation.  Cascades remove the operational rows; explicit cleanup
-- handles SET NULL/non-FK payloads before the student identity disappears.
CREATE OR REPLACE FUNCTION public.erase_student(p_student_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_previous_audit TEXT := COALESCE(
        NULLIF(current_setting('app.suppress_audit', TRUE), ''), 'off'
    );
BEGIN
    IF NOT is_admin() THEN RAISE EXCEPTION 'not authorized'; END IF;
    PERFORM enqueue_student_storage_cleanup(p_student_id, 'erase');
    PERFORM set_config('app.suppress_audit', 'on', TRUE);

    DELETE FROM messages            WHERE student_id = p_student_id;
    DELETE FROM dismissals          WHERE student_id = p_student_id;
    DELETE FROM food_poll_responses WHERE student_id = p_student_id;
    DELETE FROM app_events
    WHERE properties::TEXT LIKE '%' || p_student_id::TEXT || '%'
       OR session_id LIKE '%' || p_student_id::TEXT || '%'
       OR name LIKE '%' || p_student_id::TEXT || '%'
       OR COALESCE(role, '') LIKE '%' || p_student_id::TEXT || '%'
       OR COALESCE(app_version, '') LIKE '%' || p_student_id::TEXT || '%'
       OR COALESCE(device, '') LIKE '%' || p_student_id::TEXT || '%';
    UPDATE data_disclosures
    SET student_id = NULL,
        disclosed_to = '[redacted]',
        detail = NULL
    WHERE student_id = p_student_id
       OR detail::TEXT LIKE '%' || p_student_id::TEXT || '%';

    DELETE FROM students WHERE id = p_student_id;
    DELETE FROM audit_log
    WHERE (table_name = 'students' AND record_id = p_student_id)
       OR old_data->>'student_id' = p_student_id::TEXT
       OR new_data->>'student_id' = p_student_id::TEXT;

    PERFORM set_config('app.suppress_audit', v_previous_audit, TRUE);
END;
$$;

-- ── Trusted erasure orchestration ─────────────────────────────
-- Storage objects live outside PostgreSQL, so callers that can invoke the
-- database-only RPCs directly can otherwise leave private files behind. The
-- destructive entry points are therefore service-role-only. The web server
-- verifies the signed-in admin, sweeps Storage, invokes one of these wrappers,
-- then sweeps Storage again after the student/link rows have disappeared.
-- The original admin FOR ALL policy also allowed a raw PostgREST DELETE that
-- bypassed every wrapper. A restrictive policy denies direct authenticated
-- deletes while function-owner/service-role maintenance continues to bypass RLS.
DROP POLICY IF EXISTS "students: direct delete denied" ON students;
CREATE POLICY "students: direct delete denied"
    ON students AS RESTRICTIVE FOR DELETE TO authenticated
    USING (FALSE);

-- A direct metadata delete would orphan the private Storage object and could
-- also race a still-live signed token. Result deletion is therefore confined
-- to trusted maintenance/erasure code that also sweeps Storage.
DROP POLICY IF EXISTS "result_slips: direct delete denied" ON result_slips;
CREATE POLICY "result_slips: direct delete denied"
    ON result_slips AS RESTRICTIVE FOR DELETE TO authenticated
    USING (FALSE);

-- p_actor_id is audit context, never authority: only the service_role may call
-- these functions and the actor must still be a current database admin.
CREATE FUNCTION public.anonymise_student_secure(
    p_student_id UUID,
    p_actor_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM profiles
        WHERE id = p_actor_id AND role = 'admin'
    ) THEN
        RAISE EXCEPTION 'not authorized';
    END IF;

    PERFORM _anonymise_student(p_student_id);
    INSERT INTO data_disclosures (
        student_id, disclosed_to, disclosure_type, disclosed_by, detail
    ) VALUES (
        NULL, 'Internal', 'other', p_actor_id,
        jsonb_build_object('action', 'anonymise_student')
    );
END;
$$;

CREATE FUNCTION public.erase_student_secure(
    p_student_id UUID,
    p_actor_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_previous_audit TEXT := COALESCE(
        NULLIF(current_setting('app.suppress_audit', TRUE), ''), 'off'
    );
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM profiles
        WHERE id = p_actor_id AND role = 'admin'
    ) THEN
        RAISE EXCEPTION 'not authorized';
    END IF;

    PERFORM enqueue_student_storage_cleanup(p_student_id, 'erase');
    PERFORM set_config('app.suppress_audit', 'on', TRUE);
    DELETE FROM messages            WHERE student_id = p_student_id;
    DELETE FROM dismissals          WHERE student_id = p_student_id;
    DELETE FROM food_poll_responses WHERE student_id = p_student_id;
    DELETE FROM app_events
    WHERE properties::TEXT LIKE '%' || p_student_id::TEXT || '%'
       OR session_id LIKE '%' || p_student_id::TEXT || '%'
       OR name LIKE '%' || p_student_id::TEXT || '%'
       OR COALESCE(role, '') LIKE '%' || p_student_id::TEXT || '%'
       OR COALESCE(app_version, '') LIKE '%' || p_student_id::TEXT || '%'
       OR COALESCE(device, '') LIKE '%' || p_student_id::TEXT || '%';
    UPDATE data_disclosures
    SET student_id = NULL,
        disclosed_to = '[redacted]',
        detail = NULL
    WHERE student_id = p_student_id
       OR detail::TEXT LIKE '%' || p_student_id::TEXT || '%';
    DELETE FROM students WHERE id = p_student_id;
    DELETE FROM audit_log
    WHERE (table_name = 'students' AND record_id = p_student_id)
       OR old_data->>'student_id' = p_student_id::TEXT
       OR new_data->>'student_id' = p_student_id::TEXT;
    PERFORM set_config('app.suppress_audit', v_previous_audit, TRUE);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.anonymise_student(UUID)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.erase_student(UUID)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public._anonymise_student(UUID)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.anonymise_student_secure(UUID, UUID)
    FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.erase_student_secure(UUID, UUID)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.anonymise_student_secure(UUID, UUID)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.erase_student_secure(UUID, UUID)
    TO service_role;

DO $$
DECLARE
    v_anonymise_secure TEXT := LOWER(pg_get_functiondef(
        'anonymise_student_secure(uuid,uuid)'::REGPROCEDURE
    ));
    v_erase_secure TEXT := LOWER(pg_get_functiondef(
        'erase_student_secure(uuid,uuid)'::REGPROCEDURE
    ));
BEGIN
    ASSERT NOT has_function_privilege(
        'authenticated', 'anonymise_student(uuid)', 'EXECUTE'
    ), 'authenticated can bypass Storage cleanup through anonymise_student';
    ASSERT NOT has_function_privilege(
        'authenticated', 'erase_student(uuid)', 'EXECUTE'
    ), 'authenticated can bypass Storage cleanup through erase_student';
    ASSERT NOT has_function_privilege(
        'authenticated', '_anonymise_student(uuid)', 'EXECUTE'
    ), 'authenticated can invoke the unguarded anonymisation core';
    ASSERT NOT has_function_privilege(
        'authenticated', 'anonymise_student_secure(uuid,uuid)', 'EXECUTE'
    ), 'authenticated can invoke the trusted anonymisation wrapper';
    ASSERT NOT has_function_privilege(
        'authenticated', 'erase_student_secure(uuid,uuid)', 'EXECUTE'
    ), 'authenticated can invoke the trusted erasure wrapper';
    ASSERT has_function_privilege(
        'service_role', 'anonymise_student_secure(uuid,uuid)', 'EXECUTE'
    ), 'service_role cannot invoke the trusted anonymisation wrapper';
    ASSERT has_function_privilege(
        'service_role', 'erase_student_secure(uuid,uuid)', 'EXECUTE'
    ), 'service_role cannot invoke the trusted erasure wrapper';
    ASSERT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'students'
          AND policyname = 'students: direct delete denied'
          AND permissive = 'RESTRICTIVE'
          AND cmd = 'DELETE'
          AND LOWER(qual) LIKE '%false%'
    ), 'authenticated admins can bypass Storage-aware student erasure';
    ASSERT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'result_slips'
          AND policyname = 'result_slips: direct delete denied'
          AND permissive = 'RESTRICTIVE'
          AND cmd = 'DELETE'
          AND LOWER(qual) LIKE '%false%'
    ), 'authenticated admins can orphan result-slip Storage objects';
    ASSERT POSITION('from profiles' IN v_anonymise_secure) > 0
       AND POSITION('id = p_actor_id' IN v_anonymise_secure) > 0
       AND POSITION('role = ''admin''' IN v_anonymise_secure) > 0,
        'trusted anonymisation wrapper does not verify its actor';
    ASSERT POSITION('from profiles' IN v_erase_secure) > 0
       AND POSITION('id = p_actor_id' IN v_erase_secure) > 0
       AND POSITION('role = ''admin''' IN v_erase_secure) > 0,
        'trusted erasure wrapper does not verify its actor';
END;
$$;

-- Bounded parent-created text and result values. Text/score checks are NOT
-- VALID to avoid failing on unknown legacy content while enforcing new rows;
-- the security-critical path check is fully validated after cleanup below.
-- Detach malformed legacy paths first: the safe parent download flow must
-- never sign an object outside the row's own student prefix. The private object
-- remains admin-visible for deliberate reconciliation/cleanup.
UPDATE result_slips
SET file_path = NULL
WHERE file_path IS NOT NULL
  AND canonical_storage_student_id(file_path) IS DISTINCT FROM student_id;

ALTER TABLE result_slips
    ADD CONSTRAINT result_slips_exam_name_text_check
        CHECK (
            exam_name IS NULL
            OR char_length(BTRIM(exam_name)) BETWEEN 1 AND 200
        ) NOT VALID,
    ADD CONSTRAINT result_slips_subject_text_check
        CHECK (
            subject IS NULL
            OR char_length(BTRIM(subject)) BETWEEN 1 AND 100
        ) NOT VALID,
    ADD CONSTRAINT result_slips_scores_check
        CHECK (
            (score IS NULL OR (score <> 'NaN'::NUMERIC AND score >= 0))
            AND (max_score IS NULL OR (max_score <> 'NaN'::NUMERIC AND max_score > 0))
            AND (score IS NULL OR max_score IS NULL OR score <= max_score)
        ) NOT VALID,
    ADD CONSTRAINT result_slips_file_path_check
        CHECK (
            file_path IS NULL
            OR (
                canonical_storage_student_id(file_path) IS NOT NULL
                AND canonical_storage_student_id(file_path) = student_id
            )
        );

ALTER TABLE messages
    ADD CONSTRAINT messages_subject_text_check
        CHECK (
            subject IS NULL
            OR char_length(BTRIM(subject)) BETWEEN 1 AND 200
        ) NOT VALID,
    ADD CONSTRAINT messages_body_text_check
        CHECK (char_length(BTRIM(body)) BETWEEN 1 AND 10000) NOT VALID;

ALTER TABLE correction_requests
    ADD CONSTRAINT correction_requests_field_name_text_check
        CHECK (char_length(BTRIM(field_name)) BETWEEN 1 AND 100) NOT VALID,
    ADD CONSTRAINT correction_requests_current_value_text_check
        CHECK (
            current_value IS NULL OR char_length(current_value) <= 4000
        ) NOT VALID,
    ADD CONSTRAINT correction_requests_requested_value_text_check
        CHECK (
            requested_value IS NULL OR char_length(requested_value) <= 4000
        ) NOT VALID,
    ADD CONSTRAINT correction_requests_review_note_text_check
        CHECK (
            review_note IS NULL OR char_length(review_note) <= 4000
        ) NOT VALID;

-- Review a correction as one database transaction.  The caller supplies only
-- the decision: the request contents, student, reviewer and review timestamp
-- are all derived under a row lock so concurrent/delayed reviews cannot apply
-- twice or leave the student and compliance ledger out of sync.
CREATE FUNCTION public.review_correction_request(
    p_request_id UUID,
    p_decision TEXT,
    p_review_note TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_request correction_requests%ROWTYPE;
    v_student students%ROWTYPE;
    v_decision TEXT := LOWER(BTRIM(COALESCE(p_decision, '')));
    v_review_note TEXT := NULLIF(BTRIM(p_review_note), '');
    v_date_of_birth DATE;
    v_live_value TEXT;
BEGIN
    IF auth.uid() IS NULL OR is_admin() IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
    END IF;
    IF v_decision NOT IN ('applied', 'rejected') THEN
        RAISE EXCEPTION 'decision must be applied or rejected'
            USING ERRCODE = '22023';
    END IF;
    IF v_review_note IS NOT NULL AND char_length(v_review_note) > 4000 THEN
        RAISE EXCEPTION 'review note is too long' USING ERRCODE = '22023';
    END IF;
    IF COALESCE(v_review_note, '') ~* '\m[STFGM][0-9]{7}[A-Z]\M' THEN
        RAISE EXCEPTION 'review note appears to contain an NRIC/FIN'
            USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_request
    FROM correction_requests
    WHERE id = p_request_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'correction request not found' USING ERRCODE = 'P0002';
    END IF;
    IF v_request.status <> 'pending' THEN
        RAISE EXCEPTION 'correction request has already been reviewed'
            USING ERRCODE = '55000';
    END IF;

    IF v_decision = 'applied' THEN
        -- Lock the target too. A request is a snapshot, not permission to
        -- overwrite a newer admin correction made while it was pending.
        SELECT * INTO v_student
        FROM students
        WHERE id = v_request.student_id
        FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'student not found' USING ERRCODE = 'P0002';
        END IF;

        CASE v_request.field_name
            WHEN 'full_name' THEN v_live_value := v_student.full_name;
            WHEN 'date_of_birth' THEN
                v_live_value := v_student.date_of_birth::TEXT;
            WHEN 'school' THEN v_live_value := v_student.school;
            WHEN 'year_of_study' THEN v_live_value := v_student.year_of_study;
            WHEN 'notes' THEN v_live_value := v_student.notes;
            ELSE
                RAISE EXCEPTION 'field cannot be corrected automatically'
                    USING ERRCODE = '22023';
        END CASE;

        IF NULLIF(BTRIM(v_live_value), '') IS DISTINCT FROM
           NULLIF(BTRIM(v_request.current_value), '') THEN
            RAISE EXCEPTION 'correction request is stale; review the current value'
                USING ERRCODE = '55000';
        END IF;

        CASE v_request.field_name
            WHEN 'full_name' THEN
                IF NULLIF(BTRIM(v_request.requested_value), '') IS NULL
                   OR char_length(BTRIM(v_request.requested_value)) > 200 THEN
                    RAISE EXCEPTION 'student name must contain 1 to 200 characters'
                        USING ERRCODE = '22023';
                END IF;
                UPDATE students
                SET full_name = BTRIM(v_request.requested_value)
                WHERE id = v_request.student_id;

            WHEN 'date_of_birth' THEN
                IF NULLIF(BTRIM(v_request.requested_value), '') IS NULL THEN
                    v_date_of_birth := NULL;
                ELSE
                    BEGIN
                        v_date_of_birth := BTRIM(v_request.requested_value)::DATE;
                    EXCEPTION
                        WHEN invalid_text_representation OR datetime_field_overflow THEN
                            RAISE EXCEPTION 'date of birth must be an ISO date'
                                USING ERRCODE = '22007';
                    END;
                    IF v_date_of_birth >
                       (NOW() AT TIME ZONE 'Asia/Singapore')::DATE THEN
                        RAISE EXCEPTION 'date of birth cannot be in the future'
                            USING ERRCODE = '22023';
                    END IF;
                END IF;
                UPDATE students
                SET date_of_birth = v_date_of_birth
                WHERE id = v_request.student_id;

            WHEN 'school' THEN
                IF char_length(BTRIM(v_request.requested_value)) > 200 THEN
                    RAISE EXCEPTION 'school is too long' USING ERRCODE = '22023';
                END IF;
                UPDATE students
                SET school = NULLIF(BTRIM(v_request.requested_value), '')
                WHERE id = v_request.student_id;

            WHEN 'year_of_study' THEN
                IF char_length(BTRIM(v_request.requested_value)) > 100 THEN
                    RAISE EXCEPTION 'year of study is too long'
                        USING ERRCODE = '22023';
                END IF;
                UPDATE students
                SET year_of_study = NULLIF(BTRIM(v_request.requested_value), '')
                WHERE id = v_request.student_id;

            WHEN 'notes' THEN
                IF char_length(BTRIM(v_request.requested_value)) > 4000 THEN
                    RAISE EXCEPTION 'notes are too long' USING ERRCODE = '22023';
                END IF;
                UPDATE students
                SET notes = NULLIF(BTRIM(v_request.requested_value), '')
                WHERE id = v_request.student_id;

            ELSE
                -- The field allowlist above makes this branch unreachable.
                RAISE EXCEPTION 'field cannot be corrected automatically'
                    USING ERRCODE = '22023';
        END CASE;
    END IF;

    UPDATE correction_requests
    SET status = v_decision,
        reviewed_by = auth.uid(),
        reviewed_at = clock_timestamp(),
        review_note = v_review_note
    WHERE id = v_request.id;

    -- Deliberately omit the source and destination values.  The correction
    -- request remains the source of truth; the append-only row is only an event.
    INSERT INTO data_disclosures (
        student_id, disclosed_to, disclosure_type, disclosed_by, detail
    ) VALUES (
        v_request.student_id,
        'Internal',
        'correction_response',
        auth.uid(),
        jsonb_build_object(
            'request_id', v_request.id,
            'decision', v_decision
        )
    );

    RETURN v_request.student_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.review_correction_request(UUID, TEXT, TEXT)
    FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.review_correction_request(UUID, TEXT, TEXT)
    TO authenticated;

-- Admin clients may inspect the queue, but an authenticated session cannot
-- manufacture a reviewed state outside review_correction_request().
DROP POLICY IF EXISTS "correction_requests: admin full" ON correction_requests;
CREATE POLICY "correction_requests: admin read"
    ON correction_requests FOR SELECT TO authenticated
    USING (is_admin());
REVOKE ALL PRIVILEGES ON correction_requests FROM authenticated, anon;
GRANT SELECT ON correction_requests TO authenticated;

-- Consent is compliance evidence, so provenance cannot be supplied through a
-- raw table INSERT. This shaped RPC validates the event and derives the method,
-- notice version, actor and timestamp on the database side.
CREATE FUNCTION public.record_admin_consent(
    p_student_id UUID,
    p_consent_type TEXT,
    p_status TEXT,
    p_source_note TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_consent_type TEXT := LOWER(BTRIM(COALESCE(p_consent_type, '')));
    v_status TEXT := LOWER(BTRIM(COALESCE(p_status, '')));
    v_source_note TEXT := NULLIF(BTRIM(p_source_note), '');
    v_notice_version TEXT;
    v_consent_id UUID;
BEGIN
    IF auth.uid() IS NULL OR is_admin() IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
    END IF;
    IF v_consent_type NOT IN (
        'data_collection', 'result_slips', 'messaging', 'photos'
    ) THEN
        RAISE EXCEPTION 'invalid consent type' USING ERRCODE = '22023';
    END IF;
    IF v_status NOT IN ('granted', 'withdrawn') THEN
        RAISE EXCEPTION 'invalid consent status' USING ERRCODE = '22023';
    END IF;
    IF v_source_note IS NOT NULL AND char_length(v_source_note) > 500 THEN
        RAISE EXCEPTION 'consent source note is too long' USING ERRCODE = '22023';
    END IF;
    IF COALESCE(v_source_note, '') ~* '\m[STFGM][0-9]{7}[A-Z]\M' THEN
        RAISE EXCEPTION 'consent source note appears to contain an NRIC/FIN'
            USING ERRCODE = '22023';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM students WHERE id = p_student_id) THEN
        RAISE EXCEPTION 'student not found' USING ERRCODE = 'P0002';
    END IF;

    SELECT version INTO v_notice_version
    FROM policy_documents
    WHERE doc_type = 'data_protection_notice'
      AND is_current
    ORDER BY published_at DESC
    LIMIT 1;

    IF v_status = 'granted' AND v_notice_version IS NULL THEN
        RAISE EXCEPTION 'no current data protection notice is published';
    END IF;

    INSERT INTO consent_records (
        student_id, consent_type, status, method, notice_version,
        parent_id, granted_by, source_note
    ) VALUES (
        p_student_id, v_consent_type, v_status, 'admin_attestation',
        v_notice_version, NULL, auth.uid(), v_source_note
    )
    RETURNING id INTO v_consent_id;

    RETURN v_consent_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.record_admin_consent(UUID, TEXT, TEXT, TEXT)
    FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.record_admin_consent(UUID, TEXT, TEXT, TEXT)
    TO authenticated;

DROP POLICY IF EXISTS "consent_records: admin full" ON consent_records;
CREATE POLICY "consent_records: admin read"
    ON consent_records FOR SELECT TO authenticated
    USING (is_admin());
REVOKE ALL PRIVILEGES ON consent_records FROM authenticated, anon;
GRANT SELECT ON consent_records TO authenticated;

-- Parent result/message writes also use shaped RPCs. Removing the base INSERT
-- policies prevents callers from requesting RETURNING * to recover actor or
-- reviewer UUIDs that the read projections intentionally omit.
DROP POLICY IF EXISTS "result_slips: parent uploads own child" ON result_slips;
DROP POLICY IF EXISTS "messages: parent sends about own child" ON messages;

-- No current parent client submits correction requests. Keep the base table
-- closed until a rate-limited, shaped submission RPC and review UX are built.
DROP POLICY IF EXISTS "correction_requests: parent creates own child"
    ON correction_requests;

-- Disclosure records are compliance evidence. Only the shaped SECURITY
-- DEFINER workflows may create or scrub them; admin clients receive read-only
-- access and cannot forge the subject, actor, timestamp, type, or payload.
REVOKE ALL PRIVILEGES ON data_disclosures FROM authenticated, anon;
GRANT SELECT ON data_disclosures TO authenticated;
DROP POLICY IF EXISTS "data_disclosures: admin only" ON data_disclosures;
CREATE POLICY "data_disclosures: admin read"
    ON data_disclosures FOR SELECT TO authenticated
    USING (is_admin());

-- Serialize invite quota consumption inside PostgreSQL. The web service is the
-- only caller; validating p_actor_id as a current admin prevents stale or
-- fabricated actor IDs from consuming or bypassing another principal's quota.
CREATE FUNCTION public.consume_invite_rate_limit(p_actor_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_recent BIGINT;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM profiles
        WHERE id = p_actor_id AND role = 'admin'
    ) THEN
        RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended(p_actor_id::TEXT, 4));
    DELETE FROM rate_limit_events
    WHERE actor_id = p_actor_id
      AND action = 'invite'
      AND created_at < NOW() - INTERVAL '7 days';

    SELECT COUNT(*) INTO v_recent
    FROM rate_limit_events
    WHERE actor_id = p_actor_id
      AND action = 'invite'
      AND created_at >= NOW() - INTERVAL '1 hour';

    IF v_recent >= 20 THEN
        RAISE EXCEPTION 'invite rate limit reached' USING ERRCODE = '54000';
    END IF;

    INSERT INTO rate_limit_events (actor_id, action)
    VALUES (p_actor_id, 'invite');
END;
$$;

REVOKE EXECUTE ON FUNCTION public.consume_invite_rate_limit(UUID)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.consume_invite_rate_limit(UUID)
    TO service_role;

-- Analytics is untrusted client telemetry. Accept only a bounded batch through
-- a shaped RPC, derive actor/role/time, enforce the server-side feature flag,
-- and serialize an hourly quota. Raw table inserts previously allowed forged
-- future timestamps, roles, arbitrarily large JSON, and unbounded DB growth.
CREATE FUNCTION public.submit_app_events(p_events JSONB)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_event JSONB;
    v_properties JSONB;
    v_count INTEGER;
    v_recent BIGINT;
    v_role TEXT;
    v_platform TEXT;
    v_event_type TEXT;
    v_session_id TEXT;
    v_name TEXT;
    v_app_version TEXT;
    v_device TEXT;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
    END IF;
    IF NOT is_feature_enabled('analytics') THEN
        RETURN 0;
    END IF;
    IF jsonb_typeof(p_events) IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'analytics payload must be an array'
            USING ERRCODE = '22023';
    END IF;

    v_count := jsonb_array_length(p_events);
    IF v_count = 0 THEN RETURN 0; END IF;
    IF v_count > 100 OR octet_length(p_events::TEXT) > 131072 THEN
        RAISE EXCEPTION 'analytics batch is too large' USING ERRCODE = '22023';
    END IF;

    SELECT p.role INTO v_role FROM profiles p WHERE p.id = auth.uid();
    IF v_role NOT IN ('admin', 'tutor', 'parent') THEN
        RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended(auth.uid()::TEXT, 6));
    DELETE FROM rate_limit_events
    WHERE actor_id = auth.uid()
      AND action = 'analytics_event'
      AND created_at < NOW() - INTERVAL '7 days';
    SELECT COUNT(*) INTO v_recent
    FROM rate_limit_events
    WHERE actor_id = auth.uid()
      AND action = 'analytics_event'
      AND created_at >= NOW() - INTERVAL '1 hour';
    IF v_recent + v_count > 1000 THEN
        RAISE EXCEPTION 'analytics rate limit reached' USING ERRCODE = '54000';
    END IF;

    FOR v_event IN SELECT value FROM jsonb_array_elements(p_events)
    LOOP
        IF jsonb_typeof(v_event) IS DISTINCT FROM 'object' THEN
            RAISE EXCEPTION 'invalid analytics event' USING ERRCODE = '22023';
        END IF;

        v_platform := LOWER(BTRIM(COALESCE(v_event->>'platform', '')));
        v_event_type := LOWER(BTRIM(COALESCE(v_event->>'event_type', '')));
        v_session_id := BTRIM(COALESCE(v_event->>'session_id', ''));
        v_name := BTRIM(COALESCE(v_event->>'name', ''));
        v_app_version := NULLIF(BTRIM(v_event->>'app_version'), '');
        v_device := NULLIF(BTRIM(v_event->>'device'), '');
        v_properties := COALESCE(v_event->'properties', '{}'::JSONB);

        IF v_platform NOT IN ('ios', 'android', 'web')
           OR v_event_type NOT IN (
                'screen_view', 'tap', 'error', 'crash', 'ops', 'latency'
           )
           OR char_length(v_session_id) NOT BETWEEN 1 AND 128
           OR char_length(v_name) NOT BETWEEN 1 AND 200
           OR (v_app_version IS NOT NULL AND char_length(v_app_version) > 64)
           OR (v_device IS NOT NULL AND char_length(v_device) > 200)
           OR jsonb_typeof(v_properties) IS DISTINCT FROM 'object'
           OR octet_length(v_properties::TEXT) > 4096 THEN
            RAISE EXCEPTION 'invalid analytics event' USING ERRCODE = '22023';
        END IF;
        IF (v_name || ' ' || v_session_id || ' ' || v_properties::TEXT) ~*
               '\m[STFGM][0-9]{7}[A-Z]\M'
           OR (v_name || ' ' || v_session_id || ' ' || v_properties::TEXT) ~*
               '[A-Z0-9._%+-]+@[A-Z0-9.-]+[.][A-Z]{2,}' THEN
            RAISE EXCEPTION 'analytics event appears to contain personal data'
                USING ERRCODE = '22023';
        END IF;

        INSERT INTO app_events (
            occurred_at, user_id, role, platform, app_version, session_id,
            event_type, name, properties, device
        ) VALUES (
            clock_timestamp(), auth.uid(), v_role, v_platform, v_app_version,
            v_session_id, v_event_type, v_name, v_properties, v_device
        );
    END LOOP;

    INSERT INTO rate_limit_events (actor_id, action)
    SELECT auth.uid(), 'analytics_event'
    FROM generate_series(1, v_count);
    RETURN v_count;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.submit_app_events(JSONB)
    FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.submit_app_events(JSONB) TO authenticated;
DROP POLICY IF EXISTS "app_events: authenticated insert own" ON app_events;
REVOKE ALL PRIVILEGES ON app_events FROM authenticated, anon;
GRANT SELECT ON app_events TO authenticated;

-- Push tokens are another amplification boundary: an unbounded owner INSERT
-- multiplied every attendance notification. Register through a shaped parent
-- RPC, cap each account at five recent tokens, and keep the base table closed.
CREATE FUNCTION public.register_device_token(
    p_token TEXT,
    p_platform TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_token TEXT := BTRIM(COALESCE(p_token, ''));
    v_platform TEXT := LOWER(BTRIM(COALESCE(p_platform, '')));
BEGIN
    IF auth.uid() IS NULL
       OR NOT is_parent()
       OR NOT is_feature_enabled('push_notifications') THEN
        RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
    END IF;
    IF char_length(v_token) NOT BETWEEN 32 AND 4096
       OR v_token ~ '[[:space:][:cntrl:]]'
       OR v_platform NOT IN ('ios', 'android') THEN
        RAISE EXCEPTION 'invalid device token' USING ERRCODE = '22023';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended(auth.uid()::TEXT, 7));
    INSERT INTO device_tokens (user_id, token, platform, created_at)
    VALUES (auth.uid(), v_token, v_platform, clock_timestamp())
    ON CONFLICT (token) DO UPDATE
    SET user_id = EXCLUDED.user_id,
        platform = EXCLUDED.platform,
        created_at = EXCLUDED.created_at;

    DELETE FROM device_tokens dt
    WHERE dt.user_id = auth.uid()
      AND dt.id IN (
          SELECT ranked.id
          FROM device_tokens ranked
          WHERE ranked.user_id = auth.uid()
          ORDER BY ranked.created_at DESC, ranked.id DESC
          OFFSET 5
      );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.register_device_token(TEXT, TEXT)
    FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.register_device_token(TEXT, TEXT)
    TO authenticated;
DROP POLICY IF EXISTS "device_tokens: owner manages own" ON device_tokens;
REVOKE ALL PRIVILEGES ON device_tokens FROM authenticated, anon;

-- ── Result-slip storage boundary ─────────────────────────────
UPDATE storage.buckets
SET public = FALSE,
    file_size_limit = 10485760,
    allowed_mime_types = ARRAY[
        'application/pdf', 'image/jpeg', 'image/png'
    ]::TEXT[]
WHERE id = 'result-slips';

DROP POLICY IF EXISTS "result-slips: admin all" ON storage.objects;
CREATE POLICY "result-slips: admin all"
    ON storage.objects FOR ALL TO authenticated
    USING (bucket_id = 'result-slips' AND is_admin())
    WITH CHECK (
        bucket_id = 'result-slips'
        AND is_admin()
        AND canonical_storage_student_id(name) IS NOT NULL
        AND EXISTS (
            SELECT 1 FROM students st
            WHERE st.id = canonical_storage_student_id(name)
        )
    );

DROP POLICY IF EXISTS "result-slips: parent read" ON storage.objects;
-- Parent downloads receive a short-lived URL minted by the trusted web server
-- after get_parent_result_slips authorizes the child. Do not expose Storage
-- owner/metadata columns to the authenticated role.

DROP POLICY IF EXISTS "result-slips: parent upload own child" ON storage.objects;
-- Parent file writes now require a server-minted signed upload token tied to a
-- result_slip_upload_intents row. No broad authenticated Storage INSERT policy
-- remains, preventing unbounded orphan-object uploads through the Data API.

-- ── Enforce feature flags at the database boundary ───────────
-- Unrelated session updates remain possible for legacy rows, while every new
-- or changed note is bounded and authenticated writes must use the shaped RPC.
-- Calls without an end-user JWT (trusted maintenance work) still receive the
-- length and identifier checks.
CREATE FUNCTION public.enforce_session_notes_feature_flag()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.notes IS NOT NULL AND char_length(NEW.notes) > 4000 THEN
            RAISE EXCEPTION 'session notes are too long'
                USING ERRCODE = '22001';
        END IF;
    ELSIF NEW.notes IS DISTINCT FROM OLD.notes THEN
        IF NEW.notes IS NOT NULL AND char_length(NEW.notes) > 4000 THEN
            RAISE EXCEPTION 'session notes are too long'
                USING ERRCODE = '22001';
        END IF;
        IF auth.uid() IS NOT NULL
           AND COALESCE(
                current_setting('app.session_note_write', TRUE), 'off'
           ) <> 'on' THEN
            RAISE EXCEPTION 'session notes require the dedicated workflow'
                USING ERRCODE = '42501';
        END IF;
    END IF;

    IF NEW.notes IS NOT NULL
       AND NEW.notes ~* '\m[STFGM][0-9]{7}[A-Z]\M' THEN
        RAISE EXCEPTION 'session note appears to contain an NRIC/FIN'
            USING ERRCODE = '23514';
    END IF;

    IF auth.uid() IS NOT NULL
       AND NULLIF(BTRIM(NEW.notes), '') IS NOT NULL
       AND NOT is_feature_enabled('session_notes') THEN
        RAISE EXCEPTION 'session notes are disabled'
            USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER enforce_session_notes_feature_flag
BEFORE INSERT OR UPDATE OF notes ON sessions
FOR EACH ROW EXECUTE FUNCTION public.enforce_session_notes_feature_flag();

-- Remove the draft NOT VALID constraint if a partial preview was applied. A
-- constraint would still reject unrelated UPDATEs of pre-existing overlong
-- rows; the column-specific trigger above avoids that availability trap.
ALTER TABLE sessions
    DROP CONSTRAINT IF EXISTS sessions_notes_length_check;

-- Clearing an avatar remains possible while the feature is off; assigning or
-- replacing one requires the same database flag as the storage write.
CREATE FUNCTION public.enforce_student_avatar_feature_flag()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    IF auth.uid() IS NOT NULL
       AND NEW.avatar_url IS DISTINCT FROM OLD.avatar_url
       AND NEW.avatar_url IS NOT NULL
       AND NOT is_feature_enabled('student_photos') THEN
        RAISE EXCEPTION 'student photos are disabled'
            USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER enforce_student_avatar_feature_flag
BEFORE UPDATE OF avatar_url ON students
FOR EACH ROW EXECUTE FUNCTION public.enforce_student_avatar_feature_flag();

DROP POLICY IF EXISTS "awards: admin only" ON awards;
CREATE POLICY "awards: admin only"
    ON awards FOR ALL TO authenticated
    USING (is_admin() AND is_feature_enabled('awards'))
    WITH CHECK (is_admin() AND is_feature_enabled('awards'));

DROP POLICY IF EXISTS "awards: parent reads own child" ON awards;
-- Awards are currently an admin-only surface. Add a shaped parent RPC if the
-- product later exposes them; do not publish awarded_by through the base row.

-- Only the public privacy notice belongs on parent/anonymous boundaries;
-- retention schedules and breach plans are internal admin documents.
DROP POLICY IF EXISTS "policy_documents: anon read current" ON policy_documents;
CREATE POLICY "policy_documents: anon read current"
    ON policy_documents FOR SELECT TO anon
    USING (
        doc_type = 'data_protection_notice'
        AND is_current = TRUE
    );

DROP POLICY IF EXISTS "policy_documents: auth read" ON policy_documents;
CREATE POLICY "policy_documents: auth read"
    ON policy_documents FOR SELECT TO authenticated
    USING (
        is_admin()
        OR (
            doc_type = 'data_protection_notice'
            AND is_current = TRUE
        )
    );

-- Verification (DEVOPS-02): abort on a partial security migration.
SET plpgsql.check_asserts = on;
DO $$
DECLARE
    v_anonymise TEXT := LOWER(
        pg_get_functiondef('_anonymise_student(uuid)'::REGPROCEDURE)
    );
    v_retrospective TEXT := LOWER(
        pg_get_functiondef(
            'mark_retrospective_attendance(uuid,uuid,text)'::REGPROCEDURE
        )
    );
    v_erase TEXT := LOWER(
        pg_get_functiondef('erase_student(uuid)'::REGPROCEDURE)
    );
    v_wipe TEXT := LOWER(
        pg_get_functiondef(
            'wipe_operational_data_secure(text,uuid)'::REGPROCEDURE
        )
    );
    v_tutor_owns_class TEXT := LOWER(
        pg_get_functiondef('tutor_owns_class(uuid)'::REGPROCEDURE)
    );
    v_substitute_scope TEXT := LOWER(
        pg_get_functiondef('substitute_covers_session(uuid)'::REGPROCEDURE)
    );
    v_get_my_classes TEXT := LOWER(
        pg_get_functiondef('get_my_classes()'::REGPROCEDURE)
    );
    v_get_today_session TEXT := LOWER(
        pg_get_functiondef(
            'get_or_create_today_session(uuid)'::REGPROCEDURE
        )
    );
    v_session_lifecycle TEXT := LOWER(
        pg_get_functiondef(
            'set_session_lifecycle(uuid,text)'::REGPROCEDURE
        )
    );
    v_session_lifecycle_guard TEXT := LOWER(
        pg_get_functiondef(
            'enforce_session_lifecycle_boundary()'::REGPROCEDURE
        )
    );
    v_update_session_note TEXT := LOWER(
        pg_get_functiondef('update_session_note(uuid,text)'::REGPROCEDURE)
    );
    v_session_notes_guard TEXT := LOWER(
        pg_get_functiondef(
            'enforce_session_notes_feature_flag()'::REGPROCEDURE
        )
    );
    v_get_roster TEXT := LOWER(
        pg_get_functiondef('get_session_roster(uuid)'::REGPROCEDURE)
    );
    v_attendance_integrity TEXT := LOWER(
        pg_get_functiondef(
            'enforce_attendance_write_integrity()'::REGPROCEDURE
        )
    );
    v_sync_attendance TEXT := LOWER(
        pg_get_functiondef('sync_attendance(jsonb)'::REGPROCEDURE)
    );
    v_mutation_replay TEXT := LOWER(
        pg_get_functiondef(
            'attendance_mutation_is_replay(text,uuid,uuid)'::REGPROCEDURE
        )
    );
    v_session_guard TEXT := LOWER(
        pg_get_functiondef(
            'check_retrospective_session_changes()'::REGPROCEDURE
        )
    );
    v_update_retrospective TEXT := LOWER(
        pg_get_functiondef(
            'update_retrospective_session(uuid,text,text,uuid)'::REGPROCEDURE
        )
    );
    v_finalize_upload TEXT := LOWER(
        pg_get_functiondef(
            'finalize_result_slip_upload(uuid,uuid,text,text,text,numeric,numeric)'
                ::REGPROCEDURE
        )
    );
    v_mark_safely_home TEXT := LOWER(
        pg_get_functiondef('mark_safely_home(uuid)'::REGPROCEDURE)
    );
    v_notify_attendance TEXT := LOWER(
        pg_get_functiondef('notify_parent_on_attendance()'::REGPROCEDURE)
    );
    v_notify_dismissal TEXT := LOWER(
        pg_get_functiondef('notify_parent_on_dismissal()'::REGPROCEDURE)
    );
    v_invoke_cleanup TEXT := LOWER(
        pg_get_functiondef('invoke_student_storage_cleanup()'::REGPROCEDURE)
    );
    v_parent_children TEXT := LOWER(
        pg_get_functiondef('get_parent_children()'::REGPROCEDURE)
    );
    v_parent_results TEXT := LOWER(
        pg_get_functiondef('get_parent_result_slips(uuid)'::REGPROCEDURE)
    );
    v_parent_messages TEXT := LOWER(
        pg_get_functiondef('get_parent_messages(uuid)'::REGPROCEDURE)
    );
    v_parent_dismissals TEXT := LOWER(
        pg_get_functiondef('get_parent_dismissals()'::REGPROCEDURE)
    );
    v_submit_parent_result TEXT := LOWER(
        pg_get_functiondef(
            'submit_parent_result_slip(uuid,text,date,text,numeric,numeric)'
                ::REGPROCEDURE
        )
    );
    v_send_parent_message TEXT := LOWER(
        pg_get_functiondef('send_parent_message(uuid,text,text)'::REGPROCEDURE)
    );
    v_review_correction TEXT := LOWER(
        pg_get_functiondef(
            'review_correction_request(uuid,text,text)'::REGPROCEDURE
        )
    );
    v_record_consent TEXT := LOWER(
        pg_get_functiondef(
            'record_admin_consent(uuid,text,text,text)'::REGPROCEDURE
        )
    );
    v_consume_invite TEXT := LOWER(
        pg_get_functiondef('consume_invite_rate_limit(uuid)'::REGPROCEDURE)
    );
    v_submit_events TEXT := LOWER(
        pg_get_functiondef('submit_app_events(jsonb)'::REGPROCEDURE)
    );
    v_register_token TEXT := LOWER(
        pg_get_functiondef('register_device_token(text,text)'::REGPROCEDURE)
    );
BEGIN
    ASSERT POSITION('assigned_from <=' IN v_tutor_owns_class) > 0
       AND POSITION('asia/singapore' IN v_tutor_owns_class) > 0,
        'tutor_owns_class ignores assignment start or centre civil date';

    ASSERT (
        SELECT LOWER(qual) LIKE '%assigned_from%'
           AND LOWER(qual) LIKE '%asia/singapore%'
           AND LOWER(with_check) LIKE '%assigned_from%'
           AND LOWER(with_check) LIKE '%asia/singapore%'
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'student_results'
          AND policyname = 'student_results: tutor manages enrolled students'
    ), 'student-result assignment boundaries ignore the centre civil date';

    ASSERT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgrelid = 'sessions'::REGCLASS
          AND tgname = 'validate_session_sub_tutor'
          AND NOT tgisinternal
    ), 'substitute tutor validation trigger missing';

    ASSERT POSITION('sub_tutor_id = auth.uid()' IN v_substitute_scope) > 0
       AND POSITION('asia/singapore' IN v_substitute_scope) > 0
       AND POSITION('::date - 7' IN v_substitute_scope) > 0,
        'substitute access is not actor-bound to the seven-day offline window';
    ASSERT (
        SELECT LOWER(qual) LIKE '%substitute_covers_session%'
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'sessions'
          AND policyname = 'substitute_can_read_session'
    ), 'substitute session reads remain unbounded';
    ASSERT POSITION('substitute_covers_session' IN v_get_my_classes) > 0
       AND POSITION('tutor_owns_class' IN v_get_my_classes) > 0
       AND POSITION('not c.is_study_space' IN v_get_my_classes) > 0
       AND POSITION('current_session.session_date = v_today' IN v_get_my_classes) > 0
       AND POSITION('can_operate_today_session' IN v_get_my_classes) > 0,
        'staff class projection lacks bounded scope or explicit capabilities';
    ASSERT POSITION('substitute_covers_session' IN v_get_roster) > 0
       AND POSITION('tutor_owns_class' IN v_get_roster) > 0
       AND POSITION('e.enrolled_at' IN v_get_roster) > 0
       AND POSITION('e.unenrolled_at' IN v_get_roster) > 0,
        'session roster lacks authorization or historical enrollment bounds';
    ASSERT has_function_privilege(
        'authenticated', 'get_my_classes()', 'EXECUTE'
    ) AND NOT has_function_privilege(
        'anon', 'get_my_classes()', 'EXECUTE'
    ) AND has_function_privilege(
        'authenticated', 'get_session_roster(uuid)', 'EXECUTE'
    ) AND NOT has_function_privilege(
        'anon', 'get_session_roster(uuid)', 'EXECUTE'
    ), 'staff class/roster projection privileges are incorrect';
    ASSERT POSITION('clock_timestamp()' IN v_get_today_session) > 0
       AND POSITION('on conflict (class_id, session_date) do nothing' IN v_get_today_session) > 0
       AND POSITION('substitute_covers_session' IN v_get_today_session) > 0,
        'today-session discovery/creation lost server time or substitute scope';
    ASSERT POSITION('clock_timestamp()' IN v_session_lifecycle) > 0
       AND POSITION('ended sessions cannot be reopened' IN v_session_lifecycle) > 0
       AND POSITION('substitute_covers_session' IN v_session_lifecycle) > 0
       AND POSITION('app.session_lifecycle_write' IN v_session_lifecycle) > 0,
        'session lifecycle is not server-timed, immutable, or substitute scoped';
    ASSERT POSITION('app.session_lifecycle_write' IN v_session_lifecycle_guard) > 0
       AND POSITION('app.session_create_write' IN v_session_lifecycle_guard) > 0
       AND POSITION('app.retrospective_session_create' IN v_session_lifecycle_guard) > 0
       AND POSITION('session creation requires the dedicated workflow' IN v_session_lifecycle_guard) > 0
       AND EXISTS (
            SELECT 1 FROM pg_trigger
            WHERE tgrelid = 'sessions'::REGCLASS
              AND tgname = 'enforce_session_lifecycle_boundary'
              AND NOT tgisinternal
       ), 'direct session lifecycle timestamp writes are not blocked';
    ASSERT POSITION('session identity fields are immutable' IN v_session_guard) > 0
       AND POSITION('new.created_at' IN v_session_guard) > 0
       AND POSITION('sessions cannot be deleted directly' IN v_session_guard) > 0,
        'direct session identity mutation or deletion is not blocked';
    ASSERT POSITION('session_notes' IN v_update_session_note) > 0
       AND POSITION('substitute_covers_session' IN v_update_session_note) > 0
       AND POSITION('[stfgm]' IN v_update_session_note) > 0
       AND POSITION('app.session_note_write' IN v_update_session_note) > 0,
        'session-note RPC lost feature, substitute, or identifier controls';
    ASSERT has_function_privilege(
        'authenticated', 'get_or_create_today_session(uuid)', 'EXECUTE'
    ) AND NOT has_function_privilege(
        'anon', 'get_or_create_today_session(uuid)', 'EXECUTE'
    ) AND NOT has_function_privilege(
        'service_role', 'get_or_create_today_session(uuid)', 'EXECUTE'
    ) AND has_function_privilege(
        'authenticated', 'set_session_lifecycle(uuid,text)', 'EXECUTE'
    ) AND NOT has_function_privilege(
        'anon', 'set_session_lifecycle(uuid,text)', 'EXECUTE'
    ) AND NOT has_function_privilege(
        'service_role', 'set_session_lifecycle(uuid,text)', 'EXECUTE'
    ) AND has_function_privilege(
        'authenticated', 'update_session_note(uuid,text)', 'EXECUTE'
    ) AND NOT has_function_privilege(
        'anon', 'update_session_note(uuid,text)', 'EXECUTE'
    ) AND NOT has_function_privilege(
        'service_role', 'update_session_note(uuid,text)', 'EXECUTE'
    ), 'session lifecycle/note RPC privileges are incorrect';

    ASSERT (
        SELECT LOWER(with_check) LIKE '%student_is_enrolled_for_session%'
           AND LOWER(with_check) LIKE '%tutor_owns_class%'
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'attendance_records'
          AND policyname = 'attendance_records: tutor reads/writes their sessions'
    ), 'tutor attendance writes are not class-bound';

    ASSERT (
        SELECT LOWER(with_check) LIKE '%student_is_enrolled_for_session%'
           AND LOWER(with_check) LIKE '%substitute_covers_session%'
           AND LOWER(qual) LIKE '%substitute_covers_session%'
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'attendance_records'
          AND policyname = 'substitute_can_mark_attendance'
    ), 'substitute attendance writes are not class-bound';

    ASSERT POSITION('student_is_enrolled_for_session' IN v_retrospective) > 0,
        'retrospective attendance is not historically enrollment-bound';

    ASSERT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgrelid = 'attendance_records'::REGCLASS
          AND tgname = 'enforce_attendance_write_integrity'
          AND NOT tgisinternal
    ), 'universal attendance integrity trigger is missing';
    ASSERT POSITION('new.marked_by := auth.uid()' IN v_attendance_integrity) > 0
       AND POSITION('new.marked_at := clock_timestamp()' IN v_attendance_integrity) > 0
       AND POSITION('student was not enrolled for this session' IN v_attendance_integrity) > 0,
        'attendance actor, timestamp, or enrollment integrity is incomplete';
    ASSERT (
        SELECT COUNT(*) = 3
        FROM pg_constraint
        WHERE conrelid = 'attendance_records'::REGCLASS
          AND conname IN (
              'attendance_records_notes_length_check',
              'attendance_records_late_reason_check',
              'attendance_records_mutation_id_check'
          )
    ), 'attendance content bounds are incomplete';
    ASSERT POSITION('app.attendance_offline_sync' IN v_sync_attendance) > 0
       AND POSITION('clock_timestamp()' IN v_sync_attendance) > 0
       AND POSITION('attendance_mutation_is_replay' IN v_sync_attendance) > 0
       AND POSITION('pg_advisory_xact_lock' IN v_sync_attendance) > 0,
        'offline attendance replay still trusts device time or hides collisions';
    ASSERT POSITION(
        'v_session_date < v_today - 7' IN LOWER(pg_get_functiondef(
            'check_session_not_ended()'::REGPROCEDURE
        ))
    ) > 0, 'offline sync can rewrite arbitrarily old open sessions';
    ASSERT (
        SELECT rowsecurity
        FROM pg_tables
        WHERE schemaname = 'public'
          AND tablename = 'attendance_mutation_receipts'
    ), 'attendance mutation receipts are missing or lack RLS';
    ASSERT NOT has_table_privilege(
        'authenticated', 'attendance_mutation_receipts', 'SELECT'
    ) AND NOT has_table_privilege(
        'authenticated', 'attendance_mutation_receipts', 'INSERT'
    ), 'attendance mutation receipts are exposed to clients';
    ASSERT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgrelid = 'attendance_records'::REGCLASS
          AND tgname = 'archive_attendance_mutation_receipt'
          AND NOT tgisinternal
    ), 'replaced attendance mutation IDs are not archived';
    ASSERT POSITION('attendance_mutation_receipts' IN v_mutation_replay) > 0
       AND POSITION('app.attendance_offline_sync' IN v_mutation_replay) > 0
       AND POSITION('auth.uid()' IN v_mutation_replay) > 0,
        'mutation replay lookup is exposed or not bound to the original actor';
    ASSERT POSITION('app.retrospective_session_update' IN v_session_guard) > 0
       AND POSITION('old.session_date < v_today or new.session_date < v_today' IN v_session_guard) > 0
       AND POSITION('app.retrospective_session_update' IN v_update_retrospective) > 0
       AND POSITION('app.session_note_write' IN v_update_retrospective) > 0,
        'past sessions can bypass the dedicated feature-gated update RPC';

    ASSERT POSITION('delete from parent_student_links' IN v_anonymise) > 0
       AND POSITION('delete from enrollments' IN v_anonymise) > 0
       AND POSITION('late_reason = null' IN v_anonymise) > 0
       AND POSITION('marked_by = null' IN v_anonymise) > 0
       AND POSITION('client_mutation_id = null' IN v_anonymise) > 0
       AND POSITION('id = gen_random_uuid()' IN v_anonymise) > 0
       AND POSITION('student_id = v_anonymous_student_id' IN v_anonymise) > 0
       AND POSITION('delete from students where id = p_student_id' IN v_anonymise) > 0
       AND POSITION('enqueue_student_storage_cleanup' IN v_anonymise) > 0
       AND POSITION('delete from app_events' IN v_anonymise) > 0
       AND POSITION('update data_disclosures' IN v_anonymise) > 0,
        '_anonymise_student is missing required child-data cleanup';

    ASSERT POSITION(
        'null, ''internal'', ''other'''
        IN LOWER(pg_get_functiondef('anonymise_student(uuid)'::REGPROCEDURE))
    ) > 0, 'anonymise_student recreates a child-linked disclosure';

    ASSERT POSITION('delete from app_events' IN v_erase) > 0
       AND POSITION('update data_disclosures' IN v_erase) > 0
       AND POSITION('enqueue_student_storage_cleanup' IN v_erase) > 0,
        'erase_student leaves indirect child PII';

    ASSERT NOT has_function_privilege(
        'authenticated', 'wipe_operational_data(text)', 'EXECUTE'
    ), 'legacy email-only wipe RPC remains directly callable';
    ASSERT NOT has_function_privilege(
        'authenticated', 'wipe_operational_data_secure(text,uuid)', 'EXECUTE'
    ), 'authenticated can bypass Storage-aware wipe orchestration';
    ASSERT has_function_privilege(
        'service_role', 'wipe_operational_data_secure(text,uuid)', 'EXECUTE'
    ), 'trusted web service cannot invoke the secure wipe';
    ASSERT POSITION('security_principals' IN v_wipe) > 0
       AND POSITION('p_actor_id' IN v_wipe) > 0
       AND POSITION('delete from messages' IN v_wipe) > 0
       AND POSITION('delete from result_slips' IN v_wipe) > 0
       AND POSITION('delete from app_events' IN v_wipe) > 0
       AND POSITION('student_storage_cleanup_queue' IN v_wipe) > 0,
        'secure wipe lacks principal authorization or complete cleanup';

    ASSERT (
        SELECT file_size_limit = 10485760
           AND public = FALSE
           AND allowed_mime_types @> ARRAY[
                'application/pdf', 'image/jpeg', 'image/png'
           ]::TEXT[]
           AND allowed_mime_types <@ ARRAY[
                'application/pdf', 'image/jpeg', 'image/png'
           ]::TEXT[]
        FROM storage.buckets
        WHERE id = 'result-slips'
    ), 'result-slips bucket limits are incorrect';

    ASSERT (
        SELECT file_size_limit = 5242880
           AND public = FALSE
           AND allowed_mime_types @> ARRAY['image/jpeg', 'image/png']::TEXT[]
           AND allowed_mime_types <@ ARRAY['image/jpeg', 'image/png']::TEXT[]
        FROM storage.buckets
        WHERE id = 'student-photos'
    ), 'student-photos bucket limits are incorrect';

    ASSERT (
        SELECT LOWER(with_check) LIKE '%canonical_storage_student_id%'
           AND LOWER(with_check) LIKE '%student_photos%'
        FROM pg_policies
        WHERE schemaname = 'storage'
          AND tablename = 'objects'
          AND policyname = 'student-photos: admin all'
    ), 'admin student-photo writes are not flag/canonical bound';

    ASSERT NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'storage'
          AND tablename = 'objects'
          AND policyname = 'student-photos: parent read'
    ), 'parent clients can enumerate student-photo Storage metadata';

    ASSERT (
        SELECT LOWER(qual) LIKE '%student_photos%'
           AND LOWER(qual) LIKE '%tutor_owns_class%'
           AND LOWER(qual) LIKE '%substitute_covers_session%'
           AND LOWER(qual) LIKE '%e.enrolled_at%'
           AND LOWER(qual) LIKE '%e.unenrolled_at%'
           AND LOWER(qual) LIKE '%canonical_storage_student_id%'
        FROM pg_policies
        WHERE schemaname = 'storage'
          AND tablename = 'objects'
          AND policyname = 'student-photos: tutor read'
    ), 'tutor student-photo reads ignore assignment/substitute/path boundaries';

    ASSERT (
        SELECT LOWER(with_check) LIKE '%canonical_storage_student_id%'
        FROM pg_policies
        WHERE schemaname = 'storage'
          AND tablename = 'objects'
          AND policyname = 'result-slips: admin all'
    ), 'admin result-slip uploads are not canonical';

    ASSERT NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'storage'
          AND tablename = 'objects'
          AND policyname = 'result-slips: parent upload own child'
    ), 'parents retain an unbounded direct Storage upload policy';

    ASSERT NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'storage'
          AND tablename = 'objects'
          AND policyname = 'result-slips: parent read'
    ), 'parent clients can enumerate result-slip Storage metadata';

    ASSERT NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND (
              (tablename = 'result_slips'
               AND policyname IN (
                   'result_slips: parent reads own child',
                   'result_slips: parent uploads own child'
               ))
              OR (tablename = 'messages'
                  AND policyname IN (
                      'messages: participant reads own',
                      'messages: parent sends about own child'
                  ))
              OR (tablename = 'dismissals'
                  AND policyname = 'dismissals: parent reads own child')
          )
    ), 'parent specialty base-table access exposes provenance fields';

    ASSERT (
        SELECT rowsecurity
        FROM pg_tables
        WHERE schemaname = 'public'
          AND tablename = 'result_slip_upload_intents'
    ), 'result-slip upload intents are missing or lack RLS';
    ASSERT NOT has_table_privilege(
        'authenticated', 'result_slip_upload_intents', 'SELECT'
    ) AND NOT has_table_privilege(
        'authenticated', 'result_slip_upload_intents', 'INSERT'
    ), 'result-slip upload intents are exposed to clients';
    ASSERT NOT has_function_privilege(
        'authenticated',
        'reserve_result_slip_upload(uuid,uuid,text,bigint,text)',
        'EXECUTE'
    ) AND NOT has_function_privilege(
        'authenticated',
        'finalize_result_slip_upload(uuid,uuid,text,text,text,numeric,numeric)',
        'EXECUTE'
    ), 'authenticated clients can mint or finalize upload intents';
    ASSERT has_function_privilege(
        'service_role',
        'reserve_result_slip_upload(uuid,uuid,text,bigint,text)',
        'EXECUTE'
    ) AND has_function_privilege(
        'service_role',
        'finalize_result_slip_upload(uuid,uuid,text,text,text,numeric,numeric)',
        'EXECUTE'
    ), 'trusted web service cannot manage result-slip upload intents';
    ASSERT POSITION('for update' IN v_finalize_upload) > 0
       AND POSITION('cleanup_claimed_at is null' IN v_finalize_upload) > 0
       AND POSITION('update result_slip_upload_intents' IN v_finalize_upload) > 0
       AND POSITION('finalized_result_id' IN v_finalize_upload) > 0
       AND POSITION('finalized_at' IN v_finalize_upload) > 0,
        'result-slip finalization does not atomically retain its token tombstone';
    ASSERT (
        SELECT COUNT(*) = 3
        FROM pg_constraint
        WHERE conrelid = 'result_slip_upload_intents'::REGCLASS
          AND contype = 'f'
          AND LOWER(pg_get_constraintdef(oid)) LIKE '%on delete set null%'
    ), 'identity/result deletion can discard a live signed-upload cleanup tombstone';

    ASSERT (
        SELECT COUNT(*) = 6
        FROM pg_constraint
        WHERE conrelid IN ('result_slips'::REGCLASS, 'messages'::REGCLASS)
          AND conname IN (
              'result_slips_exam_name_text_check',
              'result_slips_subject_text_check',
              'result_slips_scores_check',
              'result_slips_file_path_check',
              'messages_subject_text_check',
              'messages_body_text_check'
          )
    ), 'bounded text/result constraints are incomplete';

    ASSERT (
        SELECT COUNT(*) = 4
        FROM pg_constraint
        WHERE conrelid = 'correction_requests'::REGCLASS
          AND conname IN (
              'correction_requests_field_name_text_check',
              'correction_requests_current_value_text_check',
              'correction_requests_requested_value_text_check',
              'correction_requests_review_note_text_check'
          )
    ), 'correction-request text constraints are incomplete';

    ASSERT NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'correction_requests'
          AND policyname = 'correction_requests: parent creates own child'
    ), 'unused parent correction insertion remains an unbounded spam surface';
    ASSERT has_table_privilege(
        'authenticated', 'correction_requests', 'SELECT'
    ) AND NOT has_table_privilege(
        'authenticated', 'correction_requests', 'INSERT'
    ) AND NOT has_table_privilege(
        'authenticated', 'correction_requests', 'UPDATE'
    ) AND NOT has_table_privilege(
        'authenticated', 'correction_requests', 'DELETE'
    ) AND NOT has_table_privilege(
        'authenticated', 'correction_requests', 'TRUNCATE'
    ) AND NOT has_table_privilege(
        'authenticated', 'correction_requests', 'REFERENCES'
    ) AND NOT has_table_privilege(
        'authenticated', 'correction_requests', 'TRIGGER'
    ), 'authenticated clients can bypass atomic correction review';
    ASSERT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'correction_requests'
          AND policyname = 'correction_requests: admin read'
          AND cmd = 'SELECT'
    ) AND NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'correction_requests'
          AND policyname = 'correction_requests: admin full'
    ), 'correction queue is not read-only outside its review RPC';

    ASSERT EXISTS (
        SELECT 1
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = 'review_correction_request'
          AND p.prosecdef
    ), 'atomic correction-review RPC is missing or not SECURITY DEFINER';
    ASSERT has_function_privilege(
        'authenticated', 'review_correction_request(uuid,text,text)', 'EXECUTE'
    ) AND NOT has_function_privilege(
        'anon', 'review_correction_request(uuid,text,text)', 'EXECUTE'
    ) AND NOT has_function_privilege(
        'service_role', 'review_correction_request(uuid,text,text)', 'EXECUTE'
    ), 'correction-review RPC privileges are not admin-client scoped';
    ASSERT POSITION('for update' IN v_review_correction) > 0
       AND POSITION('is_admin() is distinct from true' IN v_review_correction) > 0
       AND POSITION('case v_request.field_name' IN v_review_correction) > 0
       AND POSITION('from students' IN v_review_correction) > 0
       AND POSITION('v_request.current_value' IN v_review_correction) > 0
       AND POSITION('correction request is stale' IN v_review_correction) > 0
       AND POSITION('reviewed_by = auth.uid()' IN v_review_correction) > 0
       AND POSITION('insert into data_disclosures' IN v_review_correction) > 0,
        'correction review lacks stale-write protection, admin enforcement, or atomic audit';
    ASSERT POSITION('''applied_value''' IN v_review_correction) = 0
       AND POSITION('''new_value''' IN v_review_correction) = 0
       AND POSITION('''field''' IN v_review_correction) = 0
       AND POSITION('''request_id''' IN v_review_correction) > 0
       AND POSITION('''decision''' IN v_review_correction) > 0,
        'correction disclosure duplicates corrected personal data';

    ASSERT has_function_privilege(
        'authenticated', 'record_admin_consent(uuid,text,text,text)', 'EXECUTE'
    ) AND NOT has_function_privilege(
        'anon', 'record_admin_consent(uuid,text,text,text)', 'EXECUTE'
    ) AND NOT has_function_privilege(
        'service_role', 'record_admin_consent(uuid,text,text,text)', 'EXECUTE'
    ), 'consent-recording RPC privileges are not admin-client scoped';
    ASSERT POSITION('is_admin() is distinct from true' IN v_record_consent) > 0
       AND POSITION('''admin_attestation''' IN v_record_consent) > 0
       AND POSITION('granted_by' IN v_record_consent) > 0
       AND POSITION('auth.uid()' IN v_record_consent) > 0
       AND POSITION('data_protection_notice' IN v_record_consent) > 0,
        'consent provenance is not derived inside the trusted RPC';
    ASSERT has_table_privilege(
        'authenticated', 'consent_records', 'SELECT'
    ) AND NOT has_table_privilege(
        'authenticated', 'consent_records', 'INSERT'
    ) AND NOT has_table_privilege(
        'authenticated', 'consent_records', 'UPDATE'
    ) AND NOT has_table_privilege(
        'authenticated', 'consent_records', 'DELETE'
    ), 'authenticated users can forge or mutate the consent ledger';
    ASSERT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'consent_records'
          AND policyname = 'consent_records: admin read'
          AND cmd = 'SELECT'
    ) AND NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'consent_records'
          AND policyname = 'consent_records: admin full'
    ), 'consent ledger is not read-only outside its recording RPC';

    ASSERT has_table_privilege(
        'authenticated', 'data_disclosures', 'SELECT'
    ) AND NOT has_table_privilege(
        'authenticated', 'data_disclosures', 'INSERT'
    ) AND NOT has_table_privilege(
        'authenticated', 'data_disclosures', 'UPDATE'
    ) AND NOT has_table_privilege(
        'authenticated', 'data_disclosures', 'DELETE'
    ), 'authenticated users can forge or mutate the disclosure ledger';

    ASSERT (
        SELECT COUNT(*) = 1
        FROM pg_policies
        WHERE tablename = 'data_disclosures'
          AND policyname = 'data_disclosures: admin read'
          AND cmd = 'SELECT'
    ), 'disclosure ledger is not restricted to read-only admin access';

    ASSERT has_function_privilege(
        'service_role', 'consume_invite_rate_limit(uuid)', 'EXECUTE'
    ) AND NOT has_function_privilege(
        'authenticated', 'consume_invite_rate_limit(uuid)', 'EXECUTE'
    ) AND NOT has_function_privilege(
        'anon', 'consume_invite_rate_limit(uuid)', 'EXECUTE'
    ), 'invite quota function is not service-only';
    ASSERT POSITION('pg_advisory_xact_lock' IN v_consume_invite) > 0
       AND POSITION('role = ''admin''' IN v_consume_invite) > 0
       AND POSITION('count(*)' IN v_consume_invite) > 0
       AND POSITION('insert into rate_limit_events' IN v_consume_invite) > 0,
        'invite quota consumption is not atomic or actor-bound';

    ASSERT has_function_privilege(
        'authenticated', 'submit_app_events(jsonb)', 'EXECUTE'
    ) AND NOT has_function_privilege(
        'anon', 'submit_app_events(jsonb)', 'EXECUTE'
    ) AND NOT has_function_privilege(
        'service_role', 'submit_app_events(jsonb)', 'EXECUTE'
    ), 'analytics ingestion RPC privileges are incorrect';
    ASSERT POSITION('is_feature_enabled(''analytics'')' IN v_submit_events) > 0
       AND POSITION('pg_advisory_xact_lock' IN v_submit_events) > 0
       AND POSITION('clock_timestamp()' IN v_submit_events) > 0
       AND POSITION('auth.uid()' IN v_submit_events) > 0
       AND POSITION('octet_length(v_properties::text) > 4096' IN v_submit_events) > 0,
        'analytics ingestion lacks feature, provenance, size, or quota controls';
    ASSERT NOT has_table_privilege(
        'authenticated', 'app_events', 'INSERT'
    ) AND has_table_privilege(
        'authenticated', 'app_events', 'SELECT'
    ) AND NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'app_events'
          AND policyname = 'app_events: authenticated insert own'
    ), 'authenticated clients can bypass shaped analytics ingestion';

    ASSERT has_function_privilege(
        'authenticated', 'register_device_token(text,text)', 'EXECUTE'
    ) AND NOT has_function_privilege(
        'anon', 'register_device_token(text,text)', 'EXECUTE'
    ) AND NOT has_function_privilege(
        'service_role', 'register_device_token(text,text)', 'EXECUTE'
    ), 'device-token registration RPC privileges are incorrect';
    ASSERT POSITION('is_parent()' IN v_register_token) > 0
       AND POSITION('push_notifications' IN v_register_token) > 0
       AND POSITION('pg_advisory_xact_lock' IN v_register_token) > 0
       AND POSITION('offset 5' IN v_register_token) > 0,
        'device-token registration lacks role, feature, or count limits';
    ASSERT NOT has_table_privilege(
        'authenticated', 'device_tokens', 'SELECT'
    ) AND NOT has_table_privilege(
        'authenticated', 'device_tokens', 'INSERT'
    ) AND NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'device_tokens'
          AND policyname = 'device_tokens: owner manages own'
    ), 'authenticated clients can directly amplify push fan-out';

    ASSERT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgrelid = 'sessions'::REGCLASS
          AND tgname = 'enforce_session_notes_feature_flag'
          AND NOT tgisinternal
    ) AND POSITION('char_length(new.notes) > 4000' IN v_session_notes_guard) > 0
      AND POSITION('app.session_note_write' IN v_session_notes_guard) > 0
      AND POSITION('[stfgm]' IN v_session_notes_guard) > 0,
        'session notes lack universal bounds or shaped-write enforcement';
    ASSERT NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'sessions'::REGCLASS
          AND conname = 'sessions_notes_length_check'
    ), 'legacy session notes could block unrelated session updates';

    ASSERT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgrelid = 'students'::REGCLASS
          AND tgname = 'enforce_student_avatar_feature_flag'
          AND NOT tgisinternal
    ), 'student_photos database gate missing';

    ASSERT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'students'::REGCLASS
          AND conname = 'students_avatar_url_path_check'
          AND LOWER(pg_get_constraintdef(oid)) LIKE '%is not null%'
    ), 'students.avatar_url canonical-path constraint missing';

    ASSERT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'result_slips'::REGCLASS
          AND conname = 'result_slips_file_path_check'
          AND LOWER(pg_get_constraintdef(oid)) LIKE '%is not null%'
    ), 'result_slips.file_path allows malformed non-null paths';

    ASSERT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgrelid = 'profiles'::REGCLASS
          AND tgname = 'enforce_profile_role_boundary'
          AND NOT tgisinternal
    ), 'profile role-escalation trigger missing';

    ASSERT (
        SELECT LOWER(qual) LIKE '%is_superadmin%'
           AND LOWER(with_check) LIKE '%is_superadmin%'
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'feature_flags'
          AND policyname = 'feature_flags: superadmin writes'
    ), 'ordinary admins can still mutate feature flags directly';

    ASSERT NOT has_table_privilege(
        'authenticated', 'security_principals', 'SELECT'
    ) AND NOT has_table_privilege(
        'authenticated', 'security_principals', 'UPDATE'
    ), 'security principal mapping is exposed to authenticated clients';

    ASSERT (
        SELECT rowsecurity
        FROM pg_tables
        WHERE schemaname = 'public'
          AND tablename = 'student_storage_cleanup_queue'
    ), 'Storage cleanup queue is missing or lacks RLS';
    ASSERT NOT has_table_privilege(
        'authenticated', 'student_storage_cleanup_queue', 'SELECT'
    ) AND NOT has_table_privilege(
        'authenticated', 'student_storage_cleanup_queue', 'INSERT'
    ), 'Storage cleanup queue is exposed to authenticated clients';
    ASSERT NOT has_function_privilege(
        'authenticated', 'invoke_student_storage_cleanup()', 'EXECUTE'
    ) AND NOT has_function_privilege(
        'service_role', 'invoke_student_storage_cleanup()', 'EXECUTE'
    ), 'cleanup worker invoker is directly callable through the Data API';
    ASSERT POSITION('storage_cleanup_invoke_secret' IN v_invoke_cleanup) > 0
       AND POSITION('missing or invalid' IN v_invoke_cleanup) > 0
       AND POSITION('timeout_milliseconds := 120000' IN v_invoke_cleanup) > 0,
        'Storage cleanup invocation lacks fail-closed auth or a usable timeout';

    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        ASSERT EXISTS (
            SELECT 1 FROM cron.job
            WHERE jobname = 'student-storage-cleanup'
              AND schedule = '*/15 * * * *'
              AND active
        ), 'student Storage cleanup cron is missing or inactive';
    END IF;

    ASSERT (
        SELECT COUNT(*) = 0
        FROM pg_policies
        WHERE schemaname = 'public'
          AND (
                (tablename = 'students'
                 AND policyname = 'students: parent can read own children')
                OR (tablename = 'classes'
                    AND policyname = 'classes: parent reads children''s classes')
                OR (tablename = 'enrollments'
                    AND policyname = 'enrollments: parent reads own children')
                OR (tablename = 'sessions'
                    AND policyname = 'sessions: parent reads children''s sessions')
                OR (tablename = 'attendance_records'
                    AND policyname = 'attendance_records: parent reads own children')
              )
    ), 'parent base-table policies still expose staff-only columns';

    ASSERT (
        SELECT COUNT(*) = 8
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname IN (
              'get_parent_children',
              'get_parent_attendance_history',
              'get_parent_attendance_summary',
              'get_parent_result_slips',
              'get_parent_messages',
              'get_parent_dismissals',
              'submit_parent_result_slip',
              'send_parent_message'
          )
          AND p.prosecdef
    ), 'parent-safe projections are missing or not SECURITY DEFINER';
    ASSERT POSITION('avatar_url' IN v_parent_children) = 0,
        'parent child projection exposes raw Storage object paths';
    ASSERT POSITION('parent_portal' IN v_parent_results) > 0
       AND POSITION('parent_owns_student' IN v_parent_results) > 0
       AND POSITION('parent_portal' IN v_parent_messages) > 0
       AND POSITION('parent_owns_student' IN v_parent_messages) > 0
       AND POSITION('push_notifications' IN v_parent_dismissals) > 0
       AND POSITION('parent_owns_student' IN v_parent_dismissals) > 0,
        'parent specialty projections ignore flags or current child links';
    ASSERT POSITION('parent_result_slip' IN v_submit_parent_result) > 0
       AND POSITION('pg_advisory_xact_lock' IN v_submit_parent_result) > 0
       AND POSITION('parent_message' IN v_send_parent_message) > 0
       AND POSITION('pg_advisory_xact_lock' IN v_send_parent_message) > 0,
        'parent-created rows lack server-side rate and integrity gates';

    ASSERT (
        SELECT LOWER(qual) LIKE '%parent_portal%'
           AND LOWER(qual) LIKE '%parent_id = auth.uid()%'
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'parent_student_links'
          AND policyname = 'parent_student_links: parent reads own'
    ), 'parent-link reads ignore the portal or caller identity';
    ASSERT NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND (
              (tablename = 'consent_records'
               AND policyname = 'consent_records: parent reads own child')
              OR (tablename = 'correction_requests'
                  AND policyname IN (
                      'correction_requests: parent reads own child',
                      'correction_requests: parent creates own child'
                  ))
              OR (tablename = 'awards'
                  AND policyname = 'awards: parent reads own child')
          )
    ), 'parent base-table policies expose compliance or staff provenance';
    ASSERT POSITION('parent_portal' IN v_mark_safely_home) > 0
       AND POSITION('push_notifications' IN v_mark_safely_home) > 0
       AND POSITION('parent_owns_student' IN v_mark_safely_home) > 0,
        'safely-home mutation ignores the parent feature boundaries';

    ASSERT POSITION('notify_parent_invoke_secret' IN v_notify_attendance) > 0
       AND POSITION('authorization' IN v_notify_attendance) = 0
       AND POSITION('old.status is not distinct from new.status' IN v_notify_attendance) > 0
       AND POSITION('new.status not in (''late'', ''absent'')' IN v_notify_attendance) > 0
       AND POSITION('missing or invalid' IN v_notify_attendance) > 0
       AND POSITION('timeout_milliseconds := 30000' IN v_notify_attendance) > 0,
        'attendance notification auth/deduplication/status/timeout is incomplete';

    ASSERT POSITION('notify_parent_invoke_secret' IN v_notify_dismissal) > 0
       AND POSITION('authorization' IN v_notify_dismissal) = 0
       AND POSITION('missing or invalid' IN v_notify_dismissal) > 0
       AND POSITION('timeout_milliseconds := 30000' IN v_notify_dismissal) > 0,
        'dismissal notification auth/timeout is not fail-closed and isolated';

    ASSERT (
        SELECT LOWER(with_check) LIKE '%is_feature_enabled%awards%'
        FROM pg_policies
        WHERE tablename = 'awards' AND policyname = 'awards: admin only'
    ), 'awards writes are not flag-gated';

    ASSERT (
        SELECT LOWER(qual) LIKE '%data_protection_notice%'
        FROM pg_policies
        WHERE tablename = 'policy_documents'
          AND policyname = 'policy_documents: anon read current'
    ), 'anonymous policy documents expose internal documents';

    ASSERT (
        SELECT LOWER(qual) LIKE '%is_admin%'
           AND LOWER(qual) LIKE '%data_protection_notice%'
        FROM pg_policies
        WHERE tablename = 'policy_documents'
          AND policyname = 'policy_documents: auth read'
    ), 'authenticated non-admins can read internal policy documents';
END;
$$;

NOTIFY pgrst, 'reload schema';
