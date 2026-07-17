-- down/035_parent_portal_writes.sql — reverse of 035.

DROP POLICY IF EXISTS "result_slips: parent uploads own child" ON result_slips;
DROP POLICY IF EXISTS "result-slips: parent upload own child" ON storage.objects;
DROP POLICY IF EXISTS "messages: parent sends about own child" ON messages;
DROP INDEX IF EXISTS idx_messages_student_sent;
DROP INDEX IF EXISTS idx_result_slips_student_uploaded;

NOTIFY pgrst, 'reload schema';
