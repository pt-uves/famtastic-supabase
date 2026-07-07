-- ============================================================================
-- ENUMS (if any)
-- ============================================================================

DROP TYPE IF EXISTS location_visibility CASCADE;
CREATE TYPE location_visibility AS ENUM ('all','parents_only','none');

-- ============================================================================
-- TABLES
-- ============================================================================

CREATE TABLE IF NOT EXISTS member_locations (
  id uuid primary key default public.uuid_generate_v7(),
  member_id uuid not null references family_members(id) on delete cascade,
  lat double precision not null,
  lng double precision not null,
  recorded_at timestamptz not null default CURRENT_TIMESTAMP,
  created_at timestamptz not null default CURRENT_TIMESTAMP,
  updated_at timestamptz not null default CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS location_sharing_prefs (
  member_id uuid primary key references family_members(id) on delete cascade,
  visibility location_visibility not null default 'all',
  active_hours jsonb,
  created_at timestamptz not null default CURRENT_TIMESTAMP,
  updated_at timestamptz not null default CURRENT_TIMESTAMP
);

-- ============================================================================
-- INDEXES / CONSTRAINTS
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_member_locations_member_recorded ON member_locations (member_id, recorded_at desc);

-- ============================================================================
-- COMMENTS SECTION
-- ============================================================================

COMMENT ON TABLE member_locations IS 'Location updates for members.';
COMMENT ON COLUMN member_locations.id IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN member_locations.member_id IS 'Member ID.';
COMMENT ON COLUMN member_locations.lat IS 'Latitude.';
COMMENT ON COLUMN member_locations.lng IS 'Longitude.';
COMMENT ON COLUMN member_locations.recorded_at IS 'Timestamp of recording.';
COMMENT ON COLUMN member_locations.created_at IS 'Record creation timestamp.';
COMMENT ON COLUMN member_locations.updated_at IS 'Last update timestamp.';

COMMENT ON TABLE location_sharing_prefs IS 'Preferences for location sharing.';
COMMENT ON COLUMN location_sharing_prefs.member_id IS 'Member ID (primary key).';
COMMENT ON COLUMN location_sharing_prefs.visibility IS 'Visibility setting.';
COMMENT ON COLUMN location_sharing_prefs.active_hours IS 'JSON active hours configuration.';
COMMENT ON COLUMN location_sharing_prefs.created_at IS 'Record creation timestamp.';
COMMENT ON COLUMN location_sharing_prefs.updated_at IS 'Last update timestamp.';
