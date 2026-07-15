-- ============================================================================
-- EXTENSIONS
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pg_trgm SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_cron SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_net SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS supabase_vault WITH SCHEMA vault;

-- ============================================================================
-- API ROLE GRANTS
--
-- PostgREST checks table/function GRANTs BEFORE Row Level Security. Without a
-- base grant to the API roles, every request fails with "permission denied"
-- (42501) regardless of RLS - so RLS never even runs. This establishes the
-- standard Supabase grant baseline: broad table privileges to the API roles,
-- with RLS remaining the real row-level gate (service_role bypasses RLS by
-- design). Running it here - before any tables are created - means the DEFAULT
-- PRIVILEGES below cause every table/sequence/function in later migrations to
-- inherit the same baseline automatically.
-- Idempotent: GRANT and ALTER DEFAULT PRIVILEGES are safe to re-run.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Schema usage
-- ----------------------------------------------------------------------------

GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- Existing objects
-- ----------------------------------------------------------------------------

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public
    TO anon, authenticated, service_role;

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public
    TO anon, authenticated, service_role;

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public
    TO anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- Future objects - keep the baseline in place for later migrations
-- ----------------------------------------------------------------------------

ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO anon, authenticated, service_role;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT USAGE, SELECT ON SEQUENCES TO anon, authenticated, service_role;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role;

-- ============================================================================
-- COMMENTS SECTION
-- ============================================================================

COMMENT ON EXTENSION postgis IS 'PostGIS geometry and geography types - used for location tracking and SOS location snapshots.';
COMMENT ON EXTENSION pg_trgm IS 'Trigram matching - backs the GIN index on families.name for fast case-insensitive substring search in the admin portal.';
COMMENT ON EXTENSION pg_cron IS 'PostgreSQL cron extension for scheduling background jobs.';
COMMENT ON EXTENSION pg_net IS 'PostgreSQL networking extension for calling external APIs/Edge Functions.';
COMMENT ON EXTENSION pgcrypto IS 'Cryptographic functions - used for bcrypt hashing of the Child Mode exit PIN (crypt/gen_salt).';
COMMENT ON EXTENSION supabase_vault IS 'Encrypted secret storage; holds edge_base_url and push_webhook_secret for server-side edge-function calls (notification dispatch).';

COMMENT ON SCHEMA public IS
    'Application schema. API roles (anon, authenticated, service_role) hold broad table/function grants (see migration 0002); Row Level Security is the real per-row access gate. service_role bypasses RLS.';
