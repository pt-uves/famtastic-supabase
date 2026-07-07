# Supabase Migration Guide — famtastic

> **The single source of truth for all database operations on this project.**
> Every developer must read this document before touching the database.

---

## Table of Contents

1. [Core Philosophy](#core-philosophy)
2. [Prerequisites](#prerequisites)
3. [Initial Setup (First Time)](#initial-setup-first-time)
4. [Daily Development Workflow](#daily-development-workflow)
5. [Creating Migrations](#creating-migrations)
6. [Migration Naming & Structure](#migration-naming--structure)
7. [RLS Policies](#rls-policies)
8. [Working with Functions & Triggers](#working-with-functions--triggers)
9. [Seed Data](#seed-data)
10. [Deploying to Production](#deploying-to-production)
11. [Working with Multiple Developers](#working-with-multiple-developers)
12. [TypeScript Type Generation](#typescript-type-generation)
13. [Rollback Strategy](#rollback-strategy)
14. [Troubleshooting](#troubleshooting)
15. [Command Reference](#command-reference)
16. [Rules — The Non-Negotiables](#rules--the-non-negotiables)

---

## Core Philosophy

```
⛔ No SQL Editor  →  ✅ Migration File  →  ✅ Git Commit  →  ✅ db:push
```

The `supabase/` folder **is** the database. Every schema change, every index, every
policy, and every function lives as a SQL file in `supabase/migrations/`. If it is
not in a migration file, it does not exist officially.

**One-way flow:**

```
Developer's local machine  →  Staging (optional)  →  Production
```

Changes **never** go backwards (production → local via manual edits).

---

## Prerequisites

| Tool           | Minimum Version | Install                                                                             |
| -------------- | --------------- | ----------------------------------------------------------------------------------- |
| Supabase CLI   | `>= 1.200.0`    | `npm i -g supabase` or [docs](https://supabase.com/docs/guides/cli/getting-started) |
| Docker Desktop | Latest          | [docker.com](https://docker.com)                                                    |
| Node.js        | `>= 18`         | [nodejs.org](https://nodejs.org)                                                    |
| Git            | Any             | [git-scm.com](https://git-scm.com)                                                  |

Verify your install:

```bash
supabase --version
docker info
node --version
```

---

## Initial Setup (First Time)

### 1. Clone the repository

```bash
git clone <repo-url>
cd famtastic
```

### 2. Configure environment variables

```bash
cp .env.example .env
# Open .env and fill in your Supabase project credentials
```

### 3. Install Node dependencies

```bash
npm install
```

### 4. Register the Git hook (prevents bad pushes)

```bash
git config core.hooksPath .githooks
```

### 5. Start the local Supabase stack

```bash
npm run db:start
# First run downloads Docker images — takes 2–5 minutes.
# Subsequent starts are instant.
```

### 6. Apply all migrations and seed data

```bash
npm run db:reset
# This runs all migrations in order, then applies supabase/seed.sql
```

### 7. Link to your remote project (for pushing to production)

```bash
npm run db:link
# Requires SUPABASE_PROJECT_REF in your .env
```

Your local database is now ready. Access the local Studio at:

- **Studio UI:** http://127.0.0.1:54323
- **API URL:** http://127.0.0.1:54321
- **DB URL:** postgresql://postgres:postgres@127.0.0.1:54322/postgres

---

## Daily Development Workflow

### When you start a work session

```bash
# 1. Pull latest changes from teammates
git pull origin main

# 2. Reset local DB to apply any new migrations from teammates
npm run db:reset
```

### When you want to change the schema

> Always use migrations. Never use the Studio SQL Editor for schema changes.

```bash
# 1. Create a new migration file
npm run db:new -- add_family_members_table

# 2. Open the generated file and write your SQL
# supabase/migrations/20260707123456_add_family_members_table.sql

# 3. Apply and test it
npm run db:reset

# 4. Commit
git add supabase/migrations/
git commit -m "feat(db): add family members table with RLS policies"

# 5. Push (the pre-push hook validates your migration filenames)
git push
```

---

## Creating Migrations

### Method 1: Code-first (recommended)

Write SQL manually — total control, clearest history.

```bash
npm run db:new -- <descriptive_name>
```

This creates: `supabase/migrations/YYYYMMDDHHMMSS_descriptive_name.sql`

Open the file and write your SQL. Use `supabase/templates/` for boilerplate.

### Method 2: Diff-based

Make schema changes via the local Studio UI, then capture the diff.

```bash
# After making changes in the local Studio at http://127.0.0.1:54323
npm run db:diff:file -- <descriptive_name>
```

> ⚠️ **Always review the generated diff.** `supabase db diff` can include noise
> (extensions, comments, etc.) that should not be committed.

---

## Migration Naming & Structure

### Filename format

```
YYYYMMDDHHMMSS_descriptive_snake_case_name.sql
```

Examples:

- `0001_uuid_generate_v7.sql` ← Initial schema setup
- `0002_identity_and_family.sql`
- `0003_checkins_nudges.sql`
- `20260710120000_create_rewards_table.sql` ← New timestamped migration
- `20260715093000_add_location_tracking.sql`
- `20260720140000_rls_tasks_family_owns.sql`
- `20260721090000_fn_handle_new_user.sql`
- `20260725000000_idx_tasks_assignee_id.sql`

### Naming prefixes (optional but helpful for large schemas)

| Prefix    | Used for                         |
| --------- | -------------------------------- |
| `create_` | New table                        |
| `alter_`  | Modify existing table/column     |
| `drop_`   | Remove object                    |
| `rls_`    | Row Level Security policies only |
| `fn_`     | Functions and triggers           |
| `idx_`    | Indexes only                     |
| `view_`   | Views                            |
| `seed_`   | Static reference/lookup data     |

### Migration content rules

Every migration file MUST be:

1. **Idempotent** — safe to run more than once:
   - Use `CREATE TABLE IF NOT EXISTS`
   - Use `CREATE OR REPLACE FUNCTION`
   - Use `CREATE INDEX IF NOT EXISTS`
   - Use `DROP POLICY IF EXISTS` before `CREATE POLICY`
   - Use `ALTER TABLE … ADD COLUMN IF NOT EXISTS`

2. **Focused** — one logical change per migration.
   - ✅ `20260710120000_create_family_members_table.sql` — table + indexes + RLS + triggers
   - ❌ Combining unrelated changes in one file

3. **Non-destructive** (for production):
   - Add columns with defaults or `NOT NULL DEFAULT <value>`
   - Never drop a column in the same migration that creates a replacement
   - Use `deleted_at` soft-deletes instead of hard deletes in production

4. **Primary Keys**:
   - Always use `UUIDv7` for primary keys.
   - Use `default public.uuid_generate_v7()` (do NOT use `uuidv4` or `gen_random_uuid()`).

---

## RLS Policies

> **RLS must be enabled on every table.** A table without RLS is accessible to
> anyone with the anon key.

### Rule of thumb

```sql
-- Always enable RLS
ALTER TABLE public.<table> ENABLE ROW LEVEL SECURITY;

-- Always have at least one policy or explicitly allow nothing
-- (No policies + RLS enabled = deny all — which may be intentional)
```

### Standard policy patterns

```sql
-- Own-row access (most common)
CREATE POLICY "users can select own rows"
  ON public.profiles FOR SELECT
  USING (id = auth.uid());

-- Family read (e.g., family tasks)
CREATE POLICY "family members can read tasks"
  ON public.tasks FOR SELECT
  USING (family_id IN (SELECT family_id FROM public.family_members WHERE profile_id = auth.uid()));

-- Authenticated users only
CREATE POLICY "authenticated users can insert check-ins"
  ON public.checkins FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL);

-- Service role bypass (for backend jobs)
CREATE POLICY "service role full access"
  ON public.tasks
  USING (auth.role() = 'service_role');
```

See `supabase/templates/rls_policy.sql` for more patterns.

---

## Working with Functions & Triggers

All custom functions go in the `private` schema to keep them off the REST API:

```sql
CREATE OR REPLACE FUNCTION private.my_function()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''  -- REQUIRED for SECURITY DEFINER functions
AS $$
BEGIN
  -- ...
END;
$$;
```

> ⚠️ **Always set `search_path = ''`** on `SECURITY DEFINER` functions to prevent
> search path injection attacks.

Triggers follow this pattern:

```sql
CREATE OR REPLACE TRIGGER trg_<table>_<event>
  BEFORE UPDATE ON public.<table>
  FOR EACH ROW
  EXECUTE FUNCTION private.set_updated_at();
```

See `supabase/templates/function_trigger.sql` for a complete template.

---

## Seed Data

`supabase/seed.sql` is **local development only**. It runs automatically after
`npm run db:reset`.

Rules:

- ✅ Use fixed UUIDs so references are stable
- ✅ Use `ON CONFLICT DO NOTHING` for idempotency
- ✅ Use realistic but fake data (names, emails, etc.)
- ❌ No real user data
- ❌ No production secrets
- ❌ Never run against production

```sql
-- Good seed pattern
INSERT INTO public.profiles (id, display_name)
VALUES ('00000000-0000-0000-0000-000000000001', 'Alice Dev')
ON CONFLICT (id) DO NOTHING;
```

---

## Deploying to Production

We do not use automated CI/CD for deployments. All migrations to production must be run manually from your local machine.

```bash
# 1. Make sure you're linked to production
npm run db:link

# 2. Preview what will be applied
npm run db:push:dry-run

# 3. Apply
npm run db:push

# If something goes wrong, see Rollback Strategy below.
```

> ⚠️ **Never run `npm run db:reset` against production.** It wipes the database.

---

## Working with Multiple Developers

### The golden rule

> **`git pull` → `npm run db:reset`**
> Always reset after pulling to apply teammates' migrations.

### Concurrent migration conflicts

If two developers create migrations at the same second:

1. The one with the **earlier timestamp wins** (migrations apply in lexicographic order)
2. If timestamps conflict: coordinate with your team, rename one file to use a later timestamp, then update `supabase_migrations` history if needed

To avoid conflicts:

- Communicate in your team channel before starting schema work
- Keep migrations small and focused — shorter review cycle = less overlap

### Schema drift

If production has changes not in migrations (e.g., someone used the SQL Editor):

```bash
# Pull the current remote schema into a migration file
supabase db pull --schema public

# Review the generated file, then commit it
git add supabase/migrations/
git commit -m "fix(db): capture schema drift from production"
```

---

## TypeScript Type Generation

After migrations are applied, regenerate TypeScript types:

```bash
# From local database
npm run types:generate

# From remote/production database
npm run types:generate:remote
```

Types are generated to `src/lib/database.types.ts`.

> ⚠️ **Important**: We do not generate types automatically in CI. You must run `npm run types:generate` locally after making schema changes and commit the updated `database.types.ts` file.

---

## Rollback Strategy

> Supabase does not support automatic rollback. Plan forward-migrations carefully.

### Strategy A: Forward-fix migration (preferred)

Write a new migration that undoes the breaking change:

```bash
npm run db:new -- revert_add_broken_column
# Write the reversal SQL in the new migration
npm run db:push
```

### Strategy B: Point-in-time recovery (for data loss)

Supabase Pro and above offers PITR (Point-in-Time Recovery).
Use the Dashboard → Database → Backups to restore to a specific timestamp.

> ⚠️ PITR restores the entire database — coordinate with the team before doing this.

### Prevention is better than rollback

- Always test with `npm run db:reset` before pushing
- Always use `--dry-run` before `db:push`
- Enable the "required reviews" branch protection rule
- Use the production GitHub Environment for manual approval gates

---

## Troubleshooting

### `supabase db push` fails with "migration history mismatch"

Someone made a manual change in the SQL Editor. Fix with:

```bash
# See the state of remote migrations
supabase migration list

# Mark a migration as applied without running it
supabase migration repair --status applied <timestamp>

# Or mark as reverted to re-run it
supabase migration repair --status reverted <timestamp>
```

### Local stack won't start

```bash
# Check Docker is running
docker info

# Restart the stack
supabase stop
supabase start

# Nuclear option: reset everything
supabase stop --no-backup
supabase start
npm run db:reset
```

### `supabase start` says "port already in use"

Another service is using Supabase's ports. Check `supabase/config.toml` and change
the conflicting port, or stop the other service.

### Types are out of sync after migration

```bash
npm run types:generate
```

### A migration was applied to production but shouldn't have been

Use **Strategy B** (PITR) above if data was corrupted.
If schema only: write a forward-fix migration.

---

## Command Reference

| Command                          | Description                                   |
| -------------------------------- | --------------------------------------------- |
| `npm run db:start`               | Start local Supabase stack (Docker)           |
| `npm run db:stop`                | Stop local Supabase stack                     |
| `npm run db:status`              | Show local stack URLs and status              |
| `npm run db:reset`               | Wipe local DB, re-apply all migrations + seed |
| `npm run db:new -- <name>`       | Create a new empty migration file             |
| `npm run db:diff:file -- <name>` | Capture local DB changes as a migration       |
| `npm run db:diff`                | Show unapplied diff (no file created)         |
| `npm run db:push`                | Apply pending migrations to linked remote     |
| `npm run db:push:dry-run`        | Preview what would be applied (safe)          |
| `npm run db:link`                | Link CLI to your remote Supabase project      |
| `npm run db:pull`                | Pull remote schema into a migration file      |
| `npm run db:lint`                | Lint SQL migrations for errors                |
| `npm run types:generate`         | Generate TypeScript types from local DB       |
| `npm run types:generate:remote`  | Generate TypeScript types from remote DB      |

---

## Rules — The Non-Negotiables

> Violating these rules creates schema drift, breaks CI, and puts production at risk.

| #   | Rule                                                                             |
| --- | -------------------------------------------------------------------------------- |
| 1   | **Never use the Supabase SQL Editor to modify schema in production.**            |
| 2   | **Every database change must be a migration file committed to Git.**             |
| 3   | **Always run `npm run db:reset` after `git pull` to apply new migrations.**      |
| 4   | **Never delete or modify a migration file that has been pushed to production.**  |
| 5   | **Never run `db:reset` against a production database.**                          |
| 6   | **All new tables must have RLS enabled with at least one explicit policy.**      |
| 7   | **Always use `--dry-run` before pushing to production manually.**                |
| 8   | **Secrets and real user data must never appear in migration files or seed.sql.** |
| 9   | **All primary keys must use `default public.uuid_generate_v7()`.**               |

---

_Last updated: 2026-07-07 — famtastic team_
