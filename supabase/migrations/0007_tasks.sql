-- ============================================================================
-- ENUMS
-- ============================================================================

DROP TYPE IF EXISTS task_priority CASCADE;
CREATE TYPE task_priority AS ENUM ('low', 'medium', 'high');

DROP TYPE IF EXISTS task_status CASCADE;
CREATE TYPE task_status AS ENUM ('pending', 'in_progress', 'awaiting_verification', 'completed', 'overdue');

DROP TYPE IF EXISTS task_verification CASCADE;
CREATE TYPE task_verification AS ENUM ('none', 'photo_proof', 'adult_approval');

-- ============================================================================
-- TABLES
-- ============================================================================

-- ----------------------------------------------------------------------------
-- task_categories
-- System defaults (is_system = true, child_id = NULL) are seeded by the
-- platform and visible to everyone. Parent-created categories are scoped to
-- one child (child_id IS NOT NULL).
-- Default colours: Academic = #4CAF50, Sports = #2196F3, Medicine = #F44336
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.task_categories (
    id          UUID        PRIMARY KEY DEFAULT uuid_generate_v7(),
    child_id    UUID,
    created_by  UUID,
    name        TEXT        NOT NULL,
    color_hex   CHAR(7)     NOT NULL,
    is_system   BOOLEAN     NOT NULL DEFAULT false,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_task_categories_color CHECK (color_hex ~ '^#[0-9A-Fa-f]{6}$'),
    CONSTRAINT chk_task_categories_scope CHECK (
        (is_system = true AND child_id IS NULL) OR
        (is_system = false AND child_id IS NOT NULL)
    )
);

-- ----------------------------------------------------------------------------
-- tasks
-- Tasks live inside a child. Anyone with access to the child can see the
-- child's tasks. Created by any linked member.
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.tasks (
    id                          UUID                    PRIMARY KEY DEFAULT uuid_generate_v7(),
    child_id                    UUID                    NOT NULL,
    created_by                  UUID                    NOT NULL,
    category_id                 UUID,
    name                        TEXT                    NOT NULL,
    description                 TEXT,
    due_at                      TIMESTAMPTZ,
    priority                    task_priority           NOT NULL DEFAULT 'medium',
    status                      task_status             NOT NULL DEFAULT 'pending',
    verification_type           task_verification       NOT NULL DEFAULT 'none',
    photo_proof_url             TEXT,
    approved_by                 UUID,
    approved_at                 TIMESTAMPTZ,
    points_awarded              SMALLINT,
    google_calendar_event_id    TEXT,
    created_at                  TIMESTAMPTZ             NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                  TIMESTAMPTZ             NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Approval columns are set together or not at all.
    CONSTRAINT chk_tasks_approval_pair CHECK (
        (approved_by IS NULL) = (approved_at IS NULL)
    ),
    -- A task can only reach 'completed' once its required verification is satisfied:
    -- photo_proof needs a photo, adult_approval needs an approver. 'none' is free.
    CONSTRAINT chk_tasks_completion_verified CHECK (
        status <> 'completed'
        OR verification_type = 'none'
        OR (verification_type = 'photo_proof'    AND photo_proof_url IS NOT NULL)
        OR (verification_type = 'adult_approval' AND approved_by IS NOT NULL)
    ),
    CONSTRAINT chk_tasks_points CHECK (points_awarded >= 0 AND points_awarded <= 5)
);

-- ============================================================================
-- INDEXES / CONSTRAINTS
-- ============================================================================

ALTER TABLE public.task_categories DROP CONSTRAINT IF EXISTS fk_task_categories_child;
ALTER TABLE public.task_categories ADD CONSTRAINT fk_task_categories_child
    FOREIGN KEY (child_id) REFERENCES public.children (id) ON DELETE CASCADE;

ALTER TABLE public.task_categories DROP CONSTRAINT IF EXISTS fk_task_categories_created_by;
ALTER TABLE public.task_categories ADD CONSTRAINT fk_task_categories_created_by
    FOREIGN KEY (created_by) REFERENCES public.profiles (id) ON DELETE SET NULL;

ALTER TABLE public.tasks DROP CONSTRAINT IF EXISTS fk_tasks_child;
ALTER TABLE public.tasks ADD CONSTRAINT fk_tasks_child
    FOREIGN KEY (child_id) REFERENCES public.children (id) ON DELETE CASCADE;

ALTER TABLE public.tasks DROP CONSTRAINT IF EXISTS fk_tasks_created_by;
ALTER TABLE public.tasks ADD CONSTRAINT fk_tasks_created_by
    FOREIGN KEY (created_by) REFERENCES public.profiles (id) ON DELETE CASCADE;

ALTER TABLE public.tasks DROP CONSTRAINT IF EXISTS fk_tasks_category;
ALTER TABLE public.tasks ADD CONSTRAINT fk_tasks_category
    FOREIGN KEY (category_id) REFERENCES public.task_categories (id) ON DELETE SET NULL;

ALTER TABLE public.tasks DROP CONSTRAINT IF EXISTS fk_tasks_approved_by;
ALTER TABLE public.tasks ADD CONSTRAINT fk_tasks_approved_by
    FOREIGN KEY (approved_by) REFERENCES public.profiles (id) ON DELETE SET NULL;

-- Task list view: filter by child + status, order by due date.
CREATE INDEX IF NOT EXISTS idx_tasks_child_status_due
    ON public.tasks (child_id, status, due_at);

-- Calendar month view: filter by child + date range.
CREATE INDEX IF NOT EXISTS idx_tasks_child_due
    ON public.tasks (child_id, due_at);

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Keep updated_at current on every change, including service-role writes.
DROP TRIGGER IF EXISTS trigger_tasks_set_updated_at ON public.tasks;
CREATE TRIGGER trigger_tasks_set_updated_at
    BEFORE UPDATE ON public.tasks
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

-- ============================================================================
-- RLS POLICIES
-- ============================================================================

ALTER TABLE public.task_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;

-- POLICIES - task_categories

DROP POLICY IF EXISTS "task_categories_select_policy" ON public.task_categories;
CREATE POLICY "task_categories_select_policy" ON public.task_categories
    FOR SELECT USING (
        is_system = true
        OR owns_child(child_id)
        OR is_linked_to_child(child_id)
        OR is_platform_admin()
    );

DROP POLICY IF EXISTS "task_categories_insert_policy" ON public.task_categories;
CREATE POLICY "task_categories_insert_policy" ON public.task_categories
    FOR INSERT WITH CHECK (
        (is_system = true AND is_platform_admin())
        OR (is_system = false AND (owns_child(child_id) OR is_linked_to_child(child_id)))
    );

DROP POLICY IF EXISTS "task_categories_update_policy" ON public.task_categories;
CREATE POLICY "task_categories_update_policy" ON public.task_categories
    FOR UPDATE USING (
        (is_system = true AND is_platform_admin())
        OR (is_system = false AND owns_child(child_id))
    );

DROP POLICY IF EXISTS "task_categories_delete_policy" ON public.task_categories;
CREATE POLICY "task_categories_delete_policy" ON public.task_categories
    FOR DELETE USING (
        (is_system = true AND is_platform_admin())
        OR (is_system = false AND owns_child(child_id))
    );

-- POLICIES - tasks

DROP POLICY IF EXISTS "tasks_select_policy" ON public.tasks;
CREATE POLICY "tasks_select_policy" ON public.tasks
    FOR SELECT USING (
        owns_child(child_id) OR is_linked_to_child(child_id) OR is_platform_admin()
    );

DROP POLICY IF EXISTS "tasks_insert_policy" ON public.tasks;
CREATE POLICY "tasks_insert_policy" ON public.tasks
    FOR INSERT WITH CHECK (
        owns_child(child_id) OR is_linked_to_child(child_id)
    );

DROP POLICY IF EXISTS "tasks_update_policy" ON public.tasks;
CREATE POLICY "tasks_update_policy" ON public.tasks
    FOR UPDATE USING (
        owns_child(child_id) OR is_linked_to_child(child_id)
    );

DROP POLICY IF EXISTS "tasks_delete_policy" ON public.tasks;
CREATE POLICY "tasks_delete_policy" ON public.tasks
    FOR DELETE USING (owns_child(child_id) OR created_by = auth.uid());

-- ============================================================================
-- COMMENTS SECTION
-- ============================================================================

COMMENT ON TYPE  task_priority                             IS 'Task urgency level.';
COMMENT ON TYPE  task_status                               IS 'Lifecycle status of a task.';
COMMENT ON TYPE  task_verification                         IS 'Verification method required before a task is marked complete.';

COMMENT ON TABLE  public.task_categories                        IS 'Colour-coded task categories. System defaults are shared; parent-created ones are child-scoped.';
COMMENT ON COLUMN public.task_categories.id                     IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN public.task_categories.child_id               IS 'NULL for system defaults; set for parent-created custom categories.';
COMMENT ON COLUMN public.task_categories.created_by             IS 'NULL for system defaults; the parent who created a custom category.';
COMMENT ON COLUMN public.task_categories.name                   IS 'Category display name (e.g. Academic, Medicine).';
COMMENT ON COLUMN public.task_categories.color_hex              IS 'Hex colour code (e.g. #4CAF50). Validated by check constraint.';
COMMENT ON COLUMN public.task_categories.is_system              IS 'True for platform-seeded defaults that all families share.';
COMMENT ON COLUMN public.task_categories.created_at             IS 'Row creation timestamp.';

COMMENT ON TABLE  public.tasks                                  IS 'A task scoped to a child. Visible to all members linked to that child.';
COMMENT ON COLUMN public.tasks.id                               IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN public.tasks.child_id                         IS 'The child this task belongs to.';
COMMENT ON COLUMN public.tasks.created_by                       IS 'Member who created the task.';
COMMENT ON COLUMN public.tasks.category_id                      IS 'Optional category. Falls back to uncategorised when NULL.';
COMMENT ON COLUMN public.tasks.name                             IS 'Task title displayed in the UI.';
COMMENT ON COLUMN public.tasks.description                      IS 'Optional longer description.';
COMMENT ON COLUMN public.tasks.due_at                           IS 'Timestamp the task is due. Can represent just the date if time is truncated/omitted.';
COMMENT ON COLUMN public.tasks.priority                         IS 'Task urgency: low, medium, or high.';
COMMENT ON COLUMN public.tasks.status                           IS 'Current lifecycle state of the task.';
COMMENT ON COLUMN public.tasks.verification_type                IS 'How completion is verified: none, photo proof, or adult approval.';
COMMENT ON COLUMN public.tasks.photo_proof_url                  IS 'URL of the uploaded photo proof (Supabase Storage).';
COMMENT ON COLUMN public.tasks.approved_by                      IS 'Adult member who approved the task completion.';
COMMENT ON COLUMN public.tasks.approved_at                      IS 'Timestamp of approval.';
COMMENT ON COLUMN public.tasks.points_awarded                   IS 'Fixed point amount awarded upon task completion.';
COMMENT ON COLUMN public.tasks.google_calendar_event_id         IS 'External event ID for one-way Google Calendar sync.';
COMMENT ON COLUMN public.tasks.created_at                       IS 'Row creation timestamp.';
COMMENT ON COLUMN public.tasks.updated_at                       IS 'Last-modified timestamp, stamped by the set_updated_at() trigger on every update.';
