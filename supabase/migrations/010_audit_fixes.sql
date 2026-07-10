-- ============================================================
-- 010_audit_fixes.sql
-- Addresses findings from security & maintenance audit
-- Applied: 2026-06-15
--
-- Findings addressed:
--   SEC-03  class_punctuality SECURITY DEFINER with no caller auth guard
--   SEC-04  substitute policies missing TO authenticated (defaulted to PUBLIC)
--   SEC-06  sync_attendance trusts client-supplied marked_at (no upper clamp)
--   MAINT-01 dismissals table has no unique key on (session_id, student_id)
--   MAINT-08 attendance_summary counts inactive students/classes
--   SP-07   get_session_roster does not return late_reason
--   SEC-10  audit triggers missing for profiles and classes tables
--   PERF-05 missing indexes on sessions, attendance_records, enrollments
-- ============================================================


-- ════════════════════════════════════════════════════════════════
-- SEC-03 — class_punctuality: add caller authorization guard
-- ════════════════════════════════════════════════════════════════
-- Original: 005_sprint_features.sql:62-95 (SECURITY DEFINER, no auth check)
-- Fix: raise exception if caller is neither admin nor assigned tutor for the class.
-- The rest of the function body is reproduced exactly.

CREATE OR REPLACE FUNCTION class_punctuality(
    p_class_id UUID,
    p_from     DATE,
    p_to       DATE
)
RETURNS TABLE (
    present_count  BIGINT,
    late_count     BIGINT,
    absent_count   BIGINT,
    excused_count  BIGINT,
    total_count    BIGINT,
    on_time_rate   NUMERIC   -- 0.0–1.0, NULL when total = 0
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Authorization guard: caller must be admin OR the assigned tutor for this class.
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
$$;

-- Re-grant execute (was granted in 005; preserve it)
GRANT EXECUTE ON FUNCTION class_punctuality(UUID, DATE, DATE) TO authenticated;


-- ════════════════════════════════════════════════════════════════
-- SEC-04 — substitute policies: add TO authenticated clause
-- ════════════════════════════════════════════════════════════════
-- Original policies in 005_sprint_features.sql:22-42 used no role clause,
-- defaulting to PUBLIC (which includes anon).
-- Fix: drop and recreate with TO authenticated, preserving exact USING/WITH CHECK.

DROP POLICY IF EXISTS "substitute_can_read_session"     ON sessions;
DROP POLICY IF EXISTS "substitute_can_mark_attendance"  ON attendance_records;

CREATE POLICY "substitute_can_read_session"
    ON sessions FOR SELECT
    TO authenticated
    USING (sub_tutor_id = auth.uid());

CREATE POLICY "substitute_can_mark_attendance"
    ON attendance_records FOR ALL
    TO authenticated
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


-- ════════════════════════════════════════════════════════════════
-- SEC-06 — sync_attendance: clamp client-supplied marked_at
-- ════════════════════════════════════════════════════════════════
-- Original: 003_functions_triggers.sql:127-177
-- Fix: clamp the incoming marked_at to LEAST(<incoming>, NOW() + INTERVAL '5 minutes')
-- so a client cannot forge a future timestamp.
-- All other logic (ON CONFLICT WHERE guard, synced/skipped counters, COALESCE fallback)
-- is reproduced exactly. search_path pinned (per 009_security_hardening.sql).

CREATE OR REPLACE FUNCTION sync_attendance(records JSONB)
RETURNS JSONB LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    rec            JSONB;
    v_id           UUID;
    synced         INT := 0;
    skipped        INT := 0;
    v_marked_at    TIMESTAMPTZ;
BEGIN
    FOR rec IN SELECT * FROM jsonb_array_elements(records)
    LOOP
        -- Clamp: do not allow a client to record a marked_at more than 5 minutes in the future.
        v_marked_at := LEAST(
            COALESCE((rec->>'marked_at')::TIMESTAMPTZ, NOW()),
            NOW() + INTERVAL '5 minutes'
        );

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
    END LOOP;

    RETURN jsonb_build_object(
        'synced',  synced,
        'skipped', skipped
    );
END;
$$;

-- Re-grant (was granted in 009_security_hardening.sql; preserve it)
GRANT EXECUTE ON FUNCTION sync_attendance(JSONB) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION sync_attendance(JSONB) FROM PUBLIC, anon;


-- ════════════════════════════════════════════════════════════════
-- MAINT-01 — dismissals: add unique constraint (session_id, student_id)
-- ════════════════════════════════════════════════════════════════
-- The dismissals table (001_schema.sql:199-207) has no unique key.
-- Before adding the constraint, remove duplicate rows keeping the latest
-- by dismissed_at (or by max ctid if dismissed_at is NULL/tied).

DO $$
BEGIN
    -- Dedup: for each (session_id, student_id) group, keep only the row
    -- with the greatest dismissed_at; on ties, keep the greatest ctid.
    DELETE FROM dismissals
    WHERE ctid NOT IN (
        SELECT DISTINCT ON (session_id, student_id)
               ctid
        FROM   dismissals
        ORDER  BY session_id,
                  student_id,
                  dismissed_at DESC NULLS LAST,
                  ctid DESC
    );

    -- Add unique constraint only if it doesn't already exist.
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'dismissals_session_student_unique'
          AND conrelid = 'dismissals'::regclass
    ) THEN
        ALTER TABLE dismissals
            ADD CONSTRAINT dismissals_session_student_unique
            UNIQUE (session_id, student_id);
    END IF;
END;
$$;


-- ════════════════════════════════════════════════════════════════
-- MAINT-08 — attendance_summary: filter to active students/classes
-- ════════════════════════════════════════════════════════════════
-- Original: 007_security_invoker_view.sql:6-28 (security_invoker = true)
-- Fix: add WHERE st.is_active = TRUE AND c.is_active = TRUE
-- Aliases from the existing view: s=attendance_records, st=students,
-- se=sessions, c=classes. attendance_pct formula preserved exactly.

CREATE OR REPLACE VIEW attendance_summary
WITH (security_invoker = true)
AS
SELECT
    s.student_id,
    st.full_name                                                     AS student_name,
    se.class_id,
    c.name                                                           AS class_name,
    COUNT(*)                                                         AS total_sessions,
    COUNT(*) FILTER (WHERE s.status = 'present')                    AS present_count,
    COUNT(*) FILTER (WHERE s.status = 'late')                       AS late_count,
    COUNT(*) FILTER (WHERE s.status = 'absent')                     AS absent_count,
    COUNT(*) FILTER (WHERE s.status = 'excused')                    AS excused_count,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE s.status IN ('present','late','excused'))
        / NULLIF(COUNT(*), 0),
        1
    )                                                                AS attendance_pct
FROM attendance_records s
JOIN students st  ON st.id = s.student_id
JOIN sessions se  ON se.id = s.session_id
JOIN classes  c   ON c.id  = se.class_id
WHERE st.is_active = TRUE
  AND c.is_active  = TRUE
GROUP BY s.student_id, st.full_name, se.class_id, c.name;


-- ════════════════════════════════════════════════════════════════
-- SP-07 — get_session_roster: add late_reason to returned columns
-- ════════════════════════════════════════════════════════════════
-- Original: 003_functions_triggers.sql:95-117
-- Fix: add late_reason TEXT to RETURNS TABLE and to the SELECT list (ar.late_reason).
-- All other columns, ordering, and joins preserved exactly.
-- search_path pinned (per 009_security_hardening.sql).
-- (2026-07-10, HUMANS.md §36: DROP added — OR REPLACE cannot change a return
-- type, which made the chain non-replayable; prod never ran this file as-is)

DROP FUNCTION IF EXISTS get_session_roster(UUID);
CREATE FUNCTION get_session_roster(p_session_id UUID)
RETURNS TABLE (
    student_id      UUID,
    full_name       TEXT,
    attendance_id   UUID,
    status          TEXT,
    marked_at       TIMESTAMPTZ,
    notes           TEXT,
    late_reason     TEXT
) LANGUAGE SQL STABLE
SET search_path = public
AS $$
    SELECT
        st.id            AS student_id,
        st.full_name,
        ar.id            AS attendance_id,
        ar.status,
        ar.marked_at,
        ar.notes,
        ar.late_reason
    FROM sessions se
    JOIN enrollments e  ON e.class_id  = se.class_id AND e.is_active = TRUE
    JOIN students    st ON st.id       = e.student_id AND st.is_active = TRUE
    LEFT JOIN attendance_records ar ON ar.session_id = se.id AND ar.student_id = st.id
    WHERE se.id = p_session_id
    ORDER BY st.full_name;
$$;

-- Re-grant (was granted in 009_security_hardening.sql; preserve it)
GRANT EXECUTE ON FUNCTION get_session_roster(UUID) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION get_session_roster(UUID) FROM PUBLIC, anon;


-- ════════════════════════════════════════════════════════════════
-- SEC-10 — Audit triggers for profiles and classes tables
-- ════════════════════════════════════════════════════════════════
-- Pattern from 003_functions_triggers.sql:29-43: DROP IF EXISTS then CREATE.
-- audit_trigger_func() is the shared trigger function used for all tables.
-- profiles: track INSERT (via handle_new_user trigger), UPDATE, DELETE
-- classes:  track INSERT, UPDATE, DELETE
-- Note: existing set_updated_at_profiles and set_updated_at_classes triggers
-- are BEFORE UPDATE triggers — these new audit triggers are AFTER, no conflict.

DROP TRIGGER IF EXISTS audit_profiles ON profiles;
CREATE TRIGGER audit_profiles
    AFTER INSERT OR UPDATE OR DELETE ON profiles
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_func();

DROP TRIGGER IF EXISTS audit_classes ON classes;
CREATE TRIGGER audit_classes
    AFTER INSERT OR UPDATE OR DELETE ON classes
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_func();


-- ════════════════════════════════════════════════════════════════
-- PERF-05 — Missing indexes
-- ════════════════════════════════════════════════════════════════
-- sessions(class_id, session_date): 001_schema.sql:119 already has
--   UNIQUE (class_id, session_date) which creates this exact composite index.
--   Omitting to avoid redundancy.

-- sessions(session_date) — useful for date-range queries across all classes
CREATE INDEX IF NOT EXISTS idx_sessions_session_date
    ON sessions (session_date);

-- attendance_records(student_id) — useful for per-student history lookups
CREATE INDEX IF NOT EXISTS idx_attendance_records_student_id
    ON attendance_records (student_id);

-- enrollments(class_id) — full index for general class roster lookups
CREATE INDEX IF NOT EXISTS idx_enrollments_class_id
    ON enrollments (class_id);

-- enrollments(class_id) WHERE is_active = TRUE — partial index for active-only queries
-- (named distinctly from the full index above)
CREATE INDEX IF NOT EXISTS idx_enrollments_class_id_active
    ON enrollments (class_id)
    WHERE is_active = TRUE;
