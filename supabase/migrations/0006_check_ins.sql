-- ============================================================================
-- ENUMS
-- ============================================================================

DROP TYPE IF EXISTS mood CASCADE;
CREATE TYPE mood AS ENUM ('happy', 'sad', 'overwhelmed', 'angry');

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
    prompt_id               UUID,
    is_from_child           BOOLEAN     NOT NULL DEFAULT false,
    mood                    mood        NOT NULL,
    text_response           TEXT,
    voice_note_path         TEXT,
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
-- A prompt is created by a parent to ask a child to check in; it is sent
-- immediately on creation (no scheduling). The child replies by creating a
-- check_in row (is_from_child = true) that points back here via
-- check_ins.prompt_id. Keeping prompts separate preserves the check_ins.mood
-- NOT NULL constraint and gives a clean audit trail.
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.check_in_prompts (
    id                  UUID        PRIMARY KEY DEFAULT uuid_generate_v7(),
    child_id            UUID        NOT NULL,
    initiated_by        UUID        NOT NULL,
    question_text       TEXT,
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

-- A check-in optionally answers one prompt. If the prompt is deleted the
-- check-in survives with prompt_id set NULL.
ALTER TABLE public.check_ins DROP CONSTRAINT IF EXISTS fk_check_ins_prompt;
ALTER TABLE public.check_ins ADD CONSTRAINT fk_check_ins_prompt
    FOREIGN KEY (prompt_id) REFERENCES public.check_in_prompts (id) ON DELETE SET NULL;

-- Mood chart queries: filter by child and order by time.
CREATE INDEX IF NOT EXISTS idx_check_ins_child_created
    ON public.check_ins (child_id, created_at DESC);

-- Per-member history / "top insight per member": filter by author, order by time.
CREATE INDEX IF NOT EXISTS idx_check_ins_author_created
    ON public.check_ins (author_id, created_at DESC)
    WHERE author_id IS NOT NULL;

-- At most one check-in may answer a given prompt (one reply per prompt).
-- Also powers the "which prompts are still unanswered?" anti-join.
CREATE UNIQUE INDEX IF NOT EXISTS uk_check_ins_prompt
    ON public.check_ins (prompt_id)
    WHERE prompt_id IS NOT NULL;

ALTER TABLE public.check_in_prompts DROP CONSTRAINT IF EXISTS fk_check_in_prompts_child;
ALTER TABLE public.check_in_prompts ADD CONSTRAINT fk_check_in_prompts_child
    FOREIGN KEY (child_id) REFERENCES public.children (id) ON DELETE CASCADE;

ALTER TABLE public.check_in_prompts DROP CONSTRAINT IF EXISTS fk_check_in_prompts_initiated_by;
ALTER TABLE public.check_in_prompts ADD CONSTRAINT fk_check_in_prompts_initiated_by
    FOREIGN KEY (initiated_by) REFERENCES public.profiles (id) ON DELETE CASCADE;

-- Parent queries: all prompts they sent for a child, ordered by time.
CREATE INDEX IF NOT EXISTS idx_check_in_prompts_child_created
    ON public.check_in_prompts (child_id, created_at DESC);

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

-- ----------------------------------------------------------------------------
-- check_in_prompt_consistency()
-- A check-in that answers a prompt must be about the same child the prompt was
-- addressed to. Cross-table invariant that a CHECK constraint cannot express.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.check_in_prompt_consistency()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF NEW.prompt_id IS NOT NULL THEN
        IF NEW.child_id IS NULL THEN
            RAISE EXCEPTION 'A check-in answering a prompt must be about a child (check_in id=%).', NEW.id
                USING ERRCODE = 'check_violation';
        END IF;
        IF NOT EXISTS (
            SELECT 1 FROM public.check_in_prompts p
            WHERE p.id = NEW.prompt_id AND p.child_id = NEW.child_id
        ) THEN
            RAISE EXCEPTION 'check_ins.prompt_id % does not belong to child % .', NEW.prompt_id, NEW.child_id
                USING ERRCODE = 'check_violation';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_check_ins_prompt_consistency ON public.check_ins;
CREATE TRIGGER trigger_check_ins_prompt_consistency
    BEFORE INSERT OR UPDATE ON public.check_ins
    FOR EACH ROW
    EXECUTE FUNCTION public.check_in_prompt_consistency();

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
        -- author sees their own check-ins, but a child-scoped one only while the
        -- child's family is active and they are still linked (a suspended family
        -- or a removed membership hides it). Self check-ins (child_id NULL) have
        -- no family, so they stay visible to their author.
        OR (author_id = auth.uid()
            AND (child_id IS NULL OR owns_child(child_id) OR is_linked_to_child(child_id)))
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
    USING (
        author_id = auth.uid()
        AND (
            child_id IS NULL
            OR owns_child(child_id)
            OR is_linked_to_child(child_id)
        )
    )
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
        OR (author_id = auth.uid()
            AND (child_id IS NULL OR owns_child(child_id) OR is_linked_to_child(child_id)))
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
COMMENT ON COLUMN public.check_ins.prompt_id            IS 'The prompt this check-in answers, or NULL for an unprompted check-in. Unique (one reply per prompt); must belong to the same child (enforced by trigger).';
COMMENT ON COLUMN public.check_ins.is_from_child        IS 'True when the child submitted the reply in Child Mode.';
COMMENT ON COLUMN public.check_ins.mood                 IS 'Mood selected: happy, sad, overwhelmed, or angry.';
COMMENT ON COLUMN public.check_ins.text_response        IS 'Optional short written response from the author.';
COMMENT ON COLUMN public.check_ins.voice_note_path      IS 'Storage object path of the voice note in the voice-notes bucket. Child check-in: voice-notes/{child_id}/{check_in_id}/{file}; adult self check-in (child_id NULL): voice-notes/self/{user_id}/{check_in_id}/{file}. Frontend signs on demand; never store the signed URL.';
COMMENT ON COLUMN public.check_ins.shared_with_family   IS 'Whether this check-in is visible to all linked members or only the author.';
COMMENT ON COLUMN public.check_ins.created_at           IS 'Row creation timestamp - used as the check-in timestamp.';
COMMENT ON COLUMN public.check_ins.updated_at           IS 'Last-modified timestamp, stamped by the set_updated_at() trigger.';

COMMENT ON TABLE  public.check_in_prompts                           IS 'A check-in request sent by a parent to a child, delivered immediately on creation. Keeps prompts separate from check_ins so check_ins.mood stays NOT NULL. The child replies by creating a check_in row that points here via check_ins.prompt_id.';
COMMENT ON COLUMN public.check_in_prompts.id                        IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN public.check_in_prompts.child_id                  IS 'The child this prompt is addressed to.';
COMMENT ON COLUMN public.check_in_prompts.initiated_by              IS 'The parent admin who created this prompt (provenance). Nullable: set to NULL if that account is deleted, since the prompt belongs to the child.';
COMMENT ON COLUMN public.check_in_prompts.question_text             IS 'Optional question shown to the child (e.g. "How was school today?").';
COMMENT ON COLUMN public.check_in_prompts.sent_at                   IS 'Timestamp when the push notification was dispatched. NULL = not yet sent.';
COMMENT ON COLUMN public.check_in_prompts.created_at                IS 'Row creation timestamp.';
COMMENT ON COLUMN public.check_in_prompts.updated_at                IS 'Last-modified timestamp, stamped by the set_updated_at() trigger.';

COMMENT ON FUNCTION public.shares_child_with(UUID)  IS 'Returns true if the caller and the given account both have access (owner or accepted membership) to at least one common child in an active family. Used to scope adult self check-ins to co-members.';
COMMENT ON FUNCTION public.check_in_prompt_consistency()  IS 'Trigger function ensuring a check-in that answers a prompt (prompt_id set) is about the same child the prompt was addressed to.';
