-- down/051_record_award_insert_grant.sql — reverse of 051.

BEGIN;

REVOKE INSERT ON TABLE public.awards FROM authenticated;

COMMIT;
