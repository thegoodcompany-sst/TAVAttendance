\set ON_ERROR_STOP on
-- Local regression setup ONLY, applied after the shim and before 0001.
ALTER DEFAULT PRIVILEGES GRANT EXECUTE ON FUNCTIONS TO PUBLIC,anon,authenticated,service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.hostile_acl_probe() RETURNS boolean LANGUAGE sql AS $$ SELECT true $$;
