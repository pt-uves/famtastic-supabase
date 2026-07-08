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
-- A check-in row is created by any member (adult) or triggered by the child
-- themselves (is_from_child = true, author_id = NULL).
-- One-tap mood + optional text + optional voice note.
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.check_ins (
    id                      UUID        PRIMARY KEY DEFAULT uuid_generate_v7(),
    child_id                UUID        NOT NULL,
    author_id               UUID,
    is_from_child           BOOLEAN     NOT NULL DEFAULT false,
    mood                    mood        NOT NULL,
    text_response           TEXT,
    voice_note_url          TEXT,
    shared_with_family      BOOLEAN     NOT NULL DEFAULT true,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- An adult check-in must have an author; a child check-in must not.
    CONSTRAINT chk_check_ins_author CHECK (
        (is_from_child = true AND author_id IS NULL) OR
        (is_from_child = false AND author_id IS NOT NULL)
    )
);

-- ============================================================================
-- INDEXES / CONSTRAINTS
-- ============================================================================

ALTER TABLE public.check_ins DROP CONSTRAINT IF EXISTS fk_check_ins_child;
ALTER TABLE public.check_ins ADD CONSTRAINT fk_check_ins_child
    FOREIGN KEY (child_id) REFERENCES public.children (id) ON DELETE CASCADE;

ALTER TABLE public.check_ins DROP CONSTRAINT IF EXISTS fk_check_ins_author;
ALTER TABLE public.check_ins ADD CONSTRAINT fk_check_ins_author
    FOREIGN KEY (author_id) REFERENCES public.profiles (id) ON DELETE SET NULL;

-- Mood chart queries: filter by child and order by time.
CREATE INDEX IF NOT EXISTS idx_check_ins_child_created
    ON public.check_ins (child_id, created_at DESC);

-- ============================================================================
-- RLS POLICIES
-- ============================================================================

ALTER TABLE public.check_ins ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "check_ins_select_policy" ON public.check_ins;
CREATE POLICY "check_ins_select_policy" ON public.check_ins
    FOR SELECT USING (
        owns_child(child_id) OR is_linked_to_child(child_id) OR is_platform_admin()
    );

DROP POLICY IF EXISTS "check_ins_insert_policy" ON public.check_ins;
CREATE POLICY "check_ins_insert_policy" ON public.check_ins
    FOR INSERT WITH CHECK (
        owns_child(child_id) OR is_linked_to_child(child_id)
    );

DROP POLICY IF EXISTS "check_ins_update_policy" ON public.check_ins;
CREATE POLICY "check_ins_update_policy" ON public.check_ins
    FOR UPDATE USING (author_id = auth.uid());

DROP POLICY IF EXISTS "check_ins_delete_policy" ON public.check_ins;
CREATE POLICY "check_ins_delete_policy" ON public.check_ins
    FOR DELETE USING (owns_child(child_id));

-- ============================================================================
-- COMMENTS SECTION
-- ============================================================================

COMMENT ON TYPE  mood                              IS 'Four supported mood states used in check-ins and analytics.';

COMMENT ON TABLE  public.check_ins                      IS 'A mood check-in created by a family member or by the child themselves in Child Mode.';
COMMENT ON COLUMN public.check_ins.id                   IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN public.check_ins.child_id             IS 'The child this check-in is about.';
COMMENT ON COLUMN public.check_ins.author_id            IS 'The adult member who submitted this check-in. NULL when is_from_child = true.';
COMMENT ON COLUMN public.check_ins.is_from_child        IS 'True when the child submitted the reply in Child Mode.';
COMMENT ON COLUMN public.check_ins.mood                 IS 'Mood selected: happy, calm, overwhelmed, or angry.';
COMMENT ON COLUMN public.check_ins.text_response        IS 'Optional short written response from the author.';
COMMENT ON COLUMN public.check_ins.voice_note_url       IS 'URL to a voice note recording stored in Supabase Storage.';
COMMENT ON COLUMN public.check_ins.shared_with_family   IS 'Whether this check-in is visible to all linked members or only the author.';
COMMENT ON COLUMN public.check_ins.created_at           IS 'Row creation timestamp — used as the check-in timestamp.';
