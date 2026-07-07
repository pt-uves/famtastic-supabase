-- ============================================================================
-- ENUMS (if any)
-- ============================================================================

DROP TYPE IF EXISTS mood_type CASCADE;
CREATE TYPE mood_type AS ENUM ('angry','overwhelmed','calm','happy');

DROP TYPE IF EXISTS nudge_variant CASCADE;
CREATE TYPE nudge_variant AS ENUM ('concern','encouragement','task_reminder');

-- ============================================================================
-- TABLES
-- ============================================================================

CREATE TABLE IF NOT EXISTS check_ins (
  id uuid primary key default public.uuid_generate_v7(),
  family_id uuid not null references families(id) on delete cascade,
  member_id uuid not null references family_members(id) on delete cascade,
  mood mood_type not null,
  text_response text,
  voice_note_url text,
  shared_with_family boolean not null default true,
  initiated_by uuid references family_members(id),
  created_at timestamptz not null default CURRENT_TIMESTAMP,
  updated_at timestamptz not null default CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS coping_strategies (
  id uuid primary key default public.uuid_generate_v7(),
  mood mood_type not null,
  title text not null,
  icon_url text,
  animation_key text,
  is_global boolean not null default true,
  family_id uuid references families(id) on delete cascade,
  created_at timestamptz not null default CURRENT_TIMESTAMP,
  updated_at timestamptz not null default CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS nudges (
  id uuid primary key default public.uuid_generate_v7(),
  family_id uuid not null references families(id) on delete cascade,
  from_member uuid not null references family_members(id),
  to_member uuid not null references family_members(id),
  variant nudge_variant not null,
  trigger_reason text,
  message text,
  read_at timestamptz,
  created_at timestamptz not null default CURRENT_TIMESTAMP,
  updated_at timestamptz not null default CURRENT_TIMESTAMP
);

-- ============================================================================
-- INDEXES / CONSTRAINTS
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_check_ins_family_created ON check_ins (family_id, created_at desc);
CREATE INDEX IF NOT EXISTS idx_check_ins_member_created ON check_ins (member_id, created_at desc);

CREATE INDEX IF NOT EXISTS idx_coping_strategies_family ON coping_strategies (family_id);

CREATE INDEX IF NOT EXISTS idx_nudges_family_created ON nudges (family_id, created_at desc);
CREATE INDEX IF NOT EXISTS idx_nudges_to_member ON nudges (to_member, read_at);

-- ============================================================================
-- COMMENTS SECTION
-- ============================================================================

COMMENT ON TABLE check_ins IS 'Check-ins and mood tracking.';
COMMENT ON COLUMN check_ins.id IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN check_ins.family_id IS 'Family ID.';
COMMENT ON COLUMN check_ins.member_id IS 'Member ID.';
COMMENT ON COLUMN check_ins.mood IS 'Mood selected.';
COMMENT ON COLUMN check_ins.text_response IS 'Text response.';
COMMENT ON COLUMN check_ins.voice_note_url IS 'URL for voice note.';
COMMENT ON COLUMN check_ins.shared_with_family IS 'Whether shared with family.';
COMMENT ON COLUMN check_ins.initiated_by IS 'Member who initiated check-in.';
COMMENT ON COLUMN check_ins.created_at IS 'Record creation timestamp.';
COMMENT ON COLUMN check_ins.updated_at IS 'Last update timestamp.';

COMMENT ON TABLE coping_strategies IS 'Coping strategies for moods.';
COMMENT ON COLUMN coping_strategies.id IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN coping_strategies.mood IS 'Target mood.';
COMMENT ON COLUMN coping_strategies.title IS 'Strategy title.';
COMMENT ON COLUMN coping_strategies.icon_url IS 'Icon URL.';
COMMENT ON COLUMN coping_strategies.animation_key IS 'Animation key.';
COMMENT ON COLUMN coping_strategies.is_global IS 'Global strategy flag.';
COMMENT ON COLUMN coping_strategies.family_id IS 'Family ID if not global.';
COMMENT ON COLUMN coping_strategies.created_at IS 'Record creation timestamp.';
COMMENT ON COLUMN coping_strategies.updated_at IS 'Last update timestamp.';

COMMENT ON TABLE nudges IS 'Contextual nudges between members.';
COMMENT ON COLUMN nudges.id IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN nudges.family_id IS 'Family ID.';
COMMENT ON COLUMN nudges.from_member IS 'Sender member ID.';
COMMENT ON COLUMN nudges.to_member IS 'Recipient member ID.';
COMMENT ON COLUMN nudges.variant IS 'Nudge variant.';
COMMENT ON COLUMN nudges.trigger_reason IS 'Reason for trigger.';
COMMENT ON COLUMN nudges.message IS 'Message content.';
COMMENT ON COLUMN nudges.read_at IS 'Timestamp when read.';
COMMENT ON COLUMN nudges.created_at IS 'Record creation timestamp.';
COMMENT ON COLUMN nudges.updated_at IS 'Last update timestamp.';
