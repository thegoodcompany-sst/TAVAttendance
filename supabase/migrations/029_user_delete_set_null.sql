-- 029: allow deleting auth users who have authored records
--
-- Deleting a user from the admin dashboard failed with "Database error
-- deleting user" (auth log: update or delete on table "users" violates
-- foreign key constraint "audit_log_changed_by_fkey", SQLSTATE 23503).
-- Twenty public provenance columns (marked_by, created_by, changed_by,
-- sender_id, ...) reference auth.users with the default NO ACTION, so any
-- user who ever marked attendance / created anything was undeletable.
--
-- All twenty columns are nullable: rebuild every remaining NO ACTION FK to
-- auth.users as ON DELETE SET NULL — the record survives, the author link
-- nulls out. Ownership FKs (profiles, device_tokens, parent_student_links,
-- class_tutor_assignments) already CASCADE and are untouched.

DO $$
DECLARE r RECORD;
BEGIN
    FOR r IN
        SELECT c.conrelid::regclass AS tbl, c.conname, a.attname AS col
        FROM pg_constraint c
        JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY (c.conkey)
        WHERE c.contype = 'f' AND c.confrelid = 'auth.users'::regclass
          AND c.confdeltype = 'a' AND c.connamespace = 'public'::regnamespace
    LOOP
        EXECUTE format('ALTER TABLE %s DROP CONSTRAINT %I', r.tbl, r.conname);
        EXECUTE format(
            'ALTER TABLE %s ADD CONSTRAINT %I FOREIGN KEY (%I) REFERENCES auth.users(id) ON DELETE SET NULL',
            r.tbl, r.conname, r.col);
    END LOOP;
END $$;

-- Verification (DEVOPS-02)
DO $$
BEGIN
    ASSERT NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE contype = 'f' AND confrelid = 'auth.users'::regclass
          AND confdeltype = 'a' AND connamespace = 'public'::regnamespace
    ), 'public FKs to auth.users still use NO ACTION';
    ASSERT (
        SELECT count(*) FROM pg_constraint
        WHERE contype = 'f' AND confrelid = 'auth.users'::regclass
          AND confdeltype = 'n' AND connamespace = 'public'::regnamespace
    ) >= 20, 'expected at least 20 SET NULL FKs to auth.users';
END $$;
