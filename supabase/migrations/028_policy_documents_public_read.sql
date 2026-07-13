-- 028: allow anonymous read of the current published privacy notice.
-- The web /privacy page moves outside the auth gate (Apple App Review
-- requires a publicly reachable privacy policy URL). Only current docs
-- are exposed; drafts/superseded versions stay authenticated-only.

CREATE POLICY "policy_documents: anon read current"
  ON policy_documents FOR SELECT
  TO anon
  USING (is_current = TRUE);
