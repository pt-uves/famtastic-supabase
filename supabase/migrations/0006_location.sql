-- ============================================================================
-- ENUMS
-- ============================================================================

DROP TYPE IF EXISTS location_entity_type CASCADE;
CREATE TYPE location_entity_type AS ENUM ('member', 'child');

-- ============================================================================
-- TABLES
-- ============================================================================

-- ----------------------------------------------------------------------------
-- latest_locations
-- One row per tracked entity. Upserted on every location update.
-- Used for the live family map — fast single-row lookup per entity.
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.latest_locations (
    id                  UUID                        PRIMARY KEY DEFAULT uuid_generate_v7(),
    entity_type         location_entity_type        NOT NULL,
    entity_id           UUID                        NOT NULL,
    location            GEOGRAPHY(POINT, 4326)      NOT NULL,
    accuracy_meters     FLOAT,
    recorded_at         TIMESTAMPTZ                 NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ----------------------------------------------------------------------------
-- location_history
-- Append-only log of all location pings. Used for track replay and SOS
-- context. Retention policy (e.g. 30 days) should be applied via a scheduled
-- job or pg_cron — not enforced at schema level.
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.location_history (
    id                  UUID                        PRIMARY KEY DEFAULT uuid_generate_v7(),
    entity_type         location_entity_type        NOT NULL,
    entity_id           UUID                        NOT NULL,
    location            GEOGRAPHY(POINT, 4326)      NOT NULL,
    accuracy_meters     FLOAT,
    recorded_at         TIMESTAMPTZ                 NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- INDEXES / CONSTRAINTS
-- ============================================================================

-- Only one current-location row per entity (supports UPSERT pattern).
CREATE UNIQUE INDEX IF NOT EXISTS uk_latest_locations_entity
    ON public.latest_locations (entity_type, entity_id);

-- Location history ordered by time per entity — the primary query pattern.
CREATE INDEX IF NOT EXISTS idx_location_history_entity_time
    ON public.location_history (entity_type, entity_id, recorded_at DESC);

-- PostGIS spatial index for map bounding-box queries on current positions.
CREATE INDEX IF NOT EXISTS idx_latest_locations_geom
    ON public.latest_locations USING GIST (location);

-- ============================================================================
-- RLS POLICIES
-- ============================================================================

ALTER TABLE public.latest_locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.location_history ENABLE ROW LEVEL SECURITY;

-- POLICIES — latest_locations

DROP POLICY IF EXISTS "latest_locations_select_policy" ON public.latest_locations;
CREATE POLICY "latest_locations_select_policy" ON public.latest_locations
    FOR SELECT USING (
        -- Own location always visible to self
        entity_id = auth.uid()
        -- Member locations: visible to other members linked to the same child
        OR (entity_type = 'member' AND EXISTS (
            SELECT 1 FROM public.memberships m1
            JOIN public.memberships m2 ON m2.child_id = m1.child_id
            WHERE m1.account_id = entity_id
              AND m2.account_id = auth.uid()
              AND m1.invite_status = 'accepted'
              AND m2.invite_status = 'accepted'
        ))
        -- Child locations: visible to all linked members
        OR (entity_type = 'child' AND is_linked_to_child(entity_id))
        OR is_platform_admin()
    );

DROP POLICY IF EXISTS "latest_locations_upsert_policy" ON public.latest_locations;
CREATE POLICY "latest_locations_upsert_policy" ON public.latest_locations
    FOR ALL USING (entity_id = auth.uid())
    WITH CHECK (entity_id = auth.uid());

-- POLICIES — location_history

DROP POLICY IF EXISTS "location_history_select_policy" ON public.location_history;
CREATE POLICY "location_history_select_policy" ON public.location_history
    FOR SELECT USING (
        entity_id = auth.uid()
        OR (entity_type = 'child' AND is_linked_to_child(entity_id))
        OR is_platform_admin()
    );

DROP POLICY IF EXISTS "location_history_insert_policy" ON public.location_history;
CREATE POLICY "location_history_insert_policy" ON public.location_history
    FOR INSERT WITH CHECK (entity_id = auth.uid());

-- ============================================================================
-- COMMENTS SECTION
-- ============================================================================

COMMENT ON TYPE  location_entity_type                      IS 'Distinguishes whether a location row belongs to a member (adult) or a child.';

COMMENT ON TABLE  public.latest_locations                       IS 'Current location of each tracked entity. One row per entity, upserted on every ping. Powers the live family map.';
COMMENT ON COLUMN public.latest_locations.id                    IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN public.latest_locations.entity_type          IS 'Member (adult profile) or child.';
COMMENT ON COLUMN public.latest_locations.entity_id            IS 'UUID of the profiles or children row.';
COMMENT ON COLUMN public.latest_locations.location             IS 'Current position as GEOGRAPHY POINT (SRID 4326, WGS 84).';
COMMENT ON COLUMN public.latest_locations.accuracy_meters      IS 'GPS accuracy radius reported by the device.';
COMMENT ON COLUMN public.latest_locations.recorded_at          IS 'Timestamp of the location fix on the device.';

COMMENT ON TABLE  public.location_history                       IS 'Append-only log of all location pings. Used for track replay and SOS context. Apply a retention cron job to limit growth.';
COMMENT ON COLUMN public.location_history.id                    IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN public.location_history.entity_type          IS 'Member (adult profile) or child.';
COMMENT ON COLUMN public.location_history.entity_id            IS 'UUID of the profiles or children row.';
COMMENT ON COLUMN public.location_history.location             IS 'Position as GEOGRAPHY POINT (SRID 4326, WGS 84).';
COMMENT ON COLUMN public.location_history.accuracy_meters      IS 'GPS accuracy radius reported by the device.';
COMMENT ON COLUMN public.location_history.recorded_at          IS 'Timestamp of the location fix on the device.';
