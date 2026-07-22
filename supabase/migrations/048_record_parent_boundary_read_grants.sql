-- Migration 048: record production SELECT privileges needed to reach the
-- parent-facing RLS boundaries during clean migration replay.

BEGIN;

GRANT SELECT ON TABLE
    public.parent_student_links,
    public.classes,
    public.result_slips,
    public.messages,
    public.dismissals,
    public.awards
TO authenticated;

DO $$
DECLARE
    v_table TEXT;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'parent_student_links', 'classes', 'result_slips',
        'messages', 'dismissals', 'awards'
    ] LOOP
        ASSERT has_table_privilege(
            'authenticated', 'public.' || v_table, 'SELECT'
        ), 'authenticated lacks SELECT on ' || v_table;
        ASSERT (
            SELECT relrowsecurity
            FROM pg_class
            WHERE oid = ('public.' || v_table)::REGCLASS
        ), v_table || ' RLS is disabled';
    END LOOP;
END
$$;

COMMIT;
