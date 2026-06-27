-- ============================================================
-- 015 — Study Space tracking + Data Protection Notice v1.1
-- ============================================================
-- Two unrelated-but-bundled changes (see plan):
--
--   A) Study Space tracking (internal-only drop-in room attendance).
--      Modelled as a single flagged class (classes.is_study_space) so it
--      reuses the existing sessions/attendance_records/offline-sync stack.
--      Gated by the `study_space_tracking` feature flag (012). Marked on the
--      iPad kiosk with Present / Not Here (= excused) only.
--
--      INVARIANT: study-space attendance is internal reference ONLY and must
--      NEVER appear in reports, report cards, or parent views. Every reporting
--      surface filters classes.is_study_space = FALSE. New report/parent queries
--      MUST do the same (documented in CLAUDE.md).
--
--   B) Data Protection Notice v1.1 — corrects the controller/entity (Talent
--      Beacon, operating TAVA — a study centre, not a "tuition centre") and the
--      published contact. Supersedes the v1.0 seeded in 011.
--
-- Down migration: 015_study_space_and_notice.down.sql
-- NOTE: prod has known schema drift (013 + part of 014 blocked) — apply with care.

-- ════════════════════════════════════════════════════════════════
-- A1 — is_study_space flag on classes
-- ════════════════════════════════════════════════════════════════
ALTER TABLE classes ADD COLUMN IF NOT EXISTS is_study_space BOOLEAN NOT NULL DEFAULT FALSE;

-- Singleton Study Space class. Fixed UUID so the iOS/Android kiosk can call
-- getOrCreateSession() against it without a lookup. schedule_day NULL → it is
-- exempt from the tuition day-filter and is shown only in the Study Space view.
INSERT INTO classes (id, name, subject, level, schedule_day, schedule_time, is_active, is_study_space)
VALUES (
    '57000000-0000-0000-0000-000000000001',
    'Study Space (Drop-in)',
    NULL, NULL, NULL, NULL, TRUE, TRUE
)
ON CONFLICT (id) DO UPDATE SET is_study_space = TRUE, is_active = TRUE;

-- ════════════════════════════════════════════════════════════════
-- A2 — feature flag (ships OFF). Auto-appears on the superadmin flags page.
-- ════════════════════════════════════════════════════════════════
INSERT INTO feature_flags (key, enabled, description) VALUES
    ('study_space_tracking', FALSE,
     'Internal Study Space (drop-in room) attendance — Present/Not Here only; excluded from all reports & parent views')
ON CONFLICT (key) DO NOTHING;

-- ════════════════════════════════════════════════════════════════
-- A3 — Study Space roster RPC: all ACTIVE students (not enrollment-based),
-- LEFT JOIN their attendance for the given session. SECURITY INVOKER so the
-- caller's RLS applies (kiosk runs as admin). Mirrors get_session_roster shape.
-- ════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION get_study_space_roster(p_session_id UUID)
RETURNS TABLE (
    student_id      UUID,
    full_name       TEXT,
    attendance_id   UUID,
    status          TEXT,
    marked_at       TIMESTAMPTZ,
    avatar_url      TEXT
) LANGUAGE SQL STABLE SECURITY INVOKER
SET search_path = public
AS $$
    SELECT
        st.id            AS student_id,
        st.full_name,
        ar.id            AS attendance_id,
        ar.status,
        ar.marked_at,
        st.avatar_url
    FROM students st
    LEFT JOIN attendance_records ar
           ON ar.session_id = p_session_id AND ar.student_id = st.id
    WHERE st.is_active = TRUE
    ORDER BY st.full_name;
$$;

GRANT EXECUTE ON FUNCTION get_study_space_roster(UUID) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION get_study_space_roster(UUID) FROM PUBLIC, anon;

-- ════════════════════════════════════════════════════════════════
-- A4 — exclude study space from reporting surfaces
-- ════════════════════════════════════════════════════════════════

-- attendance_summary view (003): never count study-space sessions.
-- Body identical to 003_functions_triggers.sql:66-86 plus the WHERE filter.
CREATE OR REPLACE VIEW attendance_summary AS
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
WHERE c.is_study_space = FALSE
GROUP BY s.student_id, st.full_name, se.class_id, c.name;

-- get_roster_for_date RPC (014): exclude study-space sessions from the
-- admin Today/Yesterday dashboard rosters. Body identical to 014:90-138 plus
-- the AND c.is_study_space = FALSE filter.
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
          AND c.is_study_space = FALSE
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
-- B — Data Protection Notice v1.1 (supersedes v1.0 from 011)
-- ════════════════════════════════════════════════════════════════
-- Retire the v1.0 notice, then publish v1.1 as current. getPrivacyNotice()
-- reads doc_type='data_protection_notice' AND is_current=true.
UPDATE policy_documents
   SET is_current = FALSE
 WHERE doc_type = 'data_protection_notice' AND version = '1.0';

INSERT INTO policy_documents (doc_type, version, title, body, is_current)
VALUES (
  'data_protection_notice',
  '1.1',
  'TAVA Attendance — Data Protection Notice',
  E'TAVA is a study centre operated by Talent Beacon, a non-profit serving youth and residents of Bukit Batok. Talent Beacon is the organisation responsible for the personal data described here and collects and uses personal data of students and their parents/guardians to run the Centre''s programmes: enrolment, attendance, results, dismissals and centre communications.\n\nFor students who are minors, we rely on consent given by a parent or legal guardian.\n\nWe retain personal data for as long as necessary for these purposes and to meet legal record-keeping obligations (up to 7 years after a student leaves), after which it is anonymised or erased.\n\nYou may request access to, or correction of, the personal data we hold, or withdraw consent, by contacting our Data Protection Officer at admin@talentbeacon.org (Talent Beacon, 209 Bukit Batok Street 21, #01-182, Singapore).\n\nData is stored in Singapore (Supabase, ap-southeast-1) and protected with encryption in transit and at rest.',
  TRUE
)
ON CONFLICT (doc_type, version) DO NOTHING;
