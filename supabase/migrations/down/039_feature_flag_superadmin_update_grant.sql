-- down/039_feature_flag_superadmin_update_grant.sql — reverse of 039.

BEGIN;

REVOKE UPDATE ON TABLE public.feature_flags FROM authenticated;

COMMIT;
