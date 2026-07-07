 -- ============================================================================
-- ENUMS (if any)
-- ============================================================================

DROP TYPE IF EXISTS sos_status CASCADE;
CREATE TYPE sos_status AS ENUM ('active','resolved');

-- ============================================================================
-- TABLES
-- ============================================================================

CREATE TABLE IF NOT EXISTS emergency_contacts (
  id uuid primary key default public.uuid_generate_v7(),
  family_id uuid not null references families(id) on delete cascade,
  name text not null,
  phone text not null,
  relation text,
  created_at timestamptz not null default CURRENT_TIMESTAMP,
  updated_at timestamptz not null default CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS sos_alerts (
  id uuid primary key default public.uuid_generate_v7(),
  family_id uuid not null references families(id) on delete cascade,
  triggered_by uuid not null references family_members(id),
  lat double precision,
  lng double precision,
  status sos_status not null default 'active',
  resolved_by uuid references family_members(id),
  resolved_at timestamptz,
  created_at timestamptz not null default CURRENT_TIMESTAMP,
  updated_at timestamptz not null default CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS sos_cooldowns (
  member_id uuid primary key references family_members(id) on delete cascade,
  last_triggered_at timestamptz not null default CURRENT_TIMESTAMP,
  created_at timestamptz not null default CURRENT_TIMESTAMP,
  updated_at timestamptz not null default CURRENT_TIMESTAMP
);

-- ============================================================================
-- INDEXES / CONSTRAINTS
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_emergency_contacts_family ON emergency_contacts (family_id);
CREATE INDEX IF NOT EXISTS idx_sos_alerts_family_status ON sos_alerts (family_id, status);

-- ============================================================================
-- COMMENTS SECTION
-- ============================================================================

COMMENT ON TABLE emergency_contacts IS 'Emergency contacts for the family.';
COMMENT ON COLUMN emergency_contacts.id IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN emergency_contacts.family_id IS 'Family ID.';
COMMENT ON COLUMN emergency_contacts.name IS 'Contact name.';
COMMENT ON COLUMN emergency_contacts.phone IS 'Contact phone number.';
COMMENT ON COLUMN emergency_contacts.relation IS 'Relationship to the family.';
COMMENT ON COLUMN emergency_contacts.created_at IS 'Record creation timestamp.';
COMMENT ON COLUMN emergency_contacts.updated_at IS 'Last update timestamp.';

COMMENT ON TABLE sos_alerts IS 'SOS alerts triggered by members.';
COMMENT ON COLUMN sos_alerts.id IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN sos_alerts.family_id IS 'Family ID.';
COMMENT ON COLUMN sos_alerts.triggered_by IS 'Member who triggered the alert.';
COMMENT ON COLUMN sos_alerts.lat IS 'Latitude at time of trigger.';
COMMENT ON COLUMN sos_alerts.lng IS 'Longitude at time of trigger.';
COMMENT ON COLUMN sos_alerts.status IS 'Alert status.';
COMMENT ON COLUMN sos_alerts.resolved_by IS 'Member who resolved the alert.';
COMMENT ON COLUMN sos_alerts.resolved_at IS 'Resolution timestamp.';
COMMENT ON COLUMN sos_alerts.created_at IS 'Record creation timestamp.';
COMMENT ON COLUMN sos_alerts.updated_at IS 'Last update timestamp.';

COMMENT ON TABLE sos_cooldowns IS 'Cooldowns to prevent spamming SOS.';
COMMENT ON COLUMN sos_cooldowns.member_id IS 'Member ID (primary key).';
COMMENT ON COLUMN sos_cooldowns.last_triggered_at IS 'Timestamp of last SOS trigger.';
COMMENT ON COLUMN sos_cooldowns.created_at IS 'Record creation timestamp.';
COMMENT ON COLUMN sos_cooldowns.updated_at IS 'Last update timestamp.';
