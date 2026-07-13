-- ============================================================================
-- ENUMS
-- ============================================================================

DROP TYPE IF EXISTS user_role CASCADE;
CREATE TYPE user_role AS ENUM ('user', 'admin');

DROP TYPE IF EXISTS location_visibility CASCADE;
CREATE TYPE location_visibility AS ENUM ('all_family', 'only_parents', 'nobody');

-- ============================================================================
-- TABLES
-- ============================================================================

-- ----------------------------------------------------------------------------
-- profiles
-- Extends auth.users. One row per authenticated user.
-- Created automatically via trigger when a new auth.users row is inserted.
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.profiles (
    id                          UUID                    PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
    email                       TEXT                    NOT NULL,
    full_name                   TEXT,
    avatar_url                  TEXT,
    phone                       TEXT,
    role                        user_role               NOT NULL DEFAULT 'user',
    location_visibility         location_visibility     NOT NULL DEFAULT 'all_family',
    location_tracking_start     TIME,
    location_tracking_end       TIME,
    created_at                  TIMESTAMPTZ             NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at                  TIMESTAMPTZ             NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ----------------------------------------------------------------------------
-- INDEXES / CONSTRAINTS
-- ----------------------------------------------------------------------------

CREATE UNIQUE INDEX IF NOT EXISTS uk_profiles_email ON public.profiles (email);

-- ----------------------------------------------------------------------------
-- TRIGGERS
-- ----------------------------------------------------------------------------

-- Auto-create a profile row whenever Supabase Auth creates a new user.
-- Handles email/password, Google, and Apple sign-in.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_provider   TEXT;
    v_full_name  TEXT;
    v_avatar_url TEXT;
BEGIN
    -- Identify the auth provider (google | apple | email | ...)
    v_provider := NEW.raw_app_meta_data ->> 'provider';

    IF v_provider = 'google' THEN
        -- Google provides both name variants and two avatar fields.
        v_full_name  := COALESCE(
            NEW.raw_user_meta_data ->> 'full_name',
            NEW.raw_user_meta_data ->> 'name'
        );
        v_avatar_url := COALESCE(
            NEW.raw_user_meta_data ->> 'avatar_url',
            NEW.raw_user_meta_data ->> 'picture'
        );

    ELSIF v_provider = 'apple' THEN
        -- Apple sends full_name as a JSON object on first sign-in only:
        -- { "firstName": "John", "familyName": "Doe" }
        -- Subsequent logins omit it entirely. No avatar is provided by Apple.
        IF jsonb_typeof(NEW.raw_user_meta_data -> 'full_name') = 'object' THEN
            v_full_name := NULLIF(TRIM(
                COALESCE(NEW.raw_user_meta_data -> 'full_name' ->> 'firstName', '') || ' ' ||
                COALESCE(NEW.raw_user_meta_data -> 'full_name' ->> 'familyName', '')
            ), '');
        ELSE
            v_full_name := COALESCE(
                NEW.raw_user_meta_data ->> 'full_name',
                NEW.raw_user_meta_data ->> 'name'
            );
        END IF;
        v_avatar_url := NULL;

    ELSE
        -- Email/password (and any future provider): use standard metadata fields.
        v_full_name  := COALESCE(
            NEW.raw_user_meta_data ->> 'full_name',
            NEW.raw_user_meta_data ->> 'name'
        );
        v_avatar_url := NEW.raw_user_meta_data ->> 'avatar_url';
    END IF;

    -- Normalise empty strings to NULL so the column is either a real value or absent.
    IF v_full_name = '' THEN v_full_name := NULL; END IF;

    INSERT INTO public.profiles (id, email, full_name, avatar_url)
    VALUES (
        NEW.id,
        NEW.email,
        v_full_name,
        v_avatar_url
    )
    ON CONFLICT (id) DO NOTHING;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_profiles_on_auth_user_created ON auth.users;
CREATE TRIGGER trigger_profiles_on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_user();

-- Keep profiles.email in sync when a user changes their email in Supabase Auth.
-- Email is the single identity key used to resolve accounts during invitations,
-- so a stale profile email would let the same person be invited as a duplicate
-- account. The unique index on profiles.email also makes this reject a change to
-- an address already claimed by another account (fail-closed, which is correct).
CREATE OR REPLACE FUNCTION public.handle_user_email_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- updated_at is stamped by the set_updated_at() BEFORE UPDATE trigger below.
    UPDATE public.profiles
    SET email = NEW.email
    WHERE id = NEW.id;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_profiles_on_auth_user_email_changed ON auth.users;
CREATE TRIGGER trigger_profiles_on_auth_user_email_changed
    AFTER UPDATE OF email ON auth.users
    FOR EACH ROW
    WHEN (NEW.email IS DISTINCT FROM OLD.email)
    EXECUTE FUNCTION public.handle_user_email_change();

-- Keep updated_at current on every profile change.
DROP TRIGGER IF EXISTS trigger_profiles_set_updated_at ON public.profiles;
CREATE TRIGGER trigger_profiles_set_updated_at
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

-- ============================================================================
-- ROW LEVEL SECURITY - HELPER FUNCTIONS
-- ============================================================================

-- ----------------------------------------------------------------------------
-- is_platform_admin()
-- Returns true if the current authenticated user is a platform admin.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.is_platform_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND role = 'admin'
    );
$$;

-- ============================================================================
-- RLS POLICIES
-- ============================================================================

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "profiles_select_policy" ON public.profiles;
CREATE POLICY "profiles_select_policy" ON public.profiles
    FOR SELECT USING (
        id = auth.uid() OR is_platform_admin()
    );

DROP POLICY IF EXISTS "profiles_update_policy" ON public.profiles;
CREATE POLICY "profiles_update_policy" ON public.profiles
    FOR UPDATE USING (id = auth.uid());

-- ============================================================================
-- COMMENTS SECTION
-- ============================================================================

COMMENT ON TABLE  public.profiles                          IS 'Public user profile that extends auth.users. Covers email/password, Google and Apple sign-in.';
COMMENT ON COLUMN public.profiles.id                       IS 'Matches auth.users.id (UUID v7 from Supabase Auth).';
COMMENT ON COLUMN public.profiles.email                    IS 'User email - the single identity key across all families and children.';
COMMENT ON COLUMN public.profiles.full_name                IS 'Display name, populated from OAuth metadata or set manually.';
COMMENT ON COLUMN public.profiles.avatar_url               IS 'Profile photo URL (Supabase Storage or OAuth provider).';
COMMENT ON COLUMN public.profiles.phone                    IS 'Optional phone number for the account holder.';
COMMENT ON TYPE  user_role                                 IS 'Platform-level account role. user = regular app user; admin = web-portal super-admin.';
COMMENT ON COLUMN public.profiles.role                     IS 'Platform-level role. Defaults to user; set to admin for web-portal super-admins by the platform team.';
COMMENT ON TYPE  location_visibility                       IS 'Controls who can see this member on the live map.';
COMMENT ON COLUMN public.profiles.location_visibility      IS 'Privacy setting for the live map.';
COMMENT ON COLUMN public.profiles.location_tracking_start  IS 'Optional start time for location tracking (e.g. school hours). NULL = 24/7.';
COMMENT ON COLUMN public.profiles.location_tracking_end    IS 'Optional end time for location tracking. NULL = 24/7.';
COMMENT ON COLUMN public.profiles.created_at               IS 'Row creation timestamp.';
COMMENT ON COLUMN public.profiles.updated_at               IS 'Last-modified timestamp, stamped by the set_updated_at() trigger on every update.';
COMMENT ON FUNCTION public.handle_new_user()               IS 'Trigger function - mirrors a new auth.users row into public.profiles automatically.';
COMMENT ON FUNCTION public.handle_user_email_change()      IS 'Trigger function - syncs profiles.email when auth.users.email changes, so email stays the stable account identity for invitations.';
COMMENT ON FUNCTION public.is_platform_admin()              IS 'Returns true if the calling user has role = admin in their profile.';
