-- Set the passwords of the Supabase image's service roles at first start.
\getenv password POSTGRES_PASSWORD
ALTER ROLE authenticator PASSWORD :'password';
ALTER ROLE supabase_auth_admin PASSWORD :'password';
ALTER ROLE supabase_storage_admin PASSWORD :'password';
