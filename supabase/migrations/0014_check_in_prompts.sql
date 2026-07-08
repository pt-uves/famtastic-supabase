-- ============================================================================
-- TABLES
-- ============================================================================

-- ----------------------------------------------------------------------------
-- check_in_prompts
-- A prompt is created by a parent (or scheduled) to ask a child to check in.
-- The child replies by creating a check_in row (with is_from_child = true)
-- linked back to this prompt. Keeping prompts separate preserves the
-- check_ins.mood NOT NULL constraint and gives a clean audit trail.
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.check_in_prompts (
    id              UUID        PRIMARY KEY DEFAULT uuid_generate_v7(),
    child_id        UUID        NOT NULL,
    initiated_by    UUID        NOT NULL,
    question_text   TEXT,
    -- NULL until the child replies; set to the resulting check_in.id on reply.
    reply_check_in_id UUID,
    scheduled_at    TIMESTAMPTZ,
    sent_at         TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- INDEXES / CONSTRAINTS
-- ============================================================================

ALTER TABLE public.check_in_prompts DROP CONSTRAINT IF EXISTS fk_check_in_prompts_child;
ALTER TABLE public.check_in_prompts ADD CONSTRAINT fk_check_in_prompts_child
    FOREIGN KEY (child_id) REFERENCES public.children (id) ON DELETE CASCADE;

ALTER TABLE public.check_in_prompts DROP CONSTRAINT IF EXISTS fk_check_in_prompts_initiated_by;
ALTER TABLE public.check_in_prompts ADD CONSTRAINT fk_check_in_prompts_initiated_by
    FOREIGN KEY (initiated_by) REFERENCES public.profiles (id) ON DELETE RESTRICT;

ALTER TABLE public.check_in_prompts DROP CONSTRAINT IF EXISTS fk_check_in_prompts_reply;
ALTER TABLE public.check_in_prompts ADD CONSTRAINT fk_check_in_prompts_reply
    FOREIGN KEY (reply_check_in_id) REFERENCES public.check_ins (id) ON DELETE SET NULL;

-- Parent queries: all prompts they sent for a child, ordered by time.
CREATE INDEX IF NOT EXISTS idx_check_in_prompts_child_created
    ON public.check_in_prompts (child_id, created_at DESC);

-- Pending prompts lookup (reply_check_in_id IS NULL = not yet answered).
CREATE INDEX IF NOT EXISTS idx_check_in_prompts_unanswered
    ON public.check_in_prompts (child_id, reply_check_in_id)
    WHERE reply_check_in_id IS NULL;

-- Scheduled prompt delivery (cron job queries this).
CREATE INDEX IF NOT EXISTS idx_check_in_prompts_scheduled
    ON public.check_in_prompts (scheduled_at)
    WHERE sent_at IS NULL AND scheduled_at IS NOT NULL;

-- ============================================================================
-- RLS POLICIES
-- ============================================================================

ALTER TABLE public.check_in_prompts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "check_in_prompts_select_policy" ON public.check_in_prompts;
CREATE POLICY "check_in_prompts_select_policy" ON public.check_in_prompts
    FOR SELECT USING (
        owns_child(child_id) OR is_linked_to_child(child_id) OR is_platform_admin()
    );

-- Only the parent who owns the child can create prompts.
DROP POLICY IF EXISTS "check_in_prompts_insert_policy" ON public.check_in_prompts;
CREATE POLICY "check_in_prompts_insert_policy" ON public.check_in_prompts
    FOR INSERT WITH CHECK (owns_child(child_id));

-- Update allowed to: the initiator (to mark sent_at) or the child's owner
-- (to link the reply check-in).
DROP POLICY IF EXISTS "check_in_prompts_update_policy" ON public.check_in_prompts;
CREATE POLICY "check_in_prompts_update_policy" ON public.check_in_prompts
    FOR UPDATE USING (
        initiated_by = auth.uid() OR owns_child(child_id)
    );

DROP POLICY IF EXISTS "check_in_prompts_delete_policy" ON public.check_in_prompts;
CREATE POLICY "check_in_prompts_delete_policy" ON public.check_in_prompts
    FOR DELETE USING (owns_child(child_id));

-- ============================================================================
-- COMMENTS SECTION
-- ============================================================================

COMMENT ON TABLE  public.check_in_prompts                           IS 'A check-in request sent by a parent to a child. Keeps prompts separate from check_ins so check_ins.mood stays NOT NULL. The child replies by creating a check_in row linked here via reply_check_in_id.';
COMMENT ON COLUMN public.check_in_prompts.id                        IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN public.check_in_prompts.child_id                  IS 'The child this prompt is addressed to.';
COMMENT ON COLUMN public.check_in_prompts.initiated_by              IS 'The parent admin who created this prompt.';
COMMENT ON COLUMN public.check_in_prompts.question_text             IS 'Optional question shown to the child (e.g. "How was school today?").';
COMMENT ON COLUMN public.check_in_prompts.reply_check_in_id         IS 'Set to the check_in.id when the child replies. NULL = awaiting reply.';
COMMENT ON COLUMN public.check_in_prompts.scheduled_at              IS 'Optional future time at which the prompt should be delivered (e.g. after school, before bed).';
COMMENT ON COLUMN public.check_in_prompts.sent_at                   IS 'Timestamp when the push notification was dispatched. NULL = not yet sent.';
COMMENT ON COLUMN public.check_in_prompts.created_at                IS 'Row creation timestamp.';
