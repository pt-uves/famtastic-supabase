-- ============================================================================
-- set-vault-secret.sql — insert OR update ONE Vault secret by name.
--
-- Generic + idempotent: pass any (name, value) pair. Touches only vault.secrets,
-- never application data, so it is safe to run against prod without a db reset.
-- Driven in bulk by scripts/set-vault-secrets.sh (one invocation per secret),
-- so adding a new secret is a new line in the env file — no change here.
--
--   psql "$DB_URL" -v name="edge_base_url" -v value="https://x.supabase.co" \
--     -f supabase/scripts/set-vault-secret.sql
--
-- Two plain SELECTs, not a DO block: psql does NOT substitute :'vars' inside
-- $$-quoted blocks.
-- ============================================================================

\set ON_ERROR_STOP on

-- Update if it already exists (0 rows -> no-op)...
SELECT vault.update_secret(id, :'value')
FROM vault.secrets
WHERE name = :'name';

-- ...otherwise create it.
SELECT vault.create_secret(:'value', :'name')
WHERE NOT EXISTS (SELECT 1 FROM vault.secrets WHERE name = :'name');
