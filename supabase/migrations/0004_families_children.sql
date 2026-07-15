-- ============================================================================
-- ENUMS
-- ============================================================================

DROP TYPE IF EXISTS gender CASCADE;
CREATE TYPE gender AS ENUM ('male', 'female', 'other', 'prefer_not_to_say');

DROP TYPE IF EXISTS language_level CASCADE;
CREATE TYPE language_level AS ENUM ('simple', 'standard', 'full');

DROP TYPE IF EXISTS family_status CASCADE;
CREATE TYPE family_status AS ENUM ('active', 'suspended');

-- ============================================================================
-- TABLES
-- ============================================================================

-- ----------------------------------------------------------------------------
-- families
-- Created and owned by one parent (platform admin of their own family).
-- One owner = one family. A family groups the owner's own children.
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.families (
    id                  UUID          PRIMARY KEY DEFAULT uuid_generate_v7(),
    name                TEXT          NOT NULL,
    owner_id            UUID          NOT NULL,
    status              family_status NOT NULL DEFAULT 'active',
    leaderboard_enabled BOOLEAN       NOT NULL DEFAULT true,
    created_at          TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ----------------------------------------------------------------------------
-- children
-- Belongs to one family. Never logs in.
-- The parent activates Child Mode on the child's device from this record.
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.children (
    id                          UUID            PRIMARY KEY DEFAULT uuid_generate_v7(),
    family_id                   UUID            NOT NULL,
    name                        TEXT            NOT NULL,
    date_of_birth               DATE,
    gender                      gender,
    photo_path                  TEXT,
    diagnosis                   TEXT,
    special_notes               TEXT,
    language_level              language_level  NOT NULL DEFAULT 'standard',
    communication_preferences   TEXT,
    child_mode_enabled          BOOLEAN         NOT NULL DEFAULT false,
    child_mode_device_id        TEXT,
    location_sharing_enabled    BOOLEAN         NOT NULL DEFAULT true,
    created_at                  TIMESTAMPTZ     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                  TIMESTAMPTZ     NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- INDEXES / CONSTRAINTS
-- ============================================================================

-- Each owner can own only one family.
CREATE UNIQUE INDEX IF NOT EXISTS uk_families_owner ON public.families (owner_id);

-- Case-insensitive substring search on family name (admin portal family search).
CREATE INDEX IF NOT EXISTS idx_families_name_trgm
    ON public.families USING gin (name extensions.gin_trgm_ops);

ALTER TABLE public.families DROP CONSTRAINT IF EXISTS fk_families_owner;
ALTER TABLE public.families ADD CONSTRAINT fk_families_owner
    FOREIGN KEY (owner_id) REFERENCES public.profiles (id) ON DELETE CASCADE;

ALTER TABLE public.children DROP CONSTRAINT IF EXISTS fk_children_family;
ALTER TABLE public.children ADD CONSTRAINT fk_children_family
    FOREIGN KEY (family_id) REFERENCES public.families (id) ON DELETE CASCADE;

-- Queries that load all children for a family (most common read path).
CREATE INDEX IF NOT EXISTS idx_children_family_id ON public.children (family_id);

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Keep updated_at current on every change.
DROP TRIGGER IF EXISTS trigger_families_set_updated_at ON public.families;
CREATE TRIGGER trigger_families_set_updated_at
    BEFORE UPDATE ON public.families
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trigger_children_set_updated_at ON public.children;
CREATE TRIGGER trigger_children_set_updated_at
    BEFORE UPDATE ON public.children
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

-- ============================================================================
-- RLS POLICIES
-- ============================================================================

ALTER TABLE public.families ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.children ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- COMMENTS SECTION
-- ============================================================================

COMMENT ON TYPE  gender                                IS 'Gender options for a child profile.';
COMMENT ON TYPE  language_level                        IS 'Language complexity level for the child interface.';
COMMENT ON TYPE  family_status                         IS 'Whether a family is active or has been suspended by a platform admin. Suspended families lose in-app data access (enforced in the RLS helper functions).';

COMMENT ON TABLE  public.families                           IS 'A family group created and owned by one parent admin. A parent can own exactly one family.';
COMMENT ON COLUMN public.families.id                        IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN public.families.name                      IS 'Family display name chosen during onboarding.';
COMMENT ON COLUMN public.families.owner_id                  IS 'The parent admin who created and owns this family.';
COMMENT ON COLUMN public.families.status                    IS 'Active by default. Only a platform admin can set/clear ''suspended''; a suspended family''s children and data become inaccessible in-app.';
COMMENT ON COLUMN public.families.leaderboard_enabled       IS 'Whether the family leaderboard is active for this family.';
COMMENT ON COLUMN public.families.created_at                IS 'Row creation timestamp.';
COMMENT ON COLUMN public.families.updated_at                IS 'Last-modified timestamp, stamped by the set_updated_at() trigger on every update.';

COMMENT ON TABLE  public.children                           IS 'A child profile inside a family. Children never authenticate; the parent logs in and activates Child Mode on the child device.';
COMMENT ON COLUMN public.children.id                        IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN public.children.family_id                 IS 'Family this child belongs to.';
COMMENT ON COLUMN public.children.name                      IS 'Child first name or display name.';
COMMENT ON COLUMN public.children.date_of_birth             IS 'Used to calculate age for UI display and analytics.';
COMMENT ON COLUMN public.children.gender                    IS 'Child gender - stored as an enum for consistent filtering.';
COMMENT ON COLUMN public.children.photo_path                IS 'Storage object path of the child profile photo in the child-photos bucket (e.g. child-photos/{child_id}/{file}). Frontend signs on demand; never store the signed URL.';
COMMENT ON COLUMN public.children.diagnosis                 IS 'Free-text primary diagnosis (e.g. Autism, ADHD, Speech Delay).';
COMMENT ON COLUMN public.children.special_notes             IS 'Free-text notes visible to all linked members.';
COMMENT ON COLUMN public.children.language_level            IS 'UI language complexity for this child.';
COMMENT ON COLUMN public.children.communication_preferences IS 'Free-text preferences (e.g., non-verbal, uses AAC).';
COMMENT ON COLUMN public.children.child_mode_enabled        IS 'True when this child''s device is locked into Child Mode.';
COMMENT ON COLUMN public.children.child_mode_device_id      IS 'Identifies the specific device currently running Child Mode.';
COMMENT ON COLUMN public.children.location_sharing_enabled  IS 'Controlled by the parent admin. When false, child location is hidden from the family map.';
COMMENT ON COLUMN public.children.created_at                IS 'Row creation timestamp.';
COMMENT ON COLUMN public.children.updated_at                IS 'Last-modified timestamp, stamped by the set_updated_at() trigger on every update.';
