#!/usr/bin/env bash
#
# set-vault-secrets.sh — bulk insert/update Vault secrets from an env file.
#
# One mechanism for LOCAL and PROD. Scales without code changes: each
# `NAME=value` line in the env file becomes one idempotent upsert (via
# set-vault-secret.sql). Add a secret => add a line. It only writes
# vault.secrets, so it is safe on prod WITHOUT a db reset, and rotation-safe.
#
# LOCAL (no DB_URL, uses the running Supabase container's psql):
#   npm run db:secrets
#   # -> targets postgresql://...127.0.0.1:54322 via `docker exec`, so you do
#   #    NOT need a psql client on your host. Run it after each `db reset`.
#
# PROD / STAGING (needs a psql client on PATH):
#   export DB_URL="postgresql://postgres:...@db.<ref>.supabase.co:5432/postgres"
#   npm run db:secrets
#
# Env file (default supabase/scripts/vault-secrets.env, gitignored):
#   pass a path as the first arg to override. Copy vault-secrets.example.env.
#
# ENV FILE FORMAT (one per line; blank lines and #-comments ignored):
#   edge_base_url=http://host.docker.internal:54321
#   push_webhook_secret=some-long-random-string
#   some_future_secret=whatever
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SQL="$ROOT/scripts/set-vault-secret.sql"
ENV_FILE="${1:-$ROOT/scripts/vault-secrets.env}"
CONTAINER="${SUPABASE_DB_CONTAINER:-supabase_db_famtastic}"
LOCAL_DEFAULT="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
DB_URL="${DB_URL:-${PROD_DB_URL:-}}"

# --- Decide target + how to reach it ---------------------------------------
mode_local=0
if [ -z "$DB_URL" ]; then
  DB_URL="$LOCAL_DEFAULT"; mode_local=1
elif [[ "$DB_URL" == *127.0.0.1* || "$DB_URL" == *localhost* ]]; then
  mode_local=1
fi

use_docker=0
if command -v psql >/dev/null 2>&1; then
  use_docker=0                       # host psql available: use it everywhere
elif [ "$mode_local" -eq 1 ] && docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  use_docker=1                       # no host psql, but local container is up
else
  echo "error: 'psql' not found on PATH and no local Supabase container to fall back to." >&2
  echo "       Install a Postgres client, or start the stack ('npm run db:start') for local." >&2
  exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
  echo "error: env file not found: $ENV_FILE" >&2
  echo "       copy scripts/vault-secrets.example.env -> scripts/vault-secrets.env and fill it in." >&2
  exit 1
fi

run_psql() {   # args: -v name=.. -v value=..
  if [ "$use_docker" -eq 1 ]; then
    docker exec -i "$CONTAINER" psql -U postgres -d postgres "$@" < "$SQL"
  else
    psql "$DB_URL" "$@" -f "$SQL"
  fi
}

# --- Upsert every secret ----------------------------------------------------
[ "$use_docker" -eq 1 ] && echo "(target: local container '$CONTAINER')" || echo "(target: $DB_URL)"

count=0
while IFS= read -r line || [ -n "$line" ]; do
  # Strip leading/trailing whitespace; skip blanks and comments.
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  [ -z "$line" ] && continue
  case "$line" in \#*) continue ;; esac

  name="${line%%=*}"
  value="${line#*=}"
  name="${name%"${name##*[![:space:]]}"}"   # rtrim name

  if [ "$name" = "$line" ] || [ -z "$name" ]; then
    echo "warning: skipping malformed line (no '='): $line" >&2
    continue
  fi

  echo "-> upserting '$name'"
  run_psql -v name="$name" -v value="$value" >/dev/null
  count=$((count + 1))
done < "$ENV_FILE"

echo "Done. $count secret(s) upserted into vault.secrets."
