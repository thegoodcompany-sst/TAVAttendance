-- down/048_record_parent_boundary_read_grants.sql — reverse of 048.

BEGIN;

REVOKE SELECT ON TABLE
    public.parent_student_links,
    public.classes,
    public.result_slips,
    public.messages,
    public.dismissals,
    public.awards
FROM authenticated;

COMMIT;
