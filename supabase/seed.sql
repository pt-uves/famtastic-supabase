-- =========================================================
-- seed.sql — run automatically by `supabase db reset`
-- =========================================================

-- ---------------------------------------------------------
-- Global reference/content data (safe to seed unconditionally)
-- ---------------------------------------------------------

insert into task_categories (id, family_id, name, color) values
  ('11111111-0000-0000-0000-000000000001', null, 'Relationships/Family', '#F4A6A6'),
  ('11111111-0000-0000-0000-000000000002', null, 'Chores', '#A6D8F4'),
  ('11111111-0000-0000-0000-000000000003', null, 'School', '#F4E1A6'),
  ('11111111-0000-0000-0000-000000000004', null, 'Health', '#A6F4C1')
ON CONFLICT (id) DO NOTHING;

insert into coping_strategies (id, mood, title, icon_url, animation_key, is_global) values
  ('22222222-0000-0000-0000-000000000001', 'angry', 'Count to Ten', null, 'breathe_slow', true),
  ('22222222-0000-0000-0000-000000000002', 'overwhelmed', 'Deep Breathing', null, 'breathe_box', true),
  ('22222222-0000-0000-0000-000000000003', 'calm', 'Keep Going', null, 'sparkle', true),
  ('22222222-0000-0000-0000-000000000004', 'happy', 'Share the Joy', null, 'confetti', true)
ON CONFLICT (id) DO NOTHING;

insert into speech_exercises (id, target_word, difficulty, category, phonetic_hint) values
  ('33333333-0000-0000-0000-000000000001', 'cat', 'easy', 'animals', 'k-a-t'),
  ('33333333-0000-0000-0000-000000000002', 'rabbit', 'medium', 'animals', 'ra-bit'),
  ('33333333-0000-0000-0000-000000000003', 'spaghetti', 'hard', 'food', 'spuh-ge-tee')
ON CONFLICT (id) DO NOTHING;

insert into badges (id, name, description) values
  ('44444444-0000-0000-0000-000000000001', 'First Check-In', 'Completed your first check-in'),
  ('44444444-0000-0000-0000-000000000002', '7-Day Streak', 'Checked in every day for a week'),
  ('44444444-0000-0000-0000-000000000003', 'Word Master', 'Mastered 20 speech words')
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

-- insert into families (id, name, created_by) values
--   ('11111111-1111-1111-1111-111111111111', 'Thompson Family', '<parent-1-auth-uid>');
--
-- insert into family_members (family_id, profile_id, role) values
--   ('11111111-1111-1111-1111-111111111111', '<parent-1-auth-uid>', 'family_admin'),
--   ('11111111-1111-1111-1111-111111111111', '<parent-2-auth-uid>', 'family_member'),
--   ('11111111-1111-1111-1111-111111111111', '<child-1-auth-uid>', 'child'),
--   ('11111111-1111-1111-1111-111111111111', '<child-2-auth-uid>', 'child');
--
-- -- Provider scoped ONLY to child 1 — this is the row to test isolation against
-- insert into child_providers (child_member_id, provider_profile_id, provider_type, status, access_scope)
-- select id, '<provider-auth-uid>', 'therapist', 'active', '{speech,check_ins}'
-- from family_members
-- where family_id = '11111111-1111-1111-1111-111111111111' and profile_id = '<child-1-auth-uid>';
