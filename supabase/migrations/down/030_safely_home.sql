-- down/030_safely_home.sql — reverse of 030.
-- Any safely_home_at values already written are left in place (data, not schema).

DROP TRIGGER IF EXISTS trg_notify_parent_dismissal ON dismissals;
DROP FUNCTION IF EXISTS notify_parent_on_dismissal();
DROP FUNCTION IF EXISTS mark_safely_home(UUID);

NOTIFY pgrst, 'reload schema';
