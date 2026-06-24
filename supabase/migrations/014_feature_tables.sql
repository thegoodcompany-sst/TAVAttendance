-- ============================================================
-- 014 — Feature tables for flag-gated work + PERF-06 roster RPC
-- ============================================================
-- Schema for PROD-04 (student photos) and PROD-02 (push notifications).
-- Everything here is inert until the matching feature flag (012) is on:
-- the columns/tables simply exist; no behaviour changes for current users.
-- Parent-portal (PROD-01) needs no new schema — parent read RLS for
-- students/attendance_records already exists in 002_rls.sql.
-- Down migration: 014_feature_tables.down.sql

-- ════════════════════════════════════════════════════════════════
-- PROD-04 — student avatar photos
-- ════════════════════════════════════════════════════════════════
ALTER TABLE students ADD COLUMN IF NOT EXISTS avatar_url TEXT;

-- Private bucket; admins upload, any authenticated user may read (tutors on
-- the roster, parents on the portal). Path convention mirrors result-slips:
-- "<student_id>/<file>".
INSERT INTO storage.buckets (id, name, public)
VALUES ('student-photos', 'student-photos', FALSE)
ON CONFLICT (id) DO UPDATE SET public = FALSE;

DROP POLICY IF EXISTS "student-photos: admin all"   ON storage.objects;
DROP POLICY IF EXISTS "student-photos: auth read"   ON storage.objects;

CREATE POLICY "student-photos: admin all"
    ON storage.objects FOR ALL TO authenticated
    USING (bucket_id = 'student-photos' AND is_admin())
    WITH CHECK (bucket_id = 'student-photos' AND is_admin());

CREATE POLICY "student-photos: auth read"
    ON storage.objects FOR SELECT TO authenticated
    USING (bucket_id = 'student-photos');

-- ════════════════════════════════════════════════════════════════
-- PROD-02 — device tokens for parent push notifications
-- ════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS device_tokens (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    token      TEXT NOT NULL,
    platform   TEXT NOT NULL CHECK (platform IN ('ios', 'android', 'web')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (token)
);
CREATE INDEX IF NOT EXISTS idx_device_tokens_user ON device_tokens (user_id);

ALTER TABLE device_tokens ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "device_tokens: owner manages own" ON device_tokens;
CREATE POLICY "device_tokens: owner manages own"
    ON device_tokens FOR ALL TO authenticated
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

-- ════════════════════════════════════════════════════════════════
-- PERF-06 — pre-aggregated roster RPC (replaces the unbounded nested
-- select in web/lib/queries.ts getRosterForDate)
-- ════════════════════════════════════════════════════════════════
-- Returns one row per student for the date, with the "worst" status across
-- all of that student's sessions (rank: late > present > absent > excused >
-- none) and the array of class names. SECURITY INVOKER so the caller's RLS
-- applies (the web caller is admin-only and sees all rows).
CREATE OR REPLACE FUNCTION get_roster_for_date(p_date DATE)
RETURNS TABLE (
    student_id  UUID,
    full_name   TEXT,
    class_names TEXT[],
    status      TEXT,
    marked_at   TIMESTAMPTZ
)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path = public
AS $$
    WITH roster AS (
        SELECT
            st.id        AS student_id,
            st.full_name AS full_name,
            c.name       AS class_name,
            ar.status    AS status,
            ar.marked_at AS marked_at,
            CASE ar.status
                WHEN 'late'    THEN 4
                WHEN 'present' THEN 3
                WHEN 'absent'  THEN 2
                WHEN 'excused' THEN 1
                ELSE 0
            END          AS rank
        FROM sessions se
        JOIN classes c     ON c.id = se.class_id
        JOIN enrollments e ON e.class_id = se.class_id AND e.is_active = TRUE
        JOIN students st   ON st.id = e.student_id AND st.is_active = TRUE
        LEFT JOIN attendance_records ar
               ON ar.session_id = se.id AND ar.student_id = st.id
        WHERE se.session_date = p_date
    ),
    agg AS (
        SELECT student_id, full_name,
               array_agg(DISTINCT class_name ORDER BY class_name) AS class_names
        FROM roster
        GROUP BY student_id, full_name
    ),
    winner AS (
        SELECT DISTINCT ON (student_id) student_id, status, marked_at
        FROM roster
        ORDER BY student_id, rank DESC, marked_at DESC NULLS LAST
    )
    SELECT a.student_id, a.full_name, a.class_names, w.status, w.marked_at
    FROM agg a
    JOIN winner w USING (student_id)
    ORDER BY a.full_name;
$$;

GRANT EXECUTE ON FUNCTION get_roster_for_date(DATE) TO authenticated, service_role;

-- ════════════════════════════════════════════════════════════════
-- PROD-04 — add avatar_url to get_session_roster (so the kiosk card can
-- show a photo when the student_photos flag is on). Extends the 010 version;
-- all other columns/joins/ordering preserved.
-- ════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION get_session_roster(p_session_id UUID)
RETURNS TABLE (
    student_id      UUID,
    full_name       TEXT,
    attendance_id   UUID,
    status          TEXT,
    marked_at       TIMESTAMPTZ,
    notes           TEXT,
    late_reason     TEXT,
    avatar_url      TEXT
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
        ar.late_reason,
        st.avatar_url
    FROM sessions se
    JOIN enrollments e  ON e.class_id  = se.class_id AND e.is_active = TRUE
    JOIN students    st ON st.id       = e.student_id AND st.is_active = TRUE
    LEFT JOIN attendance_records ar ON ar.session_id = se.id AND ar.student_id = st.id
    WHERE se.id = p_session_id
    ORDER BY st.full_name;
$$;

GRANT EXECUTE ON FUNCTION get_session_roster(UUID) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION get_session_roster(UUID) FROM PUBLIC, anon;
