-- ============================================================================
-- ENUMS (if any)
-- ============================================================================

DROP TYPE IF EXISTS role_global_type CASCADE;
CREATE TYPE role_global_type AS ENUM ('user','platform_admin');

DROP TYPE IF EXISTS family_role CASCADE;
CREATE TYPE family_role AS ENUM ('family_admin','family_member','child');

DROP TYPE IF EXISTS member_status CASCADE;
CREATE TYPE member_status AS ENUM ('active','invited','removed');

DROP TYPE IF EXISTS language_level CASCADE;
CREATE TYPE language_level AS ENUM ('simple','standard','full');

DROP TYPE IF EXISTS provider_type CASCADE;
CREATE TYPE provider_type AS ENUM ('doctor','therapist','teacher','other');

DROP TYPE IF EXISTS provider_status CASCADE;
CREATE TYPE provider_status AS ENUM ('invited','active','removed');

-- ============================================================================
-- TABLES
-- ============================================================================

CREATE TABLE IF NOT EXISTS profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  avatar_url text,
  role_global role_global_type not null default 'user',
  created_at timestamptz not null default CURRENT_TIMESTAMP,
  updated_at timestamptz not null default CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS families (
  id uuid primary key default public.uuid_generate_v7(),
  name text not null,
  created_by uuid references profiles(id),
  language_default text default 'en',
  created_at timestamptz not null default CURRENT_TIMESTAMP,
  updated_at timestamptz not null default CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS family_members (
  id uuid primary key default public.uuid_generate_v7(),
  family_id uuid not null references families(id) on delete cascade,
  profile_id uuid references profiles(id) on delete set null,
  role family_role not null,
  status member_status not null default 'active',
  status_label text,
  joined_at timestamptz not null default CURRENT_TIMESTAMP,
  created_at timestamptz not null default CURRENT_TIMESTAMP,
  updated_at timestamptz not null default CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS child_profiles (
  member_id uuid primary key references family_members(id) on delete cascade,
  condition_tags text[],
  language_level language_level not null default 'standard',
  photo_url text,
  dob date,
  created_at timestamptz not null default CURRENT_TIMESTAMP,
  updated_at timestamptz not null default CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS family_invites (
  id uuid primary key default public.uuid_generate_v7(),
  family_id uuid not null references families(id) on delete cascade,
  code text not null unique,
  contact text,
  role family_role not null,
  expires_at timestamptz not null,
  used_at timestamptz,
  created_at timestamptz not null default CURRENT_TIMESTAMP,
  updated_at timestamptz not null default CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS child_providers (
  id uuid primary key default public.uuid_generate_v7(),
  child_member_id uuid not null references family_members(id) on delete cascade,
  provider_profile_id uuid references profiles(id) on delete set null,
  provider_type provider_type not null,
  invited_by uuid references profiles(id),
  status provider_status not null default 'invited',
  access_scope text[] not null default '{check_ins,speech,tasks,routines}',
  created_at timestamptz not null default CURRENT_TIMESTAMP,
  updated_at timestamptz not null default CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS child_provider_invites (
  id uuid primary key default public.uuid_generate_v7(),
  child_member_id uuid not null references family_members(id) on delete cascade,
  contact text not null,
  provider_type provider_type not null,
  code text not null unique,
  expires_at timestamptz not null,
  used_at timestamptz,
  invited_by uuid references profiles(id),
  created_at timestamptz not null default CURRENT_TIMESTAMP,
  updated_at timestamptz not null default CURRENT_TIMESTAMP
);

-- ============================================================================
-- INDEXES / CONSTRAINTS
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_family_members_family ON family_members (family_id);
CREATE INDEX IF NOT EXISTS idx_family_members_profile ON family_members (profile_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_family_members_family_profile ON family_members (family_id, profile_id)
  WHERE profile_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_family_invites_family ON family_invites (family_id);

CREATE INDEX IF NOT EXISTS idx_child_providers_child ON child_providers (child_member_id);
CREATE INDEX IF NOT EXISTS idx_child_providers_provider ON child_providers (provider_profile_id);

CREATE INDEX IF NOT EXISTS idx_child_provider_invites_child ON child_provider_invites (child_member_id);

-- ============================================================================
-- TRIGGERS & FUNCTIONS
-- ============================================================================

-- handle_new_user
-- Fires after every INSERT on auth.users and auto-creates a profiles row.
--
-- Provider metadata layout:
--   Google      → raw_user_meta_data: { full_name, avatar_url, picture, email }
--   Apple       → raw_user_meta_data: { name, email }  (name only on first sign-in)
--   Email/pass  → raw_user_meta_data: { full_name }    (if passed via options.data)
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_full_name  text;
  v_avatar_url text;
BEGIN
  -- Resolve display name: Google uses 'full_name', Apple uses 'name'
  v_full_name := COALESCE(
    new.raw_user_meta_data->>'full_name',
    new.raw_user_meta_data->>'name',
    split_part(new.email, '@', 1)   -- fallback: email prefix
  );

  -- Resolve avatar: Google provides 'avatar_url' or 'picture'; Apple provides none
  v_avatar_url := COALESCE(
    new.raw_user_meta_data->>'avatar_url',
    new.raw_user_meta_data->>'picture'
  );

  INSERT INTO public.profiles (id, full_name, avatar_url)
  VALUES (new.id, v_full_name, v_avatar_url)
  ON CONFLICT (id) DO UPDATE
    SET
      full_name  = EXCLUDED.full_name,
      avatar_url = COALESCE(EXCLUDED.avatar_url, public.profiles.avatar_url),
      updated_at = CURRENT_TIMESTAMP
    WHERE EXCLUDED.full_name IS NOT NULL;

  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- set_updated_at
-- Generic BEFORE UPDATE trigger that stamps updated_at = now().
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS trigger LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  NEW.updated_at := CURRENT_TIMESTAMP;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_profiles_updated_at ON public.profiles;
CREATE TRIGGER trg_profiles_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================================
-- COMMENTS SECTION
-- ============================================================================

COMMENT ON TABLE profiles IS 'User profiles mirroring auth.users.';
COMMENT ON COLUMN profiles.id IS 'References auth.users.id.';
COMMENT ON COLUMN profiles.full_name IS 'User full name.';
COMMENT ON COLUMN profiles.avatar_url IS 'Avatar URL.';
COMMENT ON COLUMN profiles.role_global IS 'Global user role.';
COMMENT ON COLUMN profiles.created_at IS 'Record creation timestamp.';
COMMENT ON COLUMN profiles.updated_at IS 'Last update timestamp.';

COMMENT ON TABLE families IS 'Groups users into a family unit.';
COMMENT ON COLUMN families.id IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN families.name IS 'Family name.';
COMMENT ON COLUMN families.created_by IS 'Creator profile ID.';
COMMENT ON COLUMN families.language_default IS 'Default language for the family.';
COMMENT ON COLUMN families.created_at IS 'Record creation timestamp.';
COMMENT ON COLUMN families.updated_at IS 'Last update timestamp.';

COMMENT ON TABLE family_members IS 'Links profiles to families with roles.';
COMMENT ON COLUMN family_members.id IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN family_members.family_id IS 'Family ID.';
COMMENT ON COLUMN family_members.profile_id IS 'Profile ID.';
COMMENT ON COLUMN family_members.role IS 'Role within the family.';
COMMENT ON COLUMN family_members.status IS 'Membership status.';
COMMENT ON COLUMN family_members.status_label IS 'Custom label for status.';
COMMENT ON COLUMN family_members.joined_at IS 'Timestamp of joining.';
COMMENT ON COLUMN family_members.created_at IS 'Record creation timestamp.';
COMMENT ON COLUMN family_members.updated_at IS 'Last update timestamp.';

COMMENT ON TABLE child_profiles IS 'Extensions for child members.';
COMMENT ON COLUMN child_profiles.member_id IS 'References family_members.id.';
COMMENT ON COLUMN child_profiles.condition_tags IS 'Tags for child conditions.';
COMMENT ON COLUMN child_profiles.language_level IS 'Language level settings.';
COMMENT ON COLUMN child_profiles.photo_url IS 'Photo URL.';
COMMENT ON COLUMN child_profiles.dob IS 'Date of birth.';
COMMENT ON COLUMN child_profiles.created_at IS 'Record creation timestamp.';
COMMENT ON COLUMN child_profiles.updated_at IS 'Last update timestamp.';

COMMENT ON TABLE family_invites IS 'Invitations to join a family.';
COMMENT ON COLUMN family_invites.id IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN family_invites.family_id IS 'Family ID.';
COMMENT ON COLUMN family_invites.code IS 'Invite code.';
COMMENT ON COLUMN family_invites.contact IS 'Contact info.';
COMMENT ON COLUMN family_invites.role IS 'Role offered.';
COMMENT ON COLUMN family_invites.expires_at IS 'Expiration timestamp.';
COMMENT ON COLUMN family_invites.used_at IS 'Usage timestamp.';
COMMENT ON COLUMN family_invites.created_at IS 'Record creation timestamp.';
COMMENT ON COLUMN family_invites.updated_at IS 'Last update timestamp.';

COMMENT ON TABLE child_providers IS 'External providers linked to children.';
COMMENT ON COLUMN child_providers.id IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN child_providers.child_member_id IS 'Child member ID.';
COMMENT ON COLUMN child_providers.provider_profile_id IS 'Provider profile ID.';
COMMENT ON COLUMN child_providers.provider_type IS 'Type of provider.';
COMMENT ON COLUMN child_providers.invited_by IS 'Inviter profile ID.';
COMMENT ON COLUMN child_providers.status IS 'Provider status.';
COMMENT ON COLUMN child_providers.access_scope IS 'Scope of access.';
COMMENT ON COLUMN child_providers.created_at IS 'Record creation timestamp.';
COMMENT ON COLUMN child_providers.updated_at IS 'Last update timestamp.';

COMMENT ON TABLE child_provider_invites IS 'Invitations for child providers.';
COMMENT ON COLUMN child_provider_invites.id IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN child_provider_invites.child_member_id IS 'Child member ID.';
COMMENT ON COLUMN child_provider_invites.contact IS 'Contact info.';
COMMENT ON COLUMN child_provider_invites.provider_type IS 'Type of provider.';
COMMENT ON COLUMN child_provider_invites.code IS 'Invite code.';
COMMENT ON COLUMN child_provider_invites.expires_at IS 'Expiration timestamp.';
COMMENT ON COLUMN child_provider_invites.used_at IS 'Usage timestamp.';
COMMENT ON COLUMN child_provider_invites.invited_by IS 'Inviter profile ID.';
COMMENT ON COLUMN child_provider_invites.created_at IS 'Record creation timestamp.';
COMMENT ON COLUMN child_provider_invites.updated_at IS 'Last update timestamp.';

COMMENT ON FUNCTION handle_new_user IS
  'Auto-creates a profiles row on new auth.users insert. Handles Google OAuth '
  '(full_name, avatar_url/picture), Apple Sign-In (name), and email/password '
  '(full_name from signup options.data). Falls back to email prefix if no name.';

COMMENT ON FUNCTION set_updated_at IS
  'Generic BEFORE UPDATE trigger that stamps updated_at = CURRENT_TIMESTAMP. '
  'Bound to profiles; bind to any other table that needs auto-updated_at.';
