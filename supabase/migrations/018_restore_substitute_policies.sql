-- 018_restore_substitute_policies.sql
--
-- The drift detector's first live run (2026-07-10) found prod has NO
-- substitute-tutor RLS policies: the 2026-07-09 reconciliation backfilled
-- 005's columns and functions but missed these policies (005/010 were never
-- applied to prod as files). Without them an assigned sub_tutor silently sees
-- no sessions and cannot mark attendance. Restore the 010 (SEC-04,
-- TO authenticated) versions verbatim.

DROP POLICY IF EXISTS "substitute_can_read_session"    ON sessions;
DROP POLICY IF EXISTS "substitute_can_mark_attendance" ON attendance_records;

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

-- Verification (DEVOPS-02): abort if this migration did not fully apply.
DO $$
BEGIN
    ASSERT (SELECT count(*) = 2 FROM pg_policies
            WHERE (tablename = 'sessions'           AND policyname = 'substitute_can_read_session')
               OR (tablename = 'attendance_records' AND policyname = 'substitute_can_mark_attendance')),
           'substitute policies missing after 018';
    ASSERT (SELECT bool_and('authenticated' = ANY (roles)) FROM pg_policies
            WHERE policyname IN ('substitute_can_read_session', 'substitute_can_mark_attendance')),
           'substitute policies not scoped TO authenticated';
END $$;
