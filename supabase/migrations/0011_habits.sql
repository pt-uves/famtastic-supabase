-- ============================================================================
-- TABLES
-- ============================================================================

-- ----------------------------------------------------------------------------
-- habits
-- Daily habits defined by the parent. The child ticks them off in Child Mode
-- and builds a streak.
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.habits (
    id          UUID        PRIMARY KEY DEFAULT uuid_generate_v7(),
    child_id    UUID        NOT NULL,
    created_by  UUID        NOT NULL,
    name        TEXT        NOT NULL,
    icon_url    TEXT,
    is_active   BOOLEAN     NOT NULL DEFAULT true,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ----------------------------------------------------------------------------
-- habit_logs
-- One row per child per habit per calendar day.
-- The unique constraint prevents double-ticking on the same day.
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.habit_logs (
    id          UUID        PRIMARY KEY DEFAULT uuid_generate_v7(),
    habit_id    UUID        NOT NULL,
    child_id    UUID        NOT NULL,
    logged_date DATE        NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- INDEXES / CONSTRAINTS
-- ============================================================================

ALTER TABLE public.habits DROP CONSTRAINT IF EXISTS fk_habits_child;
ALTER TABLE public.habits ADD CONSTRAINT fk_habits_child
    FOREIGN KEY (child_id) REFERENCES public.children (id) ON DELETE CASCADE;

ALTER TABLE public.habits DROP CONSTRAINT IF EXISTS fk_habits_created_by;
ALTER TABLE public.habits ADD CONSTRAINT fk_habits_created_by
    FOREIGN KEY (created_by) REFERENCES public.profiles (id) ON DELETE RESTRICT;

CREATE INDEX IF NOT EXISTS idx_habits_child_id ON public.habits (child_id);

ALTER TABLE public.habit_logs DROP CONSTRAINT IF EXISTS fk_habit_logs_habit;
ALTER TABLE public.habit_logs ADD CONSTRAINT fk_habit_logs_habit
    FOREIGN KEY (habit_id) REFERENCES public.habits (id) ON DELETE CASCADE;

ALTER TABLE public.habit_logs DROP CONSTRAINT IF EXISTS fk_habit_logs_child;
ALTER TABLE public.habit_logs ADD CONSTRAINT fk_habit_logs_child
    FOREIGN KEY (child_id) REFERENCES public.children (id) ON DELETE CASCADE;

-- Prevent a child from logging the same habit more than once per day.
CREATE UNIQUE INDEX IF NOT EXISTS uk_habit_logs_habit_child_date
    ON public.habit_logs (habit_id, child_id, logged_date);

-- Streak calculation query: all logs for a child per habit ordered by date.
CREATE INDEX IF NOT EXISTS idx_habit_logs_child_habit_date
    ON public.habit_logs (child_id, habit_id, logged_date DESC);

-- ============================================================================
-- RLS POLICIES
-- ============================================================================

ALTER TABLE public.habits ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.habit_logs ENABLE ROW LEVEL SECURITY;

-- POLICIES — habits

DROP POLICY IF EXISTS "habits_select_policy" ON public.habits;
CREATE POLICY "habits_select_policy" ON public.habits
    FOR SELECT USING (
        owns_child(child_id) OR is_linked_to_child(child_id) OR is_platform_admin()
    );

DROP POLICY IF EXISTS "habits_insert_policy" ON public.habits;
CREATE POLICY "habits_insert_policy" ON public.habits
    FOR INSERT WITH CHECK (
        owns_child(child_id) OR is_linked_to_child(child_id)
    );

DROP POLICY IF EXISTS "habits_update_policy" ON public.habits;
CREATE POLICY "habits_update_policy" ON public.habits
    FOR UPDATE USING (owns_child(child_id) OR created_by = auth.uid());

DROP POLICY IF EXISTS "habits_delete_policy" ON public.habits;
CREATE POLICY "habits_delete_policy" ON public.habits
    FOR DELETE USING (owns_child(child_id));

-- POLICIES — habit_logs

DROP POLICY IF EXISTS "habit_logs_select_policy" ON public.habit_logs;
CREATE POLICY "habit_logs_select_policy" ON public.habit_logs
    FOR SELECT USING (
        owns_child(child_id) OR is_linked_to_child(child_id) OR is_platform_admin()
    );

DROP POLICY IF EXISTS "habit_logs_insert_policy" ON public.habit_logs;
CREATE POLICY "habit_logs_insert_policy" ON public.habit_logs
    FOR INSERT WITH CHECK (
        owns_child(child_id) OR is_linked_to_child(child_id)
    );

-- ============================================================================
-- COMMENTS SECTION
-- ============================================================================

COMMENT ON TABLE  public.habits                             IS 'A daily habit defined by the parent. The child ticks it off each day and builds a streak.';
COMMENT ON COLUMN public.habits.id                          IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN public.habits.child_id                    IS 'The child this habit belongs to.';
COMMENT ON COLUMN public.habits.created_by                  IS 'Member who defined the habit.';
COMMENT ON COLUMN public.habits.name                        IS 'Habit display name (e.g. Drink Water, Read 10 Minutes).';
COMMENT ON COLUMN public.habits.icon_url                    IS 'Optional icon or illustration for the habit.';
COMMENT ON COLUMN public.habits.is_active                   IS 'Inactive habits are hidden from the child view.';
COMMENT ON COLUMN public.habits.created_at                  IS 'Row creation timestamp.';

COMMENT ON TABLE  public.habit_logs                         IS 'One row per child per habit per calendar day. The unique constraint prevents double-ticking.';
COMMENT ON COLUMN public.habit_logs.id                      IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN public.habit_logs.habit_id                IS 'The habit that was completed.';
COMMENT ON COLUMN public.habit_logs.child_id                IS 'The child who completed it.';
COMMENT ON COLUMN public.habit_logs.logged_date             IS 'Calendar date the habit was ticked (in the child''s local timezone, set by the app).';
COMMENT ON COLUMN public.habit_logs.created_at              IS 'Row creation timestamp.';
