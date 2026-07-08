-- ============================================================================
-- EXTENSIONS
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS postgis;

-- ============================================================================
-- COMMENTS SECTION
-- ============================================================================

COMMENT ON EXTENSION postgis IS 'PostGIS geometry and geography types — used for location tracking and SOS location snapshots.';
