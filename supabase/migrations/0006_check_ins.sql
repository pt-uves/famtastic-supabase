-- ============================================================================
-- ENUMS
-- ============================================================================

DROP TYPE IF EXISTS mood CASCADE;
CREATE TYPE mood AS ENUM ('happy', 'calm', 'overwhelmed', 'angry');

-- ============================================================================
-- TABLES
-- ============================================================================

-- ----------------------------------------------------------------------------
-- check_ins
-- Two-way: a check-in is either
--   (a) an adult member's check-in (author_id set) about a linked child OR about
--       their own mood (child_id NULL - a self check-in), or
--   (b) a child's own reply in Child Mode (is_from_child = true, author_id NULL,
--       child_id set).
-- One-tap mood + optional text + optional voice note.
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.check_ins (
    id                      UUID        PRIMARY KEY DEFAULT uuid_generate_v7(),
    child_id                UUID,
    author_id               UUID,
    is_from_child           BOOLEAN     NOT NULL DEFAULT false,
    mood                    mood        NOT NULL,
    text_response           TEXT,
    voice_note_url          TEXT,
    shared_with_family      BOOLEAN     NOT NULL DEFAULT true,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_check_ins_authorship CHECK (
        -- child reply: from the child, no author, always about a child
        (is_from_child = true  AND author_id IS NULL AND child_id IS NOT NULL)
        -- adult check-in: has an author; about a linked child OR their own mood
        OR (is_from_child = false AND author_id IS NOT NULL)
    )
);

-- ----------------------------------------------------------------------------
-- check_in_prompts
-- A prompt is created by a parent (or scheduled) to ask a child to check in.
-- The child replies by creating a check_in row (with is_from_child = true)
-- linked back to this prompt. Keeping prompts separate preserves the
-- check_ins.mood NOT NULL constraint and gives a clean audit trail.
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.check_in_prompts (
    id                  UUID        PRIMARY KEY DEFAULT uuid_generate_v7(),
    child_id            UUID        NOT NULL,
    initiated_by        UUID        NOT NULL,
    question_text       TEXT,
    -- NULL until the child replies; set to the resulting check_in.id on reply.
    reply_check_in_id   UUID,
    scheduled_at        TIMESTAMPTZ,
    sent_at             TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- INDEXES / CONSTRAINTS
-- ============================================================================

ALTER TABLE public.check_ins DROP CONSTRAINT IF EXISTS fk_check_ins_child;
ALTER TABLE public.check_ins ADD CONSTRAINT fk_check_ins_child
    FOREIGN KEY (child_id) REFERENCES public.children (id) ON DELETE CASCADE;

ALTER TABLE public.check_ins DROP CONSTRAINT IF EXISTS fk_check_ins_author;
ALTER TABLE public.check_ins ADD CONSTRAINT fk_check_ins_author
    FOREIGN KEY (author_id) REFERENCES public.profiles (id) ON DELETE CASCADE;

-- Mood chart queries: filter by child and order by time.
CREATE INDEX IF NOT EXISTS idx_check_ins_child_created
    ON public.check_ins (child_id, created_at DESC);

ALTER TABLE public.check_in_prompts DROP CONSTRAINT IF EXISTS fk_check_in_prompts_child;
ALTER TABLE public.check_in_prompts ADD CONSTRAINT fk_check_in_prompts_child
    FOREIGN KEY (child_id) REFERENCES public.children (id) ON DELETE CASCADE;

ALTER TABLE public.check_in_prompts DROP CONSTRAINT IF EXISTS fk_check_in_prompts_initiated_by;
ALTER TABLE public.check_in_prompts ADD CONSTRAINT fk_check_in_prompts_initiated_by
    FOREIGN KEY (initiated_by) REFERENCES public.profiles (id) ON DELETE CASCADE;

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
-- TRIGGERS
-- ============================================================================

-- Keep updated_at current on every change.
DROP TRIGGER IF EXISTS trigger_check_ins_set_updated_at ON public.check_ins;
CREATE TRIGGER trigger_check_ins_set_updated_at
    BEFORE UPDATE ON public.check_ins
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trigger_check_in_prompts_set_updated_at ON public.check_in_prompts;
CREATE TRIGGER trigger_check_in_prompts_set_updated_at
    BEFORE UPDATE ON public.check_in_prompts
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

-- ============================================================================
-- RLS HELPER
-- ============================================================================

-- ----------------------------------------------------------------------------
-- shares_child_with(p_other_account UUID)
-- Returns true if the current user and p_other_account both have access to at
-- least one common active-family child (via ownership or an accepted
-- membership). Used so a member's own (child_id NULL) shared check-in is visible
-- to the people they share a child with - "family mood history" for adults.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.shares_child_with(p_other_account UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.children c
        JOIN public.families f ON f.id = c.family_id
        WHERE f.status = 'active'
          AND (
                f.owner_id = auth.uid()
             OR EXISTS (SELECT 1 FROM public.memberships m
                         WHERE m.child_id = c.id AND m.account_id = auth.uid()
                           AND m.invite_status = 'accepted')
          )
          AND (
                f.owner_id = p_other_account
             OR EXISTS (SELECT 1 FROM public.memberships m2
                         WHERE m2.child_id = c.id AND m2.account_id = p_other_account
                           AND m2.invite_status = 'accepted')
          )
    );
$$;

-- ============================================================================
-- RLS POLICIES
-- ============================================================================

ALTER TABLE public.check_ins ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "check_ins_select_policy" ON public.check_ins;
CREATE POLICY "check_ins_select_policy" ON public.check_ins
    FOR SELECT USING (
        is_platform_admin()
        OR author_id = auth.uid()
        -- child-scoped check-in, shared: visible to anyone linked to the child
        OR (child_id IS NOT NULL AND shared_with_family
            AND (owns_child(child_id) OR is_linked_to_child(child_id)))
        -- adult self check-in (child_id NULL), shared: visible to co-members
        OR (child_id IS NULL AND shared_with_family
            AND author_id IS NOT NULL AND shares_child_with(author_id))
    );

DROP POLICY IF EXISTS "check_ins_insert_policy" ON public.check_ins;
CREATE POLICY "check_ins_insert_policy" ON public.check_ins
    FOR INSERT WITH CHECK (
        -- adult check-in about a linked child
        (child_id IS NOT NULL AND is_from_child = false AND author_id = auth.uid()
            AND (owns_child(child_id) OR is_linked_to_child(child_id)))
        -- child's own reply in Child Mode (created on the owner's device/session)
        OR (child_id IS NOT NULL AND is_from_child = true AND author_id IS NULL
            AND owns_child(child_id))
        -- adult self check-in (own mood, no child)
        OR (child_id IS NULL AND is_from_child = false AND author_id = auth.uid())
    );

DROP POLICY IF EXISTS "check_ins_update_policy" ON public.check_ins;
CREATE POLICY "check_ins_update_policy" ON public.check_ins
    FOR UPDATE
    USING (author_id = auth.uid())
    WITH CHECK (
        author_id = auth.uid()
        AND (
            child_id IS NULL
            OR owns_child(child_id)
            OR is_linked_to_child(child_id)
        )
    );

DROP POLICY IF EXISTS "check_ins_delete_policy" ON public.check_ins;
CREATE POLICY "check_ins_delete_policy" ON public.check_ins
    FOR DELETE USING (
        (child_id IS NOT NULL AND owns_child(child_id))
        OR author_id = auth.uid()
    );

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
    FOR UPDATE
    USING (initiated_by = auth.uid() OR owns_child(child_id))
    WITH CHECK (initiated_by = auth.uid() OR owns_child(child_id));

DROP POLICY IF EXISTS "check_in_prompts_delete_policy" ON public.check_in_prompts;
CREATE POLICY "check_in_prompts_delete_policy" ON public.check_in_prompts
    FOR DELETE USING (owns_child(child_id));

-- ============================================================================
-- COMMENTS SECTION
-- ============================================================================

COMMENT ON TYPE  mood                              IS 'Four supported mood states used in check-ins and analytics.';

COMMENT ON TABLE  public.check_ins                      IS 'A two-way mood check-in: an adult member''s check-in (about a linked child or their own mood) or the child''s own reply in Child Mode.';
COMMENT ON COLUMN public.check_ins.id                   IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN public.check_ins.child_id             IS 'The child this check-in is about. NULL for an adult member''s self check-in (their own mood).';
COMMENT ON COLUMN public.check_ins.author_id            IS 'The adult member who submitted this check-in. NULL when is_from_child = true.';
COMMENT ON COLUMN public.check_ins.is_from_child        IS 'True when the child submitted the reply in Child Mode.';
COMMENT ON COLUMN public.check_ins.mood                 IS 'Mood selected: happy, calm, overwhelmed, or angry.';
COMMENT ON COLUMN public.check_ins.text_response        IS 'Optional short written response from the author.';
COMMENT ON COLUMN public.check_ins.voice_note_url       IS 'URL to a voice note recording stored in Supabase Storage.';
COMMENT ON COLUMN public.check_ins.shared_with_family   IS 'Whether this check-in is visible to all linked members or only the author.';
COMMENT ON COLUMN public.check_ins.created_at           IS 'Row creation timestamp - used as the check-in timestamp.';
COMMENT ON COLUMN public.check_ins.updated_at           IS 'Last-modified timestamp, stamped by the set_updated_at() trigger.';

COMMENT ON TABLE  public.check_in_prompts                           IS 'A check-in request sent by a parent to a child. Keeps prompts separate from check_ins so check_ins.mood stays NOT NULL. The child replies by creating a check_in row linked here via reply_check_in_id.';
COMMENT ON COLUMN public.check_in_prompts.id                        IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN public.check_in_prompts.child_id                  IS 'The child this prompt is addressed to.';
COMMENT ON COLUMN public.check_in_prompts.initiated_by              IS 'The parent admin who created this prompt (provenance). Nullable: set to NULL if that account is deleted, since the prompt belongs to the child.';
COMMENT ON COLUMN public.check_in_prompts.question_text             IS 'Optional question shown to the child (e.g. "How was school today?").';
COMMENT ON COLUMN public.check_in_prompts.reply_check_in_id         IS 'Set to the check_in.id when the child replies. NULL = awaiting reply.';
COMMENT ON COLUMN public.check_in_prompts.scheduled_at              IS 'Optional future time at which the prompt should be delivered (e.g. after school, before bed).';
COMMENT ON COLUMN public.check_in_prompts.sent_at                   IS 'Timestamp when the push notification was dispatched. NULL = not yet sent.';
COMMENT ON COLUMN public.check_in_prompts.created_at                IS 'Row creation timestamp.';
COMMENT ON COLUMN public.check_in_prompts.updated_at                IS 'Last-modified timestamp, stamped by the set_updated_at() trigger.';

COMMENT ON FUNCTION public.shares_child_with(UUID)  IS 'Returns true if the caller and the given account both have access (owner or accepted membership) to at least one common child in an active family. Used to scope adult self check-ins to co-members.';
