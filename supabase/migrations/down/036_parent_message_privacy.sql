-- down/036_parent_message_privacy.sql — reverse of 036.

DROP POLICY IF EXISTS "messages: participant reads own" ON messages;

CREATE POLICY "messages: participant reads own"
    ON messages FOR SELECT TO authenticated
    USING (
        sender_id = auth.uid()
        OR recipient_id = auth.uid()
        OR (is_parent() AND student_id IS NOT NULL AND parent_owns_student(student_id))
    );

NOTIFY pgrst, 'reload schema';
