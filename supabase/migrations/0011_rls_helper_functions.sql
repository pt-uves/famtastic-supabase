-- ============================================================================
-- FUNCTIONS
-- ============================================================================

-- Is the current user an active member of this family?
CREATE OR REPLACE FUNCTION is_family_member(p_family_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT exists (
    SELECT 1 FROM family_members
    WHERE family_id = p_family_id
      AND profile_id = auth.uid()
      AND status = 'active'
  );
$$;

-- The current user's own family_members.id within a given family (null if not a member)
CREATE OR REPLACE FUNCTION my_member_id(p_family_id uuid)
RETURNS uuid LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT id FROM family_members
  WHERE family_id = p_family_id
    AND profile_id = auth.uid()
    AND status = 'active'
  LIMIT 1;
$$;

-- Does the current user have provider access to this specific child, for this data category?
-- Only tables that opt in to this clause are provider-visible at all (see 0012).
CREATE OR REPLACE FUNCTION has_provider_access(p_child_member_id uuid, p_scope text)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT exists (
    SELECT 1 FROM child_providers
    WHERE child_member_id = p_child_member_id
      AND provider_profile_id = auth.uid()
      AND status = 'active'
      AND p_scope = ANY(access_scope)
  );
$$;

-- Is the current user a platform admin?
CREATE OR REPLACE FUNCTION is_platform_admin()
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT exists (
    SELECT 1 FROM profiles
    WHERE id = auth.uid()
      AND role_global = 'platform_admin'
  );
$$;

-- ============================================================================
-- COMMENTS SECTION
-- ============================================================================

COMMENT ON FUNCTION is_family_member IS 'Checks if the user is an active member of the family.';
COMMENT ON FUNCTION my_member_id IS 'Returns the users family member ID within a family.';
COMMENT ON FUNCTION has_provider_access IS 'Checks if the user has provider access to a specific child for a data category.';
COMMENT ON FUNCTION is_platform_admin IS 'Checks if the user is a platform admin.';
