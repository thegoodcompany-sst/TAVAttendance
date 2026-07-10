-- ============================================================
-- 017 — down migration (restores pre-017 state; see 017_advisor_followups.sql)
-- ============================================================

-- ADV-17a: unpin the search_path set by 017.
ALTER FUNCTION check_session_not_ended() RESET search_path;

-- ADV-17b/c: restore the pre-017 grants (005 granted to authenticated only,
-- but functions default to PUBLIC execute at creation).
GRANT EXECUTE ON FUNCTION class_punctuality(UUID, DATE, DATE) TO PUBLIC;
GRANT EXECUTE ON FUNCTION link_parent_student(UUID, UUID)     TO PUBLIC;
GRANT EXECUTE ON FUNCTION unlink_parent_student(UUID, UUID)   TO PUBLIC;
