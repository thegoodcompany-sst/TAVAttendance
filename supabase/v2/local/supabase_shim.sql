-- Local-only Auth stand-ins. Never install in a hosted project.
BEGIN;
DO $$
BEGIN
  IF inet_server_port() IS DISTINCT FROM 55432 OR inet_server_addr() NOT IN ('127.0.0.1'::inet,'::1'::inet) THEN
    RAISE EXCEPTION 'Local shim requires the throwaway server';
  END IF;
  IF to_regclass('auth.users') IS NOT NULL THEN
    IF NOT EXISTS (SELECT FROM pg_constraint WHERE conrelid='auth.users'::regclass AND contype='p' AND conkey=ARRAY[(SELECT attnum FROM pg_attribute WHERE attrelid='auth.users'::regclass AND attname='id')]::smallint[])
      OR (SELECT count(*) FROM information_schema.columns WHERE table_schema='auth' AND table_name='users') <> 4
      OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='auth' AND table_name='users' AND column_name='id' AND data_type='uuid')
      OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='auth' AND table_name='users' AND column_name='email' AND data_type='text')
      OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='auth' AND table_name='users' AND column_name='raw_user_meta_data' AND data_type='jsonb')
      OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='auth' AND table_name='users' AND column_name='created_at' AND data_type='timestamp with time zone') THEN
      RAISE EXCEPTION 'Incompatible auth.users: refusing local shim';
    END IF;
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN BYPASSRLS; END IF;
END $$;
CREATE SCHEMA IF NOT EXISTS auth;
CREATE TABLE IF NOT EXISTS auth.users (
 id uuid PRIMARY KEY, email text, raw_user_meta_data jsonb DEFAULT '{}', created_at timestamptz DEFAULT now()
);
CREATE OR REPLACE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE SET search_path=pg_catalog AS $$
 SELECT coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb
$$;
CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE SET search_path=pg_catalog AS $$
 SELECT nullif(auth.jwt()->>'sub','')::uuid
$$;
GRANT USAGE ON SCHEMA public,auth TO anon,authenticated,service_role;
REVOKE ALL ON auth.users FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION auth.jwt(),auth.uid() TO anon,authenticated,service_role;
COMMIT;
