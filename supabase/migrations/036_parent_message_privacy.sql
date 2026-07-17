-- 036_parent_message_privacy.sql
--
-- A child may have multiple linked parents. Direct messages must be visible
-- only to the parent who sent or received them, not every parent of the child.

DROP POLICY IF EXISTS "messages: participant reads own" ON messages;

CREATE POLICY "messages: participant reads own"
    ON messages FOR SELECT TO authenticated
    USING (
        sender_id = auth.uid()
        OR recipient_id = auth.uid()
        OR is_admin()
    );

DO $$
BEGIN
    ASSERT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'messages'
          AND policyname = 'messages: participant reads own'
          AND qual NOT LIKE '%parent_owns_student%'
    ), 'messages participant policy still exposes sibling parent threads after 036';
END;
$$;

NOTIFY pgrst, 'reload schema';
