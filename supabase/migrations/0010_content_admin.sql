-- ============================================================================
-- TABLES
-- ============================================================================

CREATE TABLE IF NOT EXISTS content_variants (
  id uuid primary key default public.uuid_generate_v7(),
  screen_key text not null,
  field_key text not null,
  level language_level not null,
  text text not null,
  created_at timestamptz not null default CURRENT_TIMESTAMP,
  updated_at timestamptz not null default CURRENT_TIMESTAMP,
  unique (screen_key, field_key, level)
);

CREATE TABLE IF NOT EXISTS audit_log (
  id uuid primary key default public.uuid_generate_v7(),
  actor_profile_id uuid references profiles(id),
  action text not null,
  target_table text,
  target_id uuid,
  metadata jsonb,
  created_at timestamptz not null default CURRENT_TIMESTAMP,
  updated_at timestamptz not null default CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS push_campaigns (
  id uuid primary key default public.uuid_generate_v7(),
  title text not null,
  body text,
  target_audience text,
  scheduled_at timestamptz,
  sent_at timestamptz,
  created_at timestamptz not null default CURRENT_TIMESTAMP,
  updated_at timestamptz not null default CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS app_settings (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default CURRENT_TIMESTAMP,
  created_at timestamptz not null default CURRENT_TIMESTAMP
);

-- ============================================================================
-- INDEXES / CONSTRAINTS
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_audit_log_created ON audit_log (created_at desc);

-- ============================================================================
-- COMMENTS SECTION
-- ============================================================================

COMMENT ON TABLE content_variants IS 'Content variants for language complexity.';
COMMENT ON COLUMN content_variants.id IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN content_variants.screen_key IS 'Key for the screen.';
COMMENT ON COLUMN content_variants.field_key IS 'Key for the specific field.';
COMMENT ON COLUMN content_variants.level IS 'Language complexity level.';
COMMENT ON COLUMN content_variants.text IS 'Content text.';
COMMENT ON COLUMN content_variants.created_at IS 'Record creation timestamp.';
COMMENT ON COLUMN content_variants.updated_at IS 'Last update timestamp.';

COMMENT ON TABLE audit_log IS 'Platform admin audit log.';
COMMENT ON COLUMN audit_log.id IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN audit_log.actor_profile_id IS 'Profile ID of actor.';
COMMENT ON COLUMN audit_log.action IS 'Action performed.';
COMMENT ON COLUMN audit_log.target_table IS 'Affected table name.';
COMMENT ON COLUMN audit_log.target_id IS 'Affected row ID.';
COMMENT ON COLUMN audit_log.metadata IS 'Additional action metadata.';
COMMENT ON COLUMN audit_log.created_at IS 'Record creation timestamp.';
COMMENT ON COLUMN audit_log.updated_at IS 'Last update timestamp.';

COMMENT ON TABLE push_campaigns IS 'Admin-managed push notification campaigns.';
COMMENT ON COLUMN push_campaigns.id IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN push_campaigns.title IS 'Campaign title.';
COMMENT ON COLUMN push_campaigns.body IS 'Campaign body.';
COMMENT ON COLUMN push_campaigns.target_audience IS 'Target audience filter.';
COMMENT ON COLUMN push_campaigns.scheduled_at IS 'Scheduled send time.';
COMMENT ON COLUMN push_campaigns.sent_at IS 'Actual send time.';
COMMENT ON COLUMN push_campaigns.created_at IS 'Record creation timestamp.';
COMMENT ON COLUMN push_campaigns.updated_at IS 'Last update timestamp.';

COMMENT ON TABLE app_settings IS 'Global application settings.';
COMMENT ON COLUMN app_settings.key IS 'Setting key (primary key).';
COMMENT ON COLUMN app_settings.value IS 'Setting value as JSONB.';
COMMENT ON COLUMN app_settings.updated_at IS 'Last update timestamp.';
COMMENT ON COLUMN app_settings.created_at IS 'Record creation timestamp.';
