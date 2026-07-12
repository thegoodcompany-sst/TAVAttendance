-- 027_awards_unique.sql
--
-- Close the duplicate-award race flagged in the 2026-07-12 review: the web
-- giveAward action does check-then-insert, so two concurrent admins could
-- file the same award twice. DB constraint makes the duplicate impossible.

ALTER TABLE awards
    ADD CONSTRAINT awards_student_type_period_key
    UNIQUE (student_id, award_type, period);

-- Verification (DEVOPS-02): abort if this migration did not fully apply.
DO $$
BEGIN
    ASSERT (SELECT EXISTS (
                SELECT FROM pg_constraint
                WHERE conname = 'awards_student_type_period_key')),
           'unique constraint missing after 027';
END $$;
