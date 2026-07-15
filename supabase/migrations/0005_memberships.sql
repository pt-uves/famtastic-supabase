-- ============================================================================
-- ENUMS
-- ============================================================================

DROP TYPE IF EXISTS membership_role CASCADE;
CREATE TYPE membership_role AS ENUM (
    'co_parent',
    'caregiver',
    'grandparent',
    'teacher',
    'therapist',
    'relative',
    'other'
);

DROP TYPE IF EXISTS invite_status CASCADE;
CREATE TYPE invite_status AS ENUM ('pending', 'accepted', 'declined');

-- ============================================================================
-- TABLES
-- ============================================================================

-- ----------------------------------------------------------------------------
-- memberships
-- The many-to-many link between an account (profile) and a child.
-- A role lives on the membership, not the account - one person can be a
-- co-parent in their own family and a therapist in another.
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.memberships (
    id              UUID                    PRIMARY KEY DEFAULT uuid_generate_v7(),
    account_id      UUID                    NOT NULL,
    child_id        UUID                    NOT NULL,
    role_category   membership_role         NOT NULL,
    role_label      TEXT,
    invited_by      UUID,
    invite_status   invite_status           NOT NULL DEFAULT 'pending',
    created_at      TIMESTAMPTZ             NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMPTZ             NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ----------------------------------------------------------------------------
-- emergency_contacts
-- Not app users - name + phone only. Receive SMS on SOS.
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.emergency_contacts (
    id          UUID        PRIMARY KEY DEFAULT uuid_generate_v7(),
    child_id    UUID        NOT NULL,
    added_by    UUID,
    name        TEXT        NOT NULL,
    phone       TEXT        NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- INDEXES / CONSTRAINTS
-- ============================================================================

-- A person can be linked to a child only once.
CREATE UNIQUE INDEX IF NOT EXISTS uk_memberships_account_child
    ON public.memberships (account_id, child_id);

ALTER TABLE public.memberships DROP CONSTRAINT IF EXISTS fk_memberships_account;
ALTER TABLE public.memberships ADD CONSTRAINT fk_memberships_account
    FOREIGN KEY (account_id) REFERENCES public.profiles (id) ON DELETE CASCADE;

ALTER TABLE public.memberships DROP CONSTRAINT IF EXISTS fk_memberships_child;
ALTER TABLE public.memberships ADD CONSTRAINT fk_memberships_child
    FOREIGN KEY (child_id) REFERENCES public.children (id) ON DELETE CASCADE;

ALTER TABLE public.memberships DROP CONSTRAINT IF EXISTS fk_memberships_invited_by;
ALTER TABLE public.memberships ADD CONSTRAINT fk_memberships_invited_by
    FOREIGN KEY (invited_by) REFERENCES public.profiles (id) ON DELETE SET NULL;

-- Most common query: "which children is this account linked to?"
CREATE INDEX IF NOT EXISTS idx_memberships_account_id ON public.memberships (account_id);

-- Common query: "who is linked to this child?" (member management screen)
CREATE INDEX IF NOT EXISTS idx_memberships_child_id ON public.memberships (child_id);

ALTER TABLE public.emergency_contacts DROP CONSTRAINT IF EXISTS fk_emergency_contacts_child;
ALTER TABLE public.emergency_contacts ADD CONSTRAINT fk_emergency_contacts_child
    FOREIGN KEY (child_id) REFERENCES public.children (id) ON DELETE CASCADE;

ALTER TABLE public.emergency_contacts DROP CONSTRAINT IF EXISTS fk_emergency_contacts_added_by;
ALTER TABLE public.emergency_contacts ADD CONSTRAINT fk_emergency_contacts_added_by
    FOREIGN KEY (added_by) REFERENCES public.profiles (id) ON DELETE SET NULL;


-- ----------------------------------------------------------------------------
-- is_linked_to_child(p_child_id UUID)
-- Returns true if the current user has an accepted membership for the child
-- AND the child's family is active (a suspended family blocks all access).
-- This is the core access-control predicate used across most tables.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.is_linked_to_child(p_child_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.memberships m
        JOIN public.children c ON c.id = m.child_id
        JOIN public.families f ON f.id = c.family_id
        WHERE m.child_id = p_child_id
          AND m.account_id = auth.uid()
          AND m.invite_status = 'accepted'
          AND f.status = 'active'
    );
$$;

-- ----------------------------------------------------------------------------
-- is_family_owner(p_family_id UUID)
-- Returns true if the current user owns the given family and it is active.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.is_family_owner(p_family_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.families
        WHERE id = p_family_id
          AND owner_id = auth.uid()
          AND status = 'active'
    );
$$;

-- ----------------------------------------------------------------------------
-- owns_child(p_child_id UUID)
-- Returns true if the current user owns the (active) family that the child
-- belongs to. Used to restrict parent-only actions (e.g. deleting a child,
-- Child Mode). A suspended family returns false for its owner.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.owns_child(p_child_id UUID)
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
        WHERE c.id = p_child_id
          AND f.owner_id = auth.uid()
          AND f.status = 'active'
    );
$$;

-- ============================================================================
-- FUNCTIONS / TRIGGERS
-- ============================================================================

-- ----------------------------------------------------------------------------
-- prevent_owner_membership()
-- Enforces the invariant "a family owner is never a member of their own child".
-- The owner already has full access via owns_child()/is_family_owner(); a
-- self-membership would duplicate the child across the "My family" and "Children"
-- views and list the owner in their own child's member roster. Runs on every
-- write path, including the service-role edge functions that bypass RLS.
-- SECURITY DEFINER so it can read families/children regardless of the caller.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.prevent_owner_membership()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM public.children c
        JOIN public.families f ON f.id = c.family_id
        WHERE c.id = NEW.child_id
          AND f.owner_id = NEW.account_id
    ) THEN
        RAISE EXCEPTION
            'A family owner cannot be a member of their own child (account_id=%, child_id=%).',
            NEW.account_id, NEW.child_id
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_memberships_prevent_owner ON public.memberships;
CREATE TRIGGER trigger_memberships_prevent_owner
    BEFORE INSERT OR UPDATE ON public.memberships
    FOR EACH ROW
    EXECUTE FUNCTION public.prevent_owner_membership();

-- ----------------------------------------------------------------------------
-- account_id and child_id are the identity of the link and are immutable after
-- insert. Without this, the memberships UPDATE policy (which an invitee can
-- satisfy for their own row) would let a member repoint child_id to ANY child -
-- instant unauthorised access to a child in another family. Re-linking to a
-- different child is a new row, never an UPDATE. Runs on every write path,
-- including service-role edge functions that bypass RLS.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.prevent_membership_identity_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF NEW.account_id IS DISTINCT FROM OLD.account_id THEN
        RAISE EXCEPTION 'memberships.account_id is immutable (id=%).', OLD.id
            USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.child_id IS DISTINCT FROM OLD.child_id THEN
        RAISE EXCEPTION 'memberships.child_id is immutable (id=%).', OLD.id
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_memberships_prevent_identity_change ON public.memberships;
CREATE TRIGGER trigger_memberships_prevent_identity_change
    BEFORE UPDATE ON public.memberships
    FOR EACH ROW
    EXECUTE FUNCTION public.prevent_membership_identity_change();

-- Keep updated_at current on every change.
DROP TRIGGER IF EXISTS trigger_memberships_set_updated_at ON public.memberships;
CREATE TRIGGER trigger_memberships_set_updated_at
    BEFORE UPDATE ON public.memberships
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trigger_emergency_contacts_set_updated_at ON public.emergency_contacts;
CREATE TRIGGER trigger_emergency_contacts_set_updated_at
    BEFORE UPDATE ON public.emergency_contacts
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

-- ============================================================================
-- RLS POLICIES (All related tables)
-- ============================================================================

ALTER TABLE public.memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.emergency_contacts ENABLE ROW LEVEL SECURITY;

-- POLICIES - memberships

DROP POLICY IF EXISTS "memberships_select_policy" ON public.memberships;
CREATE POLICY "memberships_select_policy" ON public.memberships
    FOR SELECT USING (
        account_id = auth.uid()
        OR owns_child(child_id)
        OR is_platform_admin()
    );

DROP POLICY IF EXISTS "memberships_insert_policy" ON public.memberships;
CREATE POLICY "memberships_insert_policy" ON public.memberships
    FOR INSERT WITH CHECK (owns_child(child_id));

-- account_id / child_id are held immutable by the
-- prevent_membership_identity_change() trigger, so the invitee branch here can
-- only touch their own invite_status (accept/decline), never repoint the link.
DROP POLICY IF EXISTS "memberships_update_policy" ON public.memberships;
CREATE POLICY "memberships_update_policy" ON public.memberships
    FOR UPDATE
    USING (
        account_id = auth.uid()   -- member can accept/decline their own invite
        OR owns_child(child_id)   -- parent can update role/status
    )
    WITH CHECK (
        account_id = auth.uid()
        OR owns_child(child_id)
    );

DROP POLICY IF EXISTS "memberships_delete_policy" ON public.memberships;
CREATE POLICY "memberships_delete_policy" ON public.memberships
    FOR DELETE USING (owns_child(child_id));

-- POLICIES - emergency_contacts

DROP POLICY IF EXISTS "emergency_contacts_select_policy" ON public.emergency_contacts;
CREATE POLICY "emergency_contacts_select_policy" ON public.emergency_contacts
    FOR SELECT USING (
        owns_child(child_id) OR is_linked_to_child(child_id) OR is_platform_admin()
    );

DROP POLICY IF EXISTS "emergency_contacts_insert_policy" ON public.emergency_contacts;
CREATE POLICY "emergency_contacts_insert_policy" ON public.emergency_contacts
    FOR INSERT WITH CHECK (owns_child(child_id));

DROP POLICY IF EXISTS "emergency_contacts_update_policy" ON public.emergency_contacts;
CREATE POLICY "emergency_contacts_update_policy" ON public.emergency_contacts
    FOR UPDATE USING (owns_child(child_id));

DROP POLICY IF EXISTS "emergency_contacts_delete_policy" ON public.emergency_contacts;
CREATE POLICY "emergency_contacts_delete_policy" ON public.emergency_contacts
    FOR DELETE USING (owns_child(child_id));

-- POLICIES - families

DROP POLICY IF EXISTS "families_select_policy" ON public.families;
CREATE POLICY "families_select_policy" ON public.families
    FOR SELECT USING (
        owner_id = auth.uid()
        OR is_platform_admin()
        OR EXISTS (
            SELECT 1 FROM public.children c
            JOIN public.memberships m ON m.child_id = c.id
            WHERE c.family_id = families.id
              AND m.account_id = auth.uid()
              AND m.invite_status = 'accepted'
              AND families.status = 'active'   -- a suspended family is hidden from members too
        )
    );

DROP POLICY IF EXISTS "families_insert_policy" ON public.families;
CREATE POLICY "families_insert_policy" ON public.families
    FOR INSERT WITH CHECK (owner_id = auth.uid());

-- Only a platform admin can suspend/un-suspend. An active owner may edit their
-- own family but cannot set status = 'suspended'; a suspended owner is locked out
-- entirely (cannot edit or self-un-suspend).
DROP POLICY IF EXISTS "families_update_policy" ON public.families;
CREATE POLICY "families_update_policy" ON public.families
    FOR UPDATE
    USING ((owner_id = auth.uid() AND status = 'active') OR is_platform_admin())
    WITH CHECK ((owner_id = auth.uid() AND status = 'active') OR is_platform_admin());

-- A suspended owner is locked out entirely and must NOT be able to delete
-- (and cascade-wipe) their family to evade suspension. Only an active owner or
-- a platform admin can delete.
DROP POLICY IF EXISTS "families_delete_policy" ON public.families;
CREATE POLICY "families_delete_policy" ON public.families
    FOR DELETE USING (
        (owner_id = auth.uid() AND status = 'active')
        OR is_platform_admin()
    );

-- POLICIES - children

DROP POLICY IF EXISTS "children_select_policy" ON public.children;
CREATE POLICY "children_select_policy" ON public.children
    FOR SELECT USING (
        owns_child(id) OR is_linked_to_child(id) OR is_platform_admin()
    );

DROP POLICY IF EXISTS "children_insert_policy" ON public.children;
CREATE POLICY "children_insert_policy" ON public.children
    FOR INSERT WITH CHECK (is_family_owner(family_id));

DROP POLICY IF EXISTS "children_update_policy" ON public.children;
CREATE POLICY "children_update_policy" ON public.children
    FOR UPDATE USING (owns_child(id) OR is_platform_admin());

DROP POLICY IF EXISTS "children_delete_policy" ON public.children;
CREATE POLICY "children_delete_policy" ON public.children
    FOR DELETE USING (owns_child(id));


-- ============================================================================
-- COMMENTS SECTION
-- ============================================================================

COMMENT ON TYPE  membership_role                   IS 'Categorical role a member holds for a specific child. Used for filtering and UI labelling.';
COMMENT ON TYPE  invite_status                     IS 'State of a membership invitation.';

COMMENT ON TABLE  public.memberships                    IS 'Links an account to a child, carrying the role and permissions for that relationship. The role lives here, not on the account.';
COMMENT ON COLUMN public.memberships.id                 IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN public.memberships.account_id         IS 'The profile (user) being linked to the child.';
COMMENT ON COLUMN public.memberships.child_id           IS 'The child this membership grants access to.';
COMMENT ON COLUMN public.memberships.role_category      IS 'Fixed ENUM category used for filtering and access control.';
COMMENT ON COLUMN public.memberships.role_label         IS 'Free-text display label entered by the parent (e.g. "Nana", "Speech Therapist").';
COMMENT ON COLUMN public.memberships.invited_by         IS 'The parent admin who created this invitation.';
COMMENT ON COLUMN public.memberships.invite_status      IS 'Pending until the invitee accepts; accepted memberships grant access.';
COMMENT ON COLUMN public.memberships.created_at         IS 'Row creation timestamp.';
COMMENT ON COLUMN public.memberships.updated_at         IS 'Last-modified timestamp (e.g. on accept/decline or role change), stamped by the set_updated_at() trigger.';

COMMENT ON TABLE  public.emergency_contacts             IS 'External contacts (not app users) who receive an SMS with child location when SOS is triggered.';
COMMENT ON COLUMN public.emergency_contacts.id          IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN public.emergency_contacts.child_id    IS 'The child this contact is configured for.';
COMMENT ON COLUMN public.emergency_contacts.added_by    IS 'The parent who added this contact (provenance). Nullable: set to NULL if that account is deleted, since the contact belongs to the child.';
COMMENT ON COLUMN public.emergency_contacts.name        IS 'Contact display name (e.g. Dr. Smith, School Nurse).';
COMMENT ON COLUMN public.emergency_contacts.phone       IS 'Mobile number that receives SOS SMS.';
COMMENT ON COLUMN public.emergency_contacts.created_at  IS 'Row creation timestamp.';
COMMENT ON COLUMN public.emergency_contacts.updated_at  IS 'Last-modified timestamp, stamped by the set_updated_at() trigger.';

COMMENT ON FUNCTION public.is_linked_to_child(UUID)         IS 'Returns true if the calling user has an accepted membership for the given child and the child''s family is active (not suspended).';
COMMENT ON FUNCTION public.is_family_owner(UUID)            IS 'Returns true if the calling user owns the given family and it is active (not suspended).';
COMMENT ON FUNCTION public.owns_child(UUID)                 IS 'Returns true if the calling user owns the active family that the given child belongs to. Returns false when the family is suspended.';
COMMENT ON FUNCTION public.prevent_owner_membership()       IS 'Trigger function that blocks creating/updating a membership where the account owns the child''s family - a family owner is never a member of their own child.';
COMMENT ON FUNCTION public.prevent_membership_identity_change() IS 'Trigger function that makes memberships.account_id and child_id immutable after insert, preventing a member from repointing their own membership to another child via UPDATE.';
