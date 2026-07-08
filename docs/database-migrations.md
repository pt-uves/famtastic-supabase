# Database Migrations

## Required SQL Structure

Every migration file must follow this exact layout:

```sql
-- ----------------------------------------------------------------------------
-- ENUMS (if any)
-- ----------------------------------------------------------------------------

DROP TYPE IF EXISTS your_enum_type CASCADE;
CREATE TYPE your_enum_type AS ENUM ('value1', 'value2', 'value3');

-- ----------------------------------------------------------------------------
-- TABLES
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS your_table (
    id              UUID             PRIMARY KEY DEFAULT uuid_generate_v7(),
    name            TEXT             NOT NULL,
    status          your_enum_type   NOT NULL DEFAULT 'value1',
    created_at      TIMESTAMPTZ      NOT NULL DEFAULT CURRENT_TIMESTAMP
    -- updated_at      TIMESTAMPTZ      NOT NULL DEFAULT CURRENT_TIMESTAMP -- Add only if needed, update manually
);

-- ----------------------------------------------------------------------------
-- INDEXES / CONSTRAINTS
-- ----------------------------------------------------------------------------

ALTER TABLE your_table DROP CONSTRAINT IF EXISTS fk_your_table_parent;
ALTER TABLE your_table ADD CONSTRAINT fk_your_table_parent
    FOREIGN KEY (parent_id) REFERENCES parent_table (id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_your_table_status ON your_table (status);
CREATE UNIQUE INDEX IF NOT EXISTS uk_your_table_name ON your_table (name);

-- ----------------------------------------------------------------------------
-- TRIGGERS
-- ----------------------------------------------------------------------------

-- Note: We do NOT use triggers for updated_at. It should be updated manually.
-- Example of a custom trigger:
DROP TRIGGER IF EXISTS trigger_your_table_custom ON your_table;
CREATE TRIGGER trigger_your_table_custom
    BEFORE INSERT ON your_table
    FOR EACH ROW
    EXECUTE FUNCTION some_custom_function();

-- ============================================================================
-- COMMENTS SECTION
-- ============================================================================

COMMENT ON TABLE your_table IS 'Description shown in GraphQL docs.';
COMMENT ON COLUMN your_table.id IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN your_table.name IS 'Display name.';
COMMENT ON COLUMN your_table.status IS 'Lifecycle status.';
COMMENT ON COLUMN your_table.created_at IS 'Record creation timestamp.';
-- COMMENT ON COLUMN your_table.updated_at IS 'Last update timestamp.';
-- Repeat COMMENT ON TABLE and COMMENT ON COLUMN for milam_ and omnigrowthos_ tables
```

## Section Header Format

- Major sections: `-- ============================================================================`
- Minor sections: `-- ----------------------------------------------------------------------------`
- Small separators: `-- -------------------------------------------------------------------------`

## Idempotency Rules

Every statement must be safe to run multiple times:

| Object       | Idempotent form                                                                                  |
| ------------ | ------------------------------------------------------------------------------------------------ |
| Table        | `CREATE TABLE IF NOT EXISTS`                                                                     |
| Index        | `CREATE INDEX IF NOT EXISTS`                                                                     |
| Unique index | `CREATE UNIQUE INDEX IF NOT EXISTS`                                                              |
| Foreign key  | `DROP CONSTRAINT IF EXISTS` then `ADD CONSTRAINT`                                                |
| Trigger      | `DROP TRIGGER IF EXISTS` then `CREATE TRIGGER`                                                   |
| Policy       | `DROP POLICY IF EXISTS` then `CREATE POLICY`                                                     |
| Enum         | `DROP TYPE IF EXISTS ... CASCADE` then `CREATE TYPE`                                             |
| Column add   | `DO $$ BEGIN ALTER TABLE ... ADD COLUMN ...; EXCEPTION WHEN duplicate_column THEN NULL; END $$;` |

Use `uuid_generate_v7()` — never `gen_random_uuid()` or `uuid_generate_v4()`.

## Naming Conventions

| Object            | Pattern                        | Example                          |
| ----------------- | ------------------------------ | -------------------------------- |
| Table             | `<name>`                       | `store_visits`                   |
| Index             | `idx_<table>_<col>`            | `idx_store_visits_status`        |
| Unique constraint | `uk_<table>_<col>`             | `uk_users_email`                 |
| Foreign key       | `fk_<table>_<referenced>`      | `fk_orders_customer`             |
| Trigger           | `trigger_<table>_<purpose>`    | `trigger_orders_calculate_total` |
| Policy            | `"<table>_<operation>_policy"` | `"orders_select_policy"`         |

## Comments Section (Mandatory)

Every migration must end with a `COMMENTS SECTION`. Provide:

- `COMMENT ON TABLE` for every new table (all 3 tenants)
- `COMMENT ON COLUMN` for every column in every new table (all 3 tenants)
- `COMMENT ON FUNCTION` with `@sortable` tag for computed column functions where sorting should be enabled in PostGraphile
