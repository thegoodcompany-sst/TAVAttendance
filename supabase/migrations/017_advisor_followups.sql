-- ============================================================
-- 017 — Advisor follow-ups from the 2026-07-09 prod drift campaign
-- ============================================================
-- Closes the three non-accepted security advisor findings that surfaced after
-- applying 013–016 to prod (they exist on local too):
--
--   ADV-17a  check_session_not_ended (recreated in 016) had a mutable
--            search_path — every other function was pinned in 009/013/016.
--   ADV-17b  class_punctuality is SECURITY DEFINER with NO internal role
--            guard and was executable by anon/PUBLIC via PostgREST — an
--            anonymous caller could read attendance aggregates. 009's revoke
--            pass predated its presence on prod and never listed it.
--   ADV-17c  link/unlink_parent_student were executable by anon/PUBLIC
--            (they self-guard with an admin check, but anon has no business
--            reaching them; matches the 009 convention).
--
-- Down migration: 017_advisor_followups.down.sql

-- ADV-17a
ALTER FUNCTION check_session_not_ended() SET search_path = public;

-- ADV-17b
REVOKE EXECUTE ON FUNCTION class_punctuality(UUID, DATE, DATE) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION class_punctuality(UUID, DATE, DATE) TO authenticated, service_role;

-- ADV-17c
REVOKE EXECUTE ON FUNCTION link_parent_student(UUID, UUID)   FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION unlink_parent_student(UUID, UUID) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION link_parent_student(UUID, UUID)   TO authenticated, service_role;
GRANT  EXECUTE ON FUNCTION unlink_parent_student(UUID, UUID) TO authenticated, service_role;
