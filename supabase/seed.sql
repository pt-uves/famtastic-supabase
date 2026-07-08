-- =========================================================
-- seed.sql — run automatically by `supabase db reset`
-- =========================================================

-- ---------------------------------------------------------
-- Global reference/content data (safe to seed unconditionally)
-- ---------------------------------------------------------

insert into task_categories (id, child_id, name, color_hex, is_system) values
  ('11111111-0000-0000-0000-000000000001', null, 'Relationships/Family', '#F4A6A6', true),
  ('11111111-0000-0000-0000-000000000002', null, 'Chores', '#A6D8F4', true),
  ('11111111-0000-0000-0000-000000000003', null, 'School', '#F4E1A6', true),
  ('11111111-0000-0000-0000-000000000004', null, 'Health', '#A6F4C1', true)
ON CONFLICT (id) DO NOTHING;

insert into speech_exercises (id, word, difficulty) values
  ('33333333-0000-0000-0000-000000000001', 'cat', 'beginner'),
  ('33333333-0000-0000-0000-000000000002', 'rabbit', 'intermediate'),
  ('33333333-0000-0000-0000-000000000003', 'spaghetti', 'advanced')
ON CONFLICT (id) DO NOTHING;

-- ---------------------------------------------------------
-- Test users / families
--
-- auth.users rows can't be reliably inserted with raw SQL (GoTrue owns
-- password hashing). Practical local workflow:
--   1. supabase start
--   2. Open http://localhost:54323 -> Authentication -> Add user, and
--      create 5 test accounts: 2 parents, 2 children, 1 provider.
--   3. Copy their UUIDs into the placeholders below, uncomment, and
--      re-run `supabase db reset` (seed.sql runs every reset).
-- ---------------------------------------------------------

-- insert into families (id, name, owner_id) values
--   ('11111111-1111-1111-1111-111111111111', 'Thompson Family', '<parent-1-auth-uid>');
--
-- insert into children (id, family_id, name) values
--   ('33333333-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', 'Child 1'),
--   ('44444444-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', 'Child 2');
--
-- insert into memberships (account_id, child_id, role_category, role_label, invite_status) values
--   ('<parent-1-auth-uid>', '33333333-1111-1111-1111-111111111111', 'co_parent', 'Dad', 'accepted'),
--   ('<parent-1-auth-uid>', '44444444-1111-1111-1111-111111111111', 'co_parent', 'Dad', 'accepted'),
--   ('<parent-2-auth-uid>', '33333333-1111-1111-1111-111111111111', 'co_parent', 'Mom', 'accepted'),
--   ('<parent-2-auth-uid>', '44444444-1111-1111-1111-111111111111', 'co_parent', 'Mom', 'accepted');
--
-- -- Provider scoped ONLY to child 1
-- insert into memberships (account_id, child_id, role_category, role_label, invite_status) values
--   ('<provider-auth-uid>', '33333333-1111-1111-1111-111111111111', 'therapist', 'Dr. Smith', 'accepted');
