-- ============================================================================
-- ENUMS (if any)
-- ============================================================================

DROP TYPE IF EXISTS task_priority CASCADE;
CREATE TYPE task_priority AS ENUM ('low','medium','high');

DROP TYPE IF EXISTS verification_type CASCADE;
CREATE TYPE verification_type AS ENUM ('photo','adult_approval','none');

DROP TYPE IF EXISTS task_status CASCADE;
CREATE TYPE task_status AS ENUM ('pending','completed','awaiting_verification','overdue');

-- ============================================================================
-- TABLES
-- ============================================================================

CREATE TABLE IF NOT EXISTS task_categories (
  id uuid primary key default public.uuid_generate_v7(),
  family_id uuid references families(id) on delete cascade,
  name text not null,
  color text not null,
  created_at timestamptz not null default CURRENT_TIMESTAMP,
  updated_at timestamptz not null default CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS tasks (
  id uuid primary key default public.uuid_generate_v7(),
  family_id uuid not null references families(id) on delete cascade,
  title text not null,
  category_id uuid references task_categories(id),
  date date not null,
  time time,
  assignee_id uuid references family_members(id),
  priority task_priority not null default 'medium',
  requires_verification boolean not null default false,
  verification_type verification_type not null default 'none',
  status task_status not null default 'pending',
  google_event_id text,
  reminder_at timestamptz,
  created_by uuid references family_members(id),
  created_at timestamptz not null default CURRENT_TIMESTAMP,
  updated_at timestamptz not null default CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS task_verifications (
  id uuid primary key default public.uuid_generate_v7(),
  task_id uuid not null references tasks(id) on delete cascade,
  photo_url text,
  verified_by uuid references family_members(id),
  verified_at timestamptz not null default CURRENT_TIMESTAMP,
  notes text,
  created_at timestamptz not null default CURRENT_TIMESTAMP,
  updated_at timestamptz not null default CURRENT_TIMESTAMP
);

-- ============================================================================
-- INDEXES / CONSTRAINTS
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_tasks_family_date ON tasks (family_id, date);
CREATE INDEX IF NOT EXISTS idx_tasks_assignee_status ON tasks (assignee_id, status);

CREATE INDEX IF NOT EXISTS idx_task_verifications_task ON task_verifications (task_id);

-- ============================================================================
-- COMMENTS SECTION
-- ============================================================================

COMMENT ON TABLE task_categories IS 'Task categories setup.';
COMMENT ON COLUMN task_categories.id IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN task_categories.family_id IS 'Family ID (null for global defaults).';
COMMENT ON COLUMN task_categories.name IS 'Category name.';
COMMENT ON COLUMN task_categories.color IS 'Category color.';
COMMENT ON COLUMN task_categories.created_at IS 'Record creation timestamp.';
COMMENT ON COLUMN task_categories.updated_at IS 'Last update timestamp.';

COMMENT ON TABLE tasks IS 'Tasks and assignments.';
COMMENT ON COLUMN tasks.id IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN tasks.family_id IS 'Family ID.';
COMMENT ON COLUMN tasks.title IS 'Task title.';
COMMENT ON COLUMN tasks.category_id IS 'Category ID.';
COMMENT ON COLUMN tasks.date IS 'Task date.';
COMMENT ON COLUMN tasks.time IS 'Task time.';
COMMENT ON COLUMN tasks.assignee_id IS 'Assignee member ID.';
COMMENT ON COLUMN tasks.priority IS 'Task priority.';
COMMENT ON COLUMN tasks.requires_verification IS 'Verification required flag.';
COMMENT ON COLUMN tasks.verification_type IS 'Type of verification.';
COMMENT ON COLUMN tasks.status IS 'Task status.';
COMMENT ON COLUMN tasks.google_event_id IS 'Google Calendar event ID.';
COMMENT ON COLUMN tasks.reminder_at IS 'Reminder timestamp.';
COMMENT ON COLUMN tasks.created_by IS 'Creator member ID.';
COMMENT ON COLUMN tasks.created_at IS 'Record creation timestamp.';
COMMENT ON COLUMN tasks.updated_at IS 'Last update timestamp.';

COMMENT ON TABLE task_verifications IS 'Verifications for completed tasks.';
COMMENT ON COLUMN task_verifications.id IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN task_verifications.task_id IS 'Task ID.';
COMMENT ON COLUMN task_verifications.photo_url IS 'URL to verification photo.';
COMMENT ON COLUMN task_verifications.verified_by IS 'Member who verified.';
COMMENT ON COLUMN task_verifications.verified_at IS 'Verification timestamp.';
COMMENT ON COLUMN task_verifications.notes IS 'Verification notes.';
COMMENT ON COLUMN task_verifications.created_at IS 'Record creation timestamp.';
COMMENT ON COLUMN task_verifications.updated_at IS 'Last update timestamp.';
