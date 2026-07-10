-- ============================================================
-- 005_sprint_features.sql
-- Sprint: late notes, dismissals, recurrence, substitution,
--         punctuality analytics, bulk import, parent linking,
--         result slips subject constraint
-- ============================================================

-- ─── #3 Late reason on attendance records ────────────────────
ALTER TABLE attendance_records
    ADD COLUMN IF NOT EXISTS late_reason TEXT;

-- ─── #14 Class schedule recurrence ───────────────────────────
ALTER TABLE classes
    ADD COLUMN IF NOT EXISTS recurrence_rule TEXT,          -- RFC 5545 RRULE, e.g. FREQ=WEEKLY;BYDAY=MO
    ADD COLUMN IF NOT EXISTS recurrence_end_date DATE;      -- NULL = open-ended

-- ─── #16 Per-session substitution ────────────────────────────
ALTER TABLE sessions
    ADD COLUMN IF NOT EXISTS sub_tutor_id UUID REFERENCES auth.users(id);

-- Allow a substitute tutor to read and update sessions they cover
-- (2026-07-10, HUMANS.md §36: was CREATE POLICY IF NOT EXISTS — invalid Postgres,
-- made the chain non-replayable; prod never ran this file as-is)
DROP POLICY IF EXISTS "substitute_can_read_session" ON sessions;
CREATE POLICY "substitute_can_read_session"
    ON sessions FOR SELECT
    USING (sub_tutor_id = auth.uid());

-- Allow a substitute tutor to mark attendance for their covered sessions
DROP POLICY IF EXISTS "substitute_can_mark_attendance" ON attendance_records;
CREATE POLICY "substitute_can_mark_attendance"
    ON attendance_records FOR ALL
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

-- ─── #20 Result slips: lock subject to two values ─────────────
-- Only add the constraint if it doesn't exist yet
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'result_slips_subject_check'
    ) THEN
        ALTER TABLE result_slips
            ADD CONSTRAINT result_slips_subject_check
            CHECK (subject IS NULL OR subject IN ('Math', 'English'));
    END IF;
END;
$$;

-- ─── #8 Class punctuality analytics function ──────────────────
-- Returns aggregate attendance counts and on-time rate for a class
-- over a given date range.
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
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
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
$$;

-- Grant execute to authenticated users (RLS on underlying tables still applies)
GRANT EXECUTE ON FUNCTION class_punctuality(UUID, DATE, DATE) TO authenticated;

-- ─── #13 Parent ↔ student linking RPC ────────────────────────
-- Admin-only: inserts a row into parent_student_links.
CREATE OR REPLACE FUNCTION link_parent_student(
    p_parent  UUID,
    p_student UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Only admins may call this function
    IF NOT EXISTS (
        SELECT 1 FROM profiles
        WHERE id = auth.uid() AND role = 'admin'
    ) THEN
        RAISE EXCEPTION 'Forbidden: admin role required';
    END IF;

    INSERT INTO parent_student_links (parent_id, student_id)
    VALUES (p_parent, p_student)
    ON CONFLICT DO NOTHING;
END;
$$;

GRANT EXECUTE ON FUNCTION link_parent_student(UUID, UUID) TO authenticated;

-- ─── #13 Unlink RPC (for the toggle UI) ──────────────────────
CREATE OR REPLACE FUNCTION unlink_parent_student(
    p_parent  UUID,
    p_student UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM profiles
        WHERE id = auth.uid() AND role = 'admin'
    ) THEN
        RAISE EXCEPTION 'Forbidden: admin role required';
    END IF;

    DELETE FROM parent_student_links
    WHERE parent_id = p_parent AND student_id = p_student;
END;
$$;

GRANT EXECUTE ON FUNCTION unlink_parent_student(UUID, UUID) TO authenticated;
