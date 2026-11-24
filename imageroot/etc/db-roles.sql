-- Roles expected by the Supabase services (Auth and Storage). Idempotent:
-- it runs at every start of PostgreSQL (bin/bootstrap-db) and before a
-- database restore (actions/restore-module/40restore_database).
--
-- Role passwords come from the environment of the PostgreSQL container
-- (\getenv), so they never appear in a command line. The failing statement
-- is not logged, it would contain a password.

\set ON_ERROR_STOP on
SET log_min_error_statement = panic;

\getenv auth_pw AUTH_DB_PASSWORD
\getenv storage_pw STORAGE_DB_PASSWORD

DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'anon') THEN
        CREATE ROLE anon NOLOGIN NOINHERIT;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticated') THEN
        CREATE ROLE authenticated NOLOGIN NOINHERIT;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'service_role') THEN
        CREATE ROLE service_role NOLOGIN NOINHERIT BYPASSRLS;
    END IF;
END
$$;

SELECT format('CREATE ROLE supabase_auth_admin NOINHERIT CREATEROLE LOGIN NOREPLICATION PASSWORD %L', :'auth_pw')
    WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'supabase_auth_admin') \gexec
SELECT format('ALTER ROLE supabase_auth_admin PASSWORD %L', :'auth_pw') \gexec

SELECT format('CREATE ROLE supabase_storage_admin NOINHERIT CREATEROLE LOGIN NOREPLICATION PASSWORD %L', :'storage_pw')
    WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'supabase_storage_admin') \gexec
SELECT format('ALTER ROLE supabase_storage_admin PASSWORD %L', :'storage_pw') \gexec

-- Supabase Storage switches to these roles to enforce the access rules
GRANT anon, authenticated, service_role TO supabase_storage_admin;

ALTER ROLE supabase_auth_admin SET search_path = auth;
ALTER ROLE supabase_storage_admin SET search_path = storage;

SELECT format('GRANT CREATE ON DATABASE %I TO supabase_auth_admin, supabase_storage_admin', current_database()) \gexec
