-- down/022_advisor_followups_021.sql — reverse of 022.

DROP EXTENSION IF EXISTS pg_net;
CREATE EXTENSION pg_net;
GRANT EXECUTE ON FUNCTION notify_parent_on_attendance() TO anon, authenticated;
