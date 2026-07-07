-- ============================================================================
-- TABLES
-- ============================================================================

CREATE TABLE IF NOT EXISTS routines (
  id uuid primary key default public.uuid_generate_v7(),
  family_id uuid not null references families(id) on delete cascade,
  child_id uuid not null references family_members(id) on delete cascade,
  name text not null,
  created_at timestamptz not null default CURRENT_TIMESTAMP,
  updated_at timestamptz not null default CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS routine_steps (
  id uuid primary key default public.uuid_generate_v7(),
  routine_id uuid not null references routines(id) on delete cascade,
  name text not null,
  icon text,
  order_index int not null default 0,
  time_allocation_minutes int,
  created_at timestamptz not null default CURRENT_TIMESTAMP,
  updated_at timestamptz not null default CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS routine_completions (
  id uuid primary key default public.uuid_generate_v7(),
  routine_id uuid not null references routines(id) on delete cascade,
  child_id uuid not null references family_members(id) on delete cascade,
  date date not null,
  steps_done jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default CURRENT_TIMESTAMP,
  updated_at timestamptz not null default CURRENT_TIMESTAMP,
  unique (routine_id, child_id, date)
);

CREATE TABLE IF NOT EXISTS habits (
  id uuid primary key default public.uuid_generate_v7(),
  family_id uuid not null references families(id) on delete cascade,
  child_id uuid not null references family_members(id) on delete cascade,
  name text not null,
  target_frequency int not null default 7,
  created_at timestamptz not null default CURRENT_TIMESTAMP,
  updated_at timestamptz not null default CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS habit_logs (
  id uuid primary key default public.uuid_generate_v7(),
  habit_id uuid not null references habits(id) on delete cascade,
  date date not null,
  completed boolean not null default true,
  created_at timestamptz not null default CURRENT_TIMESTAMP,
  updated_at timestamptz not null default CURRENT_TIMESTAMP,
  unique (habit_id, date)
);

-- ============================================================================
-- INDEXES / CONSTRAINTS
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_routines_child ON routines (child_id);
CREATE INDEX IF NOT EXISTS idx_routine_steps_routine ON routine_steps (routine_id);
CREATE INDEX IF NOT EXISTS idx_habits_child ON habits (child_id);

-- ============================================================================
-- COMMENTS SECTION
-- ============================================================================

COMMENT ON TABLE routines IS 'Routines defined for a child.';
COMMENT ON COLUMN routines.id IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN routines.family_id IS 'Family ID.';
COMMENT ON COLUMN routines.child_id IS 'Child ID.';
COMMENT ON COLUMN routines.name IS 'Routine name.';
COMMENT ON COLUMN routines.created_at IS 'Record creation timestamp.';
COMMENT ON COLUMN routines.updated_at IS 'Last update timestamp.';

COMMENT ON TABLE routine_steps IS 'Individual steps within a routine.';
COMMENT ON COLUMN routine_steps.id IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN routine_steps.routine_id IS 'Routine ID.';
COMMENT ON COLUMN routine_steps.name IS 'Step name.';
COMMENT ON COLUMN routine_steps.icon IS 'Step icon URL or key.';
COMMENT ON COLUMN routine_steps.order_index IS 'Ordering index for step.';
COMMENT ON COLUMN routine_steps.time_allocation_minutes IS 'Time allocated for step.';
COMMENT ON COLUMN routine_steps.created_at IS 'Record creation timestamp.';
COMMENT ON COLUMN routine_steps.updated_at IS 'Last update timestamp.';

COMMENT ON TABLE routine_completions IS 'Records of completed routines by day.';
COMMENT ON COLUMN routine_completions.id IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN routine_completions.routine_id IS 'Routine ID.';
COMMENT ON COLUMN routine_completions.child_id IS 'Child ID.';
COMMENT ON COLUMN routine_completions.date IS 'Date of completion.';
COMMENT ON COLUMN routine_completions.steps_done IS 'JSON map of completed steps.';
COMMENT ON COLUMN routine_completions.created_at IS 'Record creation timestamp.';
COMMENT ON COLUMN routine_completions.updated_at IS 'Last update timestamp.';

COMMENT ON TABLE habits IS 'Habits defined for a child.';
COMMENT ON COLUMN habits.id IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN habits.family_id IS 'Family ID.';
COMMENT ON COLUMN habits.child_id IS 'Child ID.';
COMMENT ON COLUMN habits.name IS 'Habit name.';
COMMENT ON COLUMN habits.target_frequency IS 'Target frequency in days.';
COMMENT ON COLUMN habits.created_at IS 'Record creation timestamp.';
COMMENT ON COLUMN habits.updated_at IS 'Last update timestamp.';

COMMENT ON TABLE habit_logs IS 'Daily logs for habits.';
COMMENT ON COLUMN habit_logs.id IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN habit_logs.habit_id IS 'Habit ID.';
COMMENT ON COLUMN habit_logs.date IS 'Date of the log.';
COMMENT ON COLUMN habit_logs.completed IS 'Whether habit was completed.';
COMMENT ON COLUMN habit_logs.created_at IS 'Record creation timestamp.';
COMMENT ON COLUMN habit_logs.updated_at IS 'Last update timestamp.';
