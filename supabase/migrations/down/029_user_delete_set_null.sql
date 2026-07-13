-- Reverse of 029: restore the provenance FKs to auth.users to NO ACTION.

DO $$
DECLARE r RECORD;
BEGIN
    FOR r IN
        SELECT c.conrelid::regclass AS tbl, c.conname, a.attname AS col
        FROM pg_constraint c
        JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY (c.conkey)
        WHERE c.contype = 'f' AND c.confrelid = 'auth.users'::regclass
          AND c.confdeltype = 'n' AND c.connamespace = 'public'::regnamespace
    LOOP
        EXECUTE format('ALTER TABLE %s DROP CONSTRAINT %I', r.tbl, r.conname);
        EXECUTE format(
            'ALTER TABLE %s ADD CONSTRAINT %I FOREIGN KEY (%I) REFERENCES auth.users(id)',
            r.tbl, r.conname, r.col);
    END LOOP;
END $$;
