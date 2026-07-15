-- ============================================================================
-- seed.sql — mock development data, applied after migrations by `supabase db reset`.
--
-- Migrations own all schema + system reference data; this file owns dev data:
-- auth accounts, families, children, memberships, emergency contacts, tasks,
-- check-ins, notifications, push tokens and Child Mode PINs.
--
-- Every account below logs in with password:  password123
-- Child Mode exit PINs:  Sam = 482156,  Priya = 159073
--
-- Data is fictional but realistic (no "test1" / "user2" placeholders). Three
-- families: two active (Okafor, Sharma) and one suspended (Chen) so every
-- family_status / RLS path is exercised.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 0. Clear anything migrations/triggers pre-created so this seed is authoritative.
--    TRUNCATE ... CASCADE is order-independent.
-- ----------------------------------------------------------------------------
TRUNCATE
    public.check_ins,
    public.check_in_prompts,
    public.notifications,
    public.push_tokens,
    public.tasks,
    public.task_categories,
    public.emergency_contacts,
    public.memberships,
    public.children,
    public.families,
    public.profiles
CASCADE;

-- ----------------------------------------------------------------------------
-- 1. Auth accounts. Inserting auth.users fires the handle_new_user trigger, which
--    creates bare public.profiles rows; step 2 overwrites them with full data.
--    Passwords are hashed at seed time so every account shares "password123".
-- ----------------------------------------------------------------------------
INSERT INTO auth.users
    (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
     raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
     is_super_admin, is_sso_user, is_anonymous)
VALUES
  ('00000000-0000-0000-0000-000000000000', 'a058dac5-daf9-484d-9694-e1bd867b1649', 'authenticated', 'authenticated', 'sam.okafor@gmail.com',       extensions.crypt('password123', extensions.gen_salt('bf', 10)), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Sam Okafor","email_verified":true}',   now(), now(), NULL, false, false),
  ('00000000-0000-0000-0000-000000000000', '0a9e1f52-1b34-4c77-8f21-6d2a5b8c9e10', 'authenticated', 'authenticated', 'marcus.okafor@gmail.com',    extensions.crypt('password123', extensions.gen_salt('bf', 10)), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Marcus Okafor","email_verified":true}', now(), now(), NULL, false, false),
  ('00000000-0000-0000-0000-000000000000', '654df0a7-5039-4962-9b63-9aaec7418c72', 'authenticated', 'authenticated', 'priya.sharma@outlook.com',   extensions.crypt('password123', extensions.gen_salt('bf', 10)), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Priya Sharma","email_verified":true}',  now(), now(), NULL, false, false),
  ('00000000-0000-0000-0000-000000000000', '567b979e-56e2-41ed-89d3-90cc5b7f82c8', 'authenticated', 'authenticated', 'lee.chen@gmail.com',         extensions.crypt('password123', extensions.gen_salt('bf', 10)), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Lee Chen","email_verified":true}',      now(), now(), NULL, false, false),
  ('00000000-0000-0000-0000-000000000000', '7faac339-85c1-4f3f-85bd-f690c57838f1', 'authenticated', 'authenticated', 'rohan.mehta@speechworks.com', extensions.crypt('password123', extensions.gen_salt('bf', 10)), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Rohan Mehta","email_verified":true}',   now(), now(), NULL, false, false),
  ('00000000-0000-0000-0000-000000000000', 'f2ab7307-6c95-4a38-b87f-ca55c19d49eb', 'authenticated', 'authenticated', 'nina.rossi@gmail.com',       extensions.crypt('password123', extensions.gen_salt('bf', 10)), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Nina Rossi","email_verified":true}',    now(), now(), NULL, false, false),
  ('00000000-0000-0000-0000-000000000000', '1b8c2d63-2c45-4d88-9a32-7e3b6c9d0f21', 'authenticated', 'authenticated', 'deepa.nair@gmail.com',       extensions.crypt('password123', extensions.gen_salt('bf', 10)), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Deepa Nair","email_verified":true}',    now(), now(), NULL, false, false),
  ('00000000-0000-0000-0000-000000000000', '2c7d3e74-3d56-4e99-ab43-8f4c7d0e1a32', 'authenticated', 'authenticated', 'bianca.fell@brightschool.edu', extensions.crypt('password123', extensions.gen_salt('bf', 10)), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Bianca Fell","email_verified":true}',   now(), now(), NULL, false, false),
  ('00000000-0000-0000-0000-000000000000', '3d6e4f85-4e67-4faa-bc54-9a5d8e1f2b43', 'authenticated', 'authenticated', 'tom.becker@gmail.com',       extensions.crypt('password123', extensions.gen_salt('bf', 10)), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Tom Becker","email_verified":true}',    now(), now(), NULL, false, false),
  ('00000000-0000-0000-0000-000000000000', '5ee670dd-330c-415a-a0e0-c571740ca022', 'authenticated', 'authenticated', 'uves.shaikh@propelius.tech',        extensions.crypt('password123', extensions.gen_salt('bf', 10)), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Uves Shaikh","email_verified":true}',     now(), now(), NULL, false, false);

-- GoTrue scans these token columns into Go strings on login; NULL breaks the
-- scan ("Database error finding user"). Manual auth.users inserts leave them
-- NULL, so force empty strings.
UPDATE auth.users
SET confirmation_token         = '',
    recovery_token             = '',
    email_change               = '',
    email_change_token_new     = '',
    email_change_token_current = '',
    phone_change               = '',
    phone_change_token         = '',
    reauthentication_token     = ''
WHERE instance_id = '00000000-0000-0000-0000-000000000000';

INSERT INTO auth.identities
    (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at, id)
SELECT u.id, u.id,
       jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
       'email', now(), now(), now(), uuid_generate_v7()
FROM auth.users u;

-- ----------------------------------------------------------------------------
-- 2. Profiles (overwrite the trigger-created stubs with real data).
-- ----------------------------------------------------------------------------
-- full_name is a generated column (first_name + last_name); insert the parts, not the whole.
INSERT INTO public.profiles (id, email, first_name, last_name, phone, role, location_visibility) VALUES
  ('a058dac5-daf9-484d-9694-e1bd867b1649', 'sam.okafor@gmail.com',        'Sam',    'Okafor',  '+1-415-555-0101', 'user',  'all_family'),
  ('0a9e1f52-1b34-4c77-8f21-6d2a5b8c9e10', 'marcus.okafor@gmail.com',     'Marcus', 'Okafor',  '+1-415-555-0102', 'user',  'all_family'),
  ('654df0a7-5039-4962-9b63-9aaec7418c72', 'priya.sharma@outlook.com',    'Priya',  'Sharma',  '+1-408-555-0111', 'user',  'all_family'),
  ('567b979e-56e2-41ed-89d3-90cc5b7f82c8', 'lee.chen@gmail.com',          'Lee',    'Chen',    '+1-650-555-0121', 'user',  'all_family'),
  ('7faac339-85c1-4f3f-85bd-f690c57838f1', 'rohan.mehta@speechworks.com', 'Rohan',  'Mehta',   '+1-408-555-0131', 'user',  'only_parents'),
  ('f2ab7307-6c95-4a38-b87f-ca55c19d49eb', 'nina.rossi@gmail.com',        'Nina',   'Rossi',   '+1-408-555-0141', 'user',  'all_family'),
  ('1b8c2d63-2c45-4d88-9a32-7e3b6c9d0f21', 'deepa.nair@gmail.com',        'Deepa',  'Nair',    '+1-408-555-0151', 'user',  'all_family'),
  ('2c7d3e74-3d56-4e99-ab43-8f4c7d0e1a32', 'bianca.fell@brightschool.edu','Bianca', 'Fell',    '+1-408-555-0161', 'user',  'only_parents'),
  ('3d6e4f85-4e67-4faa-bc54-9a5d8e1f2b43', 'tom.becker@gmail.com',        'Tom',    'Becker',  '+1-415-555-0171', 'user',  'nobody'),
  ('5ee670dd-330c-415a-a0e0-c571740ca022', 'uves.shaikh@propelius.tech',  'Ava',    'Admin',   NULL,              'admin', 'all_family')
-- The handle_new_user trigger already inserted a bare stub for each auth.users
-- row above; overwrite it with the full profile.
ON CONFLICT (id) DO UPDATE SET
  email               = EXCLUDED.email,
  first_name          = EXCLUDED.first_name,
  last_name           = EXCLUDED.last_name,
  phone               = EXCLUDED.phone,
  role                = EXCLUDED.role,
  location_visibility = EXCLUDED.location_visibility;

-- ----------------------------------------------------------------------------
-- 3. Families (one owner = one family). Chen is suspended by a platform admin.
-- ----------------------------------------------------------------------------
INSERT INTO public.families (id, name, owner_id, status, leaderboard_enabled) VALUES
  ('019f46db-7029-718f-a58b-c5019ba44117', 'Okafor Household',  'a058dac5-daf9-484d-9694-e1bd867b1649', 'active',    true),
  ('019f46db-7028-71e3-856c-6d9ac24486f9', 'The Sharma Family', '654df0a7-5039-4962-9b63-9aaec7418c72', 'active',    true),
  ('019f46db-7029-7c91-b426-400216523179', 'Chen Family',       '567b979e-56e2-41ed-89d3-90cc5b7f82c8', 'suspended', false);

-- ----------------------------------------------------------------------------
-- 4. Children.
-- ----------------------------------------------------------------------------
INSERT INTO public.children
    (id, family_id, name, date_of_birth, gender, diagnosis, special_notes,
     language_level, communication_preferences, child_mode_enabled, child_mode_device_id, location_sharing_enabled)
VALUES
  ('019f46db-7029-71b6-9692-5ce5b3940f4a', '019f46db-7029-718f-a58b-c5019ba44117', 'Zara',  '2016-01-20', 'female', 'ADHD',         'Takes medication before school. Struggles with transitions between activities.', 'standard', 'Responds well to timers and clear one-step instructions.', true,  'ipad-zara-01', true),
  ('019f46db-7029-7291-a0a0-9a84c10cdcdb', '019f46db-7028-71e3-856c-6d9ac24486f9', 'Joya',  '2017-05-02', 'female', 'Autism',       'Non-verbal. Uses an AAC tablet to communicate. Sensitive to loud noises.',        'simple',   'Uses AAC app; prefers pictures over text.',                true,  'tab-joya-01',  true),
  ('019f46db-7029-72d2-b61d-07a882999c15', '019f46db-7028-71e3-856c-6d9ac24486f9', 'Aarav', '2019-09-14', 'male',   'Speech Delay', 'In weekly speech therapy. Very social and eager to talk.',                         'standard', 'Encourage full sentences; give extra time to respond.',    false, NULL,           true),
  ('019f46db-7029-77a8-8a39-2ab6411ae263', '019f46db-7029-7c91-b426-400216523179', 'Kai',   '2018-11-03', 'male',   NULL,           NULL,                                                                              'standard', NULL,                                                       false, NULL,           true);

-- ----------------------------------------------------------------------------
-- 5. Memberships. Role lives on the membership; an owner is never a member of
--    their own child. Covers every membership_role and invite_status.
-- ----------------------------------------------------------------------------
INSERT INTO public.memberships (account_id, child_id, role_category, role_label, invited_by, invite_status) VALUES
  -- Zara (Okafor)
  ('0a9e1f52-1b34-4c77-8f21-6d2a5b8c9e10', '019f46db-7029-71b6-9692-5ce5b3940f4a', 'co_parent',   'Dad',              'a058dac5-daf9-484d-9694-e1bd867b1649', 'accepted'),
  ('7faac339-85c1-4f3f-85bd-f690c57838f1', '019f46db-7029-71b6-9692-5ce5b3940f4a', 'therapist',   'Behaviour Therapist','a058dac5-daf9-484d-9694-e1bd867b1649', 'accepted'),
  ('3d6e4f85-4e67-4faa-bc54-9a5d8e1f2b43', '019f46db-7029-71b6-9692-5ce5b3940f4a', 'other',       'Family Friend',    'a058dac5-daf9-484d-9694-e1bd867b1649', 'pending'),
  -- Joya (Sharma)
  ('7faac339-85c1-4f3f-85bd-f690c57838f1', '019f46db-7029-7291-a0a0-9a84c10cdcdb', 'therapist',   'Speech Therapist', '654df0a7-5039-4962-9b63-9aaec7418c72', 'accepted'),
  ('1b8c2d63-2c45-4d88-9a32-7e3b6c9d0f21', '019f46db-7029-7291-a0a0-9a84c10cdcdb', 'caregiver',   'Nanny',            '654df0a7-5039-4962-9b63-9aaec7418c72', 'accepted'),
  -- Aarav (Sharma)
  ('f2ab7307-6c95-4a38-b87f-ca55c19d49eb', '019f46db-7029-72d2-b61d-07a882999c15', 'grandparent', 'Nonna',            '654df0a7-5039-4962-9b63-9aaec7418c72', 'accepted'),
  ('2c7d3e74-3d56-4e99-ab43-8f4c7d0e1a32', '019f46db-7029-72d2-b61d-07a882999c15', 'teacher',     'Class Teacher',    '654df0a7-5039-4962-9b63-9aaec7418c72', 'accepted'),
  ('7faac339-85c1-4f3f-85bd-f690c57838f1', '019f46db-7029-72d2-b61d-07a882999c15', 'therapist',   'Speech Therapist', '654df0a7-5039-4962-9b63-9aaec7418c72', 'pending'),
  -- Nina also a relative link to Joya (declined)
  ('f2ab7307-6c95-4a38-b87f-ca55c19d49eb', '019f46db-7029-7291-a0a0-9a84c10cdcdb', 'relative',    'Great Aunt',       '654df0a7-5039-4962-9b63-9aaec7418c72', 'declined');

-- ----------------------------------------------------------------------------
-- 6. Emergency contacts (external, non-app people who receive SOS SMS).
-- ----------------------------------------------------------------------------
INSERT INTO public.emergency_contacts (child_id, added_by, name, phone) VALUES
  ('019f46db-7029-71b6-9692-5ce5b3940f4a', 'a058dac5-daf9-484d-9694-e1bd867b1649', 'Dr. Amara Okonkwo (Pediatrician)', '+1-415-555-0182'),
  ('019f46db-7029-71b6-9692-5ce5b3940f4a', 'a058dac5-daf9-484d-9694-e1bd867b1649', 'Uncle Femi',                       '+1-415-555-0147'),
  ('019f46db-7029-7291-a0a0-9a84c10cdcdb', '654df0a7-5039-4962-9b63-9aaec7418c72', 'Dr. Ruth Feldman',                 '+1-408-555-0110'),
  ('019f46db-7029-7291-a0a0-9a84c10cdcdb', '654df0a7-5039-4962-9b63-9aaec7418c72', 'Sunrise Learning Center',          '+1-408-555-0199'),
  ('019f46db-7029-72d2-b61d-07a882999c15', '654df0a7-5039-4962-9b63-9aaec7418c72', 'Nonna Nina',                       '+1-408-555-0141');

-- ----------------------------------------------------------------------------
-- 7. Task categories. System defaults (child_id NULL, is_system true) are shared;
--    the custom one is scoped to a child.
-- ----------------------------------------------------------------------------
INSERT INTO public.task_categories (id, child_id, created_by, name, color_hex, is_system) VALUES
  ('11111111-0000-0000-0000-000000000001', NULL, NULL, 'Academic', '#4CAF50', true),
  ('11111111-0000-0000-0000-000000000002', NULL, NULL, 'Sports',   '#2196F3', true),
  ('11111111-0000-0000-0000-000000000003', NULL, NULL, 'Medicine', '#F44336', true),
  ('11111111-0000-0000-0000-000000000004', NULL, NULL, 'Chores',   '#A6D8F4', true),
  ('11111111-0000-0000-0000-000000000005', NULL, NULL, 'Health',   '#A6F4C1', true),
  -- Custom, Joya-scoped, created by Priya.
  ('22222222-0000-0000-0000-000000000001', '019f46db-7029-7291-a0a0-9a84c10cdcdb', '654df0a7-5039-4962-9b63-9aaec7418c72', 'Speech Practice', '#9C27B0', false);

-- ----------------------------------------------------------------------------
-- 8. Tasks. Covers every status / priority / verification_type combination.
-- ----------------------------------------------------------------------------
INSERT INTO public.tasks
    (id, child_id, created_by, category_id, name, description, due_at, priority,
     status, verification_type, photo_proof_path, approved_by, approved_at, points_awarded)
VALUES
  -- Zara: completed via adult approval, awarded points.
  ('019f5a00-0000-7000-8000-000000000001', '019f46db-7029-71b6-9692-5ce5b3940f4a', 'a058dac5-daf9-484d-9694-e1bd867b1649', '11111111-0000-0000-0000-000000000003',
   'Take morning ADHD medication', 'One tablet with breakfast before school.', now() - interval '5 hours', 'high',
   'completed', 'adult_approval', NULL, 'a058dac5-daf9-484d-9694-e1bd867b1649', now() - interval '4 hours', 5),
  -- Zara: awaiting photo verification.
  ('019f5a00-0000-7000-8000-000000000002', '019f46db-7029-71b6-9692-5ce5b3940f4a', '0a9e1f52-1b34-4c77-8f21-6d2a5b8c9e10', '11111111-0000-0000-0000-000000000001',
   'Finish multiplication worksheet', 'Pages 4 and 5. Upload a photo when done.', now() + interval '1 day', 'medium',
   'awaiting_verification', 'photo_proof', 'child-photos/019f46db-7029-71b6-9692-5ce5b3940f4a/worksheet-p5.jpg', NULL, NULL, NULL),
  -- Zara: plain pending.
  ('019f5a00-0000-7000-8000-000000000003', '019f46db-7029-71b6-9692-5ce5b3940f4a', 'a058dac5-daf9-484d-9694-e1bd867b1649', '11111111-0000-0000-0000-000000000002',
   'Soccer practice at the park', 'Saturday morning session with the team.', now() + interval '2 days', 'low',
   'pending', 'none', NULL, NULL, NULL, NULL),
  -- Joya: in progress, custom category.
  ('019f5a00-0000-7000-8000-000000000004', '019f46db-7029-7291-a0a0-9a84c10cdcdb', '7faac339-85c1-4f3f-85bd-f690c57838f1', '22222222-0000-0000-0000-000000000001',
   'Practice /s/ sounds with flashcards', 'Ten minutes using the picture cards from therapy.', now() + interval '3 hours', 'medium',
   'in_progress', 'none', NULL, NULL, NULL, NULL),
  -- Joya: completed, no verification, points awarded.
  ('019f5a00-0000-7000-8000-000000000005', '019f46db-7029-7291-a0a0-9a84c10cdcdb', '654df0a7-5039-4962-9b63-9aaec7418c72', '11111111-0000-0000-0000-000000000004',
   'Brush teeth before bed', 'Part of the bedtime routine.', now() - interval '1 day', 'low',
   'completed', 'none', NULL, NULL, NULL, 2),
  -- Aarav: overdue.
  ('019f5a00-0000-7000-8000-000000000006', '019f46db-7029-72d2-b61d-07a882999c15', '654df0a7-5039-4962-9b63-9aaec7418c72', '11111111-0000-0000-0000-000000000001',
   'Read a bedtime story together', 'Practice new vocabulary while reading.', now() - interval '2 days', 'low',
   'overdue', 'none', NULL, NULL, NULL, NULL),
  -- Aarav: pending, created by grandparent.
  ('019f5a00-0000-7000-8000-000000000007', '019f46db-7029-72d2-b61d-07a882999c15', 'f2ab7307-6c95-4a38-b87f-ca55c19d49eb', '11111111-0000-0000-0000-000000000005',
   'Occupational therapy stretches', 'Morning stretch routine from the OT handout.', now() + interval '1 day', 'medium',
   'pending', 'none', NULL, NULL, NULL, NULL);

-- ----------------------------------------------------------------------------
-- 9. Check-in prompts. Inserting these fires the enqueue trigger, which creates
--    a child-device notification and stamps sent_at automatically.
-- ----------------------------------------------------------------------------
INSERT INTO public.check_in_prompts (id, child_id, initiated_by, question_text) VALUES
  ('019f5b00-0000-7000-8000-000000000001', '019f46db-7029-7291-a0a0-9a84c10cdcdb', '654df0a7-5039-4962-9b63-9aaec7418c72', 'How was school today, love?'),
  ('019f5b00-0000-7000-8000-000000000002', '019f46db-7029-71b6-9692-5ce5b3940f4a', 'a058dac5-daf9-484d-9694-e1bd867b1649', 'Did you take your morning medicine?');

-- ----------------------------------------------------------------------------
-- 10. Check-ins. Adult check-ins, an adult self check-in, and children's own
--     replies in Child Mode (one answering a prompt, one unprompted).
-- ----------------------------------------------------------------------------
INSERT INTO public.check_ins
    (id, child_id, author_id, prompt_id, is_from_child, mood, text_response, shared_with_family)
VALUES
  -- Joya's reply to Priya's prompt.
  ('019f5c00-0000-7000-8000-000000000001', '019f46db-7029-7291-a0a0-9a84c10cdcdb', NULL, '019f5b00-0000-7000-8000-000000000001', true,  'happy',       'I liked art class the best.', true),
  -- Therapist check-in about Joya.
  ('019f5c00-0000-7000-8000-000000000002', '019f46db-7029-7291-a0a0-9a84c10cdcdb', '7faac339-85c1-4f3f-85bd-f690c57838f1', NULL, false, 'overwhelmed', 'Tough afternoon session, needed several breaks.', true),
  -- Parent check-in about Aarav.
  ('019f5c00-0000-7000-8000-000000000003', '019f46db-7029-72d2-b61d-07a882999c15', '654df0a7-5039-4962-9b63-9aaec7418c72', NULL, false, 'sad',         'Good bedtime routine tonight.', true),
  -- Adult self check-in (Sam's own mood, no child).
  ('019f5c00-0000-7000-8000-000000000004', NULL, 'a058dac5-daf9-484d-9694-e1bd867b1649', NULL, false, 'sad',         'Feeling steady today.', true),
  -- Zara's own unprompted Child-Mode check-in (private).
  ('019f5c00-0000-7000-8000-000000000005', '019f46db-7029-71b6-9692-5ce5b3940f4a', NULL, NULL, true,  'angry',       NULL, false),
  -- Co-parent check-in about Zara.
  ('019f5c00-0000-7000-8000-000000000006', '019f46db-7029-71b6-9692-5ce5b3940f4a', '0a9e1f52-1b34-4c77-8f21-6d2a5b8c9e10', NULL, false, 'happy',       'Zara finished her homework without a fuss!', true);

-- ----------------------------------------------------------------------------
-- 11. Push tokens. device_id ties a token to a physical device; the Child-Mode
--     device tokens match children.child_mode_device_id.
-- ----------------------------------------------------------------------------
INSERT INTO public.push_tokens (user_id, device_id, token, platform) VALUES
  ('a058dac5-daf9-484d-9694-e1bd867b1649', 'iphone-sam-14', 'fcm_sam_iphone_8f2ad4c1b9e7', 'ios'),
  ('a058dac5-daf9-484d-9694-e1bd867b1649', 'ipad-zara-01',  'fcm_zara_ipad_3b7c9e2f1a08',  'ios'),
  ('654df0a7-5039-4962-9b63-9aaec7418c72', 'pixel-priya-8', 'fcm_priya_pixel_a41f8d6c2b90','android'),
  ('654df0a7-5039-4962-9b63-9aaec7418c72', 'tab-joya-01',   'fcm_joya_tab_7d2e5b9c3f14',   'android'),
  ('7faac339-85c1-4f3f-85bd-f690c57838f1', NULL,            'webpush_rohan_c9a1f4e8b207',  'web');

-- ----------------------------------------------------------------------------
-- 12. Notifications (adult inbox). Child-device prompt notifications were already
--     created by the check-in-prompt trigger above; these are adult-targeted.
-- ----------------------------------------------------------------------------
INSERT INTO public.notifications
    (recipient_user_id, entity_type, entity_id, title, body, status, priority, sent_at, read_at)
VALUES
  ('a058dac5-daf9-484d-9694-e1bd867b1649', 'task',     '019f5a00-0000-7000-8000-000000000001', 'Task approved',     'You approved Zara''s morning medication.',   'sent', 'normal', now() - interval '4 hours', now() - interval '3 hours'),
  ('654df0a7-5039-4962-9b63-9aaec7418c72', 'check_in', '019f5c00-0000-7000-8000-000000000002', 'New check-in',      'Rohan shared a check-in about Joya.',        'sent', 'normal', now() - interval '2 hours', NULL),
  ('654df0a7-5039-4962-9b63-9aaec7418c72', 'task',     '019f5a00-0000-7000-8000-000000000006', 'Task overdue',      'Aarav''s bedtime reading is overdue.',       'sent', 'high',   now() - interval '1 hours', NULL),
  ('7faac339-85c1-4f3f-85bd-f690c57838f1', NULL,       NULL,                                   'Welcome to Famtastic','Your therapist account is ready to use.',  'sent', 'normal', now() - interval '3 days',  now() - interval '3 days'),
  ('0a9e1f52-1b34-4c77-8f21-6d2a5b8c9e10', 'check_in', '019f5c00-0000-7000-8000-000000000005', 'Zara checked in',   'Zara logged a check-in on her device.',      'failed','normal', NULL, NULL);

-- ----------------------------------------------------------------------------
-- 13. Child Mode PINs. One per family (bcrypt-hashed, same as auth passwords).
--     Okafor = 482156, Sharma = 159073. The suspended Chen family gets none.
-- ----------------------------------------------------------------------------
INSERT INTO public.child_mode_credentials (family_id, pin_hash, last_changed_at) VALUES
  ('019f46db-7029-718f-a58b-c5019ba44117', extensions.crypt('482156', extensions.gen_salt('bf', 10)), now()),
  ('019f46db-7028-71e3-856c-6d9ac24486f9', extensions.crypt('159073', extensions.gen_salt('bf', 10)), now());

COMMIT;
