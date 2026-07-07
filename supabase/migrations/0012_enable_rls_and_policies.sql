-- ============================================================================
-- FUNCTIONS
-- ============================================================================

CREATE OR REPLACE FUNCTION member_family_id(p_member_id uuid)
RETURNS uuid LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT family_id FROM family_members WHERE id = p_member_id;
$$;

-- ============================================================================
-- POLICIES
-- ============================================================================

-- ---------- profiles ----------
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "profiles_select_own_or_admin" ON profiles;
CREATE POLICY "profiles_select_own_or_admin" ON profiles FOR SELECT USING (id = auth.uid() OR is_platform_admin());

DROP POLICY IF EXISTS "profiles_update_own" ON profiles;
CREATE POLICY "profiles_update_own" ON profiles FOR UPDATE USING (id = auth.uid());

-- The handle_new_user trigger runs SECURITY DEFINER so it bypasses RLS.
-- This INSERT policy covers any other direct insert paths from the client.
DROP POLICY IF EXISTS "profiles_insert_own" ON profiles;
CREATE POLICY "profiles_insert_own" ON profiles FOR INSERT WITH CHECK (id = auth.uid());

-- ---------- families ----------
ALTER TABLE families ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "families_select" ON families;
CREATE POLICY "families_select" ON families FOR SELECT USING (is_family_member(id) OR is_platform_admin());

DROP POLICY IF EXISTS "families_insert_self" ON families;
CREATE POLICY "families_insert_self" ON families FOR INSERT WITH CHECK (created_by = auth.uid());

DROP POLICY IF EXISTS "families_update_admin" ON families;
CREATE POLICY "families_update_admin" ON families FOR UPDATE USING (
  EXISTS (SELECT 1 FROM family_members WHERE family_id = families.id AND profile_id = auth.uid() AND role = 'family_admin' AND status = 'active')
  OR is_platform_admin()
);

-- ---------- family_members ----------
ALTER TABLE family_members ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "family_members_select" ON family_members;
CREATE POLICY "family_members_select" ON family_members FOR SELECT USING (
  is_family_member(family_id) OR profile_id = auth.uid() OR is_platform_admin()
);

DROP POLICY IF EXISTS "family_members_write_admin" ON family_members;
CREATE POLICY "family_members_write_admin" ON family_members FOR ALL USING (
  EXISTS (SELECT 1 FROM family_members fm WHERE fm.family_id = family_members.family_id AND fm.profile_id = auth.uid() AND fm.role = 'family_admin' AND fm.status = 'active')
  OR is_platform_admin()
);

-- ---------- child_profiles ----------
ALTER TABLE child_profiles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "child_profiles_select" ON child_profiles;
CREATE POLICY "child_profiles_select" ON child_profiles FOR SELECT USING (
  is_family_member(member_family_id(member_id))
  OR EXISTS (SELECT 1 FROM child_providers cp WHERE cp.child_member_id = child_profiles.member_id AND cp.provider_profile_id = auth.uid() AND cp.status = 'active')
  OR is_platform_admin()
);

DROP POLICY IF EXISTS "child_profiles_write" ON child_profiles;
CREATE POLICY "child_profiles_write" ON child_profiles FOR ALL USING (is_family_member(member_family_id(member_id)) OR is_platform_admin());

-- ---------- family_invites ----------
ALTER TABLE family_invites ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "family_invites_all" ON family_invites;
CREATE POLICY "family_invites_all" ON family_invites FOR ALL USING (is_family_member(family_id) OR is_platform_admin());

-- ---------- child_providers ----------
ALTER TABLE child_providers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "child_providers_select" ON child_providers;
CREATE POLICY "child_providers_select" ON child_providers FOR SELECT USING (
  is_family_member(member_family_id(child_member_id))
  OR provider_profile_id = auth.uid()
  OR is_platform_admin()
);

DROP POLICY IF EXISTS "child_providers_write_family" ON child_providers;
CREATE POLICY "child_providers_write_family" ON child_providers FOR INSERT WITH CHECK (is_family_member(member_family_id(child_member_id)));

DROP POLICY IF EXISTS "child_providers_update_family" ON child_providers;
CREATE POLICY "child_providers_update_family" ON child_providers FOR UPDATE USING (is_family_member(member_family_id(child_member_id)) OR is_platform_admin());

-- ---------- child_provider_invites ----------
ALTER TABLE child_provider_invites ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "child_provider_invites_family" ON child_provider_invites;
CREATE POLICY "child_provider_invites_family" ON child_provider_invites FOR ALL USING (is_family_member(member_family_id(child_member_id)) OR is_platform_admin());

-- ---------- check_ins ----------
ALTER TABLE check_ins ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "check_ins_select" ON check_ins;
CREATE POLICY "check_ins_select" ON check_ins FOR SELECT USING (
  is_family_member(family_id)
  OR member_id = my_member_id(family_id)
  OR has_provider_access(member_id, 'check_ins')
);

DROP POLICY IF EXISTS "check_ins_insert_own" ON check_ins;
CREATE POLICY "check_ins_insert_own" ON check_ins FOR INSERT WITH CHECK (member_id = my_member_id(family_id));

-- ---------- coping_strategies ----------
ALTER TABLE coping_strategies ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "coping_strategies_select" ON coping_strategies;
CREATE POLICY "coping_strategies_select" ON coping_strategies FOR SELECT USING (is_global = true OR is_family_member(family_id));

DROP POLICY IF EXISTS "coping_strategies_write" ON coping_strategies;
CREATE POLICY "coping_strategies_write" ON coping_strategies FOR ALL USING (
  (is_global = true AND is_platform_admin())
  OR (is_global = false AND is_family_member(family_id))
);

-- ---------- nudges ----------
ALTER TABLE nudges ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "nudges_select" ON nudges;
CREATE POLICY "nudges_select" ON nudges FOR SELECT USING (is_family_member(family_id));

DROP POLICY IF EXISTS "nudges_insert" ON nudges;
CREATE POLICY "nudges_insert" ON nudges FOR INSERT WITH CHECK (is_family_member(family_id) AND from_member = my_member_id(family_id));

DROP POLICY IF EXISTS "nudges_update_read_receipt" ON nudges;
CREATE POLICY "nudges_update_read_receipt" ON nudges FOR UPDATE USING (is_family_member(family_id));

-- ---------- task_categories ----------
ALTER TABLE task_categories ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "task_categories_select" ON task_categories;
CREATE POLICY "task_categories_select" ON task_categories FOR SELECT USING (family_id IS NULL OR is_family_member(family_id));

DROP POLICY IF EXISTS "task_categories_write" ON task_categories;
CREATE POLICY "task_categories_write" ON task_categories FOR ALL USING (
  (family_id IS NULL AND is_platform_admin())
  OR (family_id IS NOT NULL AND is_family_member(family_id))
);

-- ---------- tasks ----------
ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tasks_select" ON tasks;
CREATE POLICY "tasks_select" ON tasks FOR SELECT USING (
  is_family_member(family_id) OR has_provider_access(assignee_id, 'tasks')
);

DROP POLICY IF EXISTS "tasks_write" ON tasks;
CREATE POLICY "tasks_write" ON tasks FOR ALL USING (is_family_member(family_id));

-- ---------- task_verifications ----------
ALTER TABLE task_verifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "task_verifications_all" ON task_verifications;
CREATE POLICY "task_verifications_all" ON task_verifications FOR ALL USING (
  EXISTS (SELECT 1 FROM tasks t WHERE t.id = task_verifications.task_id AND is_family_member(t.family_id))
);

-- ---------- speech_exercises ----------
ALTER TABLE speech_exercises ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "speech_exercises_select_all" ON speech_exercises;
CREATE POLICY "speech_exercises_select_all" ON speech_exercises FOR SELECT USING (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "speech_exercises_write_admin" ON speech_exercises;
CREATE POLICY "speech_exercises_write_admin" ON speech_exercises FOR ALL USING (is_platform_admin());

-- ---------- custom_word_lists ----------
ALTER TABLE custom_word_lists ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "custom_word_lists_select" ON custom_word_lists;
CREATE POLICY "custom_word_lists_select" ON custom_word_lists FOR SELECT USING (
  is_family_member(family_id) OR has_provider_access(child_id, 'speech')
);

DROP POLICY IF EXISTS "custom_word_lists_write" ON custom_word_lists;
CREATE POLICY "custom_word_lists_write" ON custom_word_lists FOR ALL USING (is_family_member(family_id));

-- ---------- speech_attempts ----------
ALTER TABLE speech_attempts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "speech_attempts_select" ON speech_attempts;
CREATE POLICY "speech_attempts_select" ON speech_attempts FOR SELECT USING (
  is_family_member(member_family_id(child_id)) OR has_provider_access(child_id, 'speech')
);

DROP POLICY IF EXISTS "speech_attempts_insert_own" ON speech_attempts;
CREATE POLICY "speech_attempts_insert_own" ON speech_attempts FOR INSERT WITH CHECK (child_id = my_member_id(member_family_id(child_id)));

-- ---------- emergency_contacts ----------
ALTER TABLE emergency_contacts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "emergency_contacts_all" ON emergency_contacts;
CREATE POLICY "emergency_contacts_all" ON emergency_contacts FOR ALL USING (is_family_member(family_id));

-- ---------- sos_alerts ----------
ALTER TABLE sos_alerts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "sos_alerts_all" ON sos_alerts;
CREATE POLICY "sos_alerts_all" ON sos_alerts FOR ALL USING (is_family_member(family_id));

-- ---------- sos_cooldowns ----------
ALTER TABLE sos_cooldowns ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "sos_cooldowns_all" ON sos_cooldowns;
CREATE POLICY "sos_cooldowns_all" ON sos_cooldowns FOR ALL USING (is_family_member(member_family_id(member_id)));

-- ---------- routines / routine_steps / routine_completions ----------
ALTER TABLE routines ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "routines_select" ON routines;
CREATE POLICY "routines_select" ON routines FOR SELECT USING (is_family_member(family_id) OR has_provider_access(child_id, 'routines'));

DROP POLICY IF EXISTS "routines_write" ON routines;
CREATE POLICY "routines_write" ON routines FOR ALL USING (is_family_member(family_id));

ALTER TABLE routine_steps ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "routine_steps_all" ON routine_steps;
CREATE POLICY "routine_steps_all" ON routine_steps FOR ALL USING (
  EXISTS (SELECT 1 FROM routines r WHERE r.id = routine_steps.routine_id
    AND (is_family_member(r.family_id) OR has_provider_access(r.child_id, 'routines')))
);

ALTER TABLE routine_completions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "routine_completions_all" ON routine_completions;
CREATE POLICY "routine_completions_all" ON routine_completions FOR ALL USING (
  is_family_member(member_family_id(child_id)) OR has_provider_access(child_id, 'routines')
);

-- ---------- habits / habit_logs ----------
ALTER TABLE habits ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "habits_all" ON habits;
CREATE POLICY "habits_all" ON habits FOR ALL USING (is_family_member(family_id));

ALTER TABLE habit_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "habit_logs_all" ON habit_logs;
CREATE POLICY "habit_logs_all" ON habit_logs FOR ALL USING (
  EXISTS (SELECT 1 FROM habits h WHERE h.id = habit_logs.habit_id AND is_family_member(h.family_id))
);

-- ---------- member_locations / location_sharing_prefs ----------
ALTER TABLE member_locations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "member_locations_all" ON member_locations;
CREATE POLICY "member_locations_all" ON member_locations FOR ALL USING (is_family_member(member_family_id(member_id)));

ALTER TABLE location_sharing_prefs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "location_sharing_prefs_all" ON location_sharing_prefs;
CREATE POLICY "location_sharing_prefs_all" ON location_sharing_prefs FOR ALL USING (is_family_member(member_family_id(member_id)));

-- ---------- rewards ----------
ALTER TABLE points_ledger ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "points_ledger_all" ON points_ledger;
CREATE POLICY "points_ledger_all" ON points_ledger FOR ALL USING (is_family_member(member_family_id(child_id)));

ALTER TABLE badges ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "badges_select_all" ON badges;
CREATE POLICY "badges_select_all" ON badges FOR SELECT USING (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "badges_write_admin" ON badges;
CREATE POLICY "badges_write_admin" ON badges FOR ALL USING (is_platform_admin());

ALTER TABLE child_badges ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "child_badges_all" ON child_badges;
CREATE POLICY "child_badges_all" ON child_badges FOR ALL USING (is_family_member(member_family_id(child_id)));

ALTER TABLE reward_shop_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "reward_shop_items_select" ON reward_shop_items;
CREATE POLICY "reward_shop_items_select" ON reward_shop_items FOR SELECT USING (family_id IS NULL OR is_family_member(family_id));

DROP POLICY IF EXISTS "reward_shop_items_write" ON reward_shop_items;
CREATE POLICY "reward_shop_items_write" ON reward_shop_items FOR ALL USING (
  (family_id IS NULL AND is_platform_admin())
  OR (family_id IS NOT NULL AND is_family_member(family_id))
);

ALTER TABLE reward_redemptions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "reward_redemptions_all" ON reward_redemptions;
CREATE POLICY "reward_redemptions_all" ON reward_redemptions FOR ALL USING (is_family_member(member_family_id(child_id)));

-- ---------- content / platform admin ----------
ALTER TABLE content_variants ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "content_variants_select_all" ON content_variants;
CREATE POLICY "content_variants_select_all" ON content_variants FOR SELECT USING (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "content_variants_write_admin" ON content_variants;
CREATE POLICY "content_variants_write_admin" ON content_variants FOR ALL USING (is_platform_admin());

ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "audit_log_admin_only" ON audit_log;
CREATE POLICY "audit_log_admin_only" ON audit_log FOR ALL USING (is_platform_admin());

ALTER TABLE push_campaigns ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "push_campaigns_admin_only" ON push_campaigns;
CREATE POLICY "push_campaigns_admin_only" ON push_campaigns FOR ALL USING (is_platform_admin());

ALTER TABLE app_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "app_settings_admin_only" ON app_settings;
CREATE POLICY "app_settings_admin_only" ON app_settings FOR ALL USING (is_platform_admin());

-- ============================================================================
-- COMMENTS SECTION
-- ============================================================================

COMMENT ON FUNCTION member_family_id IS 'Returns the family ID for a given family member.';

-- ============================================================================
-- AUTH AUDIT VIEW
-- ============================================================================
-- Surfaces recent auth events (last 30 days) from auth.audit_log_entries
-- to platform admins. The auth schema is not PostgREST-accessible directly,
-- so we expose it through a public view with security_invoker = true
-- (the caller's own RLS context is used, restricting access to admins).

CREATE OR REPLACE VIEW public.auth_audit_view
  WITH (security_invoker = true)
AS
SELECT
  id,
  instance_id,
  payload->>'action'      AS action,
  payload->>'actor_id'    AS actor_id,
  payload->>'actor_name'  AS actor_email,
  ip_address,
  created_at
FROM auth.audit_log_entries
WHERE created_at > (CURRENT_TIMESTAMP - INTERVAL '30 days')
ORDER BY created_at DESC;

GRANT SELECT ON public.auth_audit_view TO authenticated;

COMMENT ON VIEW public.auth_audit_view IS
  'Platform-admin view of recent auth events (last 30 days) from auth.audit_log_entries.';
