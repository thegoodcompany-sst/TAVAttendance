-- 035_parent_portal_writes.sql
--
-- Phase 2 parent portal: parents can upload result slips and message the
-- centre. Adds the missing INSERT policies (table + storage); reads were
-- already granted in 011. Feature stays dark behind the parent_portal flag.

-- ── result_slips: parent uploads for own child ───────────────
CREATE POLICY "result_slips: parent uploads own child"
    ON result_slips FOR INSERT TO authenticated
    WITH CHECK (
        is_parent()
        AND parent_owns_student(student_id)
        AND uploaded_by = auth.uid()
    );

-- Storage: parents may write into their child's folder (first path
-- segment = student_id, same convention as the existing read policy).
CREATE POLICY "result-slips: parent upload own child"
    ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (
        bucket_id = 'result-slips'
        AND is_parent()
        AND parent_owns_student(((storage.foldername(name))[1])::uuid)
    );

-- ── messages: parent sends about own child ───────────────────
-- Threads are keyed by student_id; the existing participant-read policy
-- (011) already lets both sides read the thread. Admin FOR ALL (002)
-- covers centre replies.
CREATE POLICY "messages: parent sends about own child"
    ON messages FOR INSERT TO authenticated
    WITH CHECK (
        is_parent()
        AND sender_id = auth.uid()
        AND student_id IS NOT NULL
        AND parent_owns_student(student_id)
    );

CREATE INDEX IF NOT EXISTS idx_messages_student_sent
    ON messages (student_id, sent_at DESC);
CREATE INDEX IF NOT EXISTS idx_result_slips_student_uploaded
    ON result_slips (student_id, uploaded_at DESC);

-- Verification (DEVOPS-02): abort if this migration did not fully apply.
DO $$
BEGIN
    ASSERT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'result_slips'
                   AND policyname = 'result_slips: parent uploads own child'),
           'result_slips parent insert policy missing after 035';
    ASSERT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'storage'
                   AND tablename = 'objects'
                   AND policyname = 'result-slips: parent upload own child'),
           'result-slips storage insert policy missing after 035';
    ASSERT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'messages'
                   AND policyname = 'messages: parent sends about own child'),
           'messages parent insert policy missing after 035';
    ASSERT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_messages_student_sent'),
           'idx_messages_student_sent missing after 035';
END;
$$;

NOTIFY pgrst, 'reload schema';
