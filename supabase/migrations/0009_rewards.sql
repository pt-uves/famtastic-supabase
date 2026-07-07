-- ============================================================================
-- ENUMS (if any)
-- ============================================================================

DROP TYPE IF EXISTS redemption_status CASCADE;
CREATE TYPE redemption_status AS ENUM ('pending','approved','denied');

-- ============================================================================
-- TABLES
-- ============================================================================

CREATE TABLE IF NOT EXISTS points_ledger (
  id uuid primary key default public.uuid_generate_v7(),
  child_id uuid not null references family_members(id) on delete cascade,
  delta int not null,
  reason text,
  created_at timestamptz not null default CURRENT_TIMESTAMP,
  updated_at timestamptz not null default CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS badges (
  id uuid primary key default public.uuid_generate_v7(),
  name text not null,
  description text,
  icon_url text,
  created_at timestamptz not null default CURRENT_TIMESTAMP,
  updated_at timestamptz not null default CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS child_badges (
  id uuid primary key default public.uuid_generate_v7(),
  child_id uuid not null references family_members(id) on delete cascade,
  badge_id uuid not null references badges(id) on delete cascade,
  earned_at timestamptz not null default CURRENT_TIMESTAMP,
  created_at timestamptz not null default CURRENT_TIMESTAMP,
  updated_at timestamptz not null default CURRENT_TIMESTAMP,
  unique (child_id, badge_id)
);

CREATE TABLE IF NOT EXISTS reward_shop_items (
  id uuid primary key default public.uuid_generate_v7(),
  family_id uuid references families(id) on delete cascade,
  name text not null,
  cost_points int not null,
  icon_url text,
  created_at timestamptz not null default CURRENT_TIMESTAMP,
  updated_at timestamptz not null default CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS reward_redemptions (
  id uuid primary key default public.uuid_generate_v7(),
  child_id uuid not null references family_members(id) on delete cascade,
  item_id uuid not null references reward_shop_items(id),
  status redemption_status not null default 'pending',
  approved_by uuid references family_members(id),
  created_at timestamptz not null default CURRENT_TIMESTAMP,
  updated_at timestamptz not null default CURRENT_TIMESTAMP
);

-- ============================================================================
-- INDEXES / CONSTRAINTS
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_points_ledger_child_created ON points_ledger (child_id, created_at desc);

-- ============================================================================
-- COMMENTS SECTION
-- ============================================================================

COMMENT ON TABLE points_ledger IS 'Append-only ledger for points.';
COMMENT ON COLUMN points_ledger.id IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN points_ledger.child_id IS 'Child ID.';
COMMENT ON COLUMN points_ledger.delta IS 'Points change (positive or negative).';
COMMENT ON COLUMN points_ledger.reason IS 'Reason for points change.';
COMMENT ON COLUMN points_ledger.created_at IS 'Record creation timestamp.';
COMMENT ON COLUMN points_ledger.updated_at IS 'Last update timestamp.';

COMMENT ON TABLE badges IS 'Global catalog of badges.';
COMMENT ON COLUMN badges.id IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN badges.name IS 'Badge name.';
COMMENT ON COLUMN badges.description IS 'Badge description.';
COMMENT ON COLUMN badges.icon_url IS 'Badge icon URL.';
COMMENT ON COLUMN badges.created_at IS 'Record creation timestamp.';
COMMENT ON COLUMN badges.updated_at IS 'Last update timestamp.';

COMMENT ON TABLE child_badges IS 'Badges earned by children.';
COMMENT ON COLUMN child_badges.id IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN child_badges.child_id IS 'Child ID.';
COMMENT ON COLUMN child_badges.badge_id IS 'Badge ID.';
COMMENT ON COLUMN child_badges.earned_at IS 'Timestamp when earned.';
COMMENT ON COLUMN child_badges.created_at IS 'Record creation timestamp.';
COMMENT ON COLUMN child_badges.updated_at IS 'Last update timestamp.';

COMMENT ON TABLE reward_shop_items IS 'Items available in the reward shop.';
COMMENT ON COLUMN reward_shop_items.id IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN reward_shop_items.family_id IS 'Family ID (null for global items).';
COMMENT ON COLUMN reward_shop_items.name IS 'Item name.';
COMMENT ON COLUMN reward_shop_items.cost_points IS 'Cost in points.';
COMMENT ON COLUMN reward_shop_items.icon_url IS 'Item icon URL.';
COMMENT ON COLUMN reward_shop_items.created_at IS 'Record creation timestamp.';
COMMENT ON COLUMN reward_shop_items.updated_at IS 'Last update timestamp.';

COMMENT ON TABLE reward_redemptions IS 'Redemption requests for reward items.';
COMMENT ON COLUMN reward_redemptions.id IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN reward_redemptions.child_id IS 'Child ID.';
COMMENT ON COLUMN reward_redemptions.item_id IS 'Item ID.';
COMMENT ON COLUMN reward_redemptions.status IS 'Redemption status.';
COMMENT ON COLUMN reward_redemptions.approved_by IS 'Member who approved the redemption.';
COMMENT ON COLUMN reward_redemptions.created_at IS 'Record creation timestamp.';
COMMENT ON COLUMN reward_redemptions.updated_at IS 'Last update timestamp.';
