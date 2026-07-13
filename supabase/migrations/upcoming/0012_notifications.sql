-- ============================================================================
-- ENUMS
-- ============================================================================

DROP TYPE IF EXISTS push_platform CASCADE;
CREATE TYPE push_platform AS ENUM ('ios', 'android', 'web');

-- ============================================================================
-- TABLES
-- ============================================================================

-- ----------------------------------------------------------------------------
-- push_tokens
-- Device push notification tokens. One user can have multiple tokens
-- (multiple devices). Unique per user+token pair.
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.push_tokens (
    id          UUID                PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id     UUID                NOT NULL,
    token       TEXT                NOT NULL,
    platform    push_platform       NOT NULL,
    created_at  TIMESTAMPTZ         NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- INDEXES / CONSTRAINTS
-- ============================================================================

-- A device token should be registered once per user.
CREATE UNIQUE INDEX IF NOT EXISTS uk_push_tokens_user_token
    ON public.push_tokens (user_id, token);

ALTER TABLE public.push_tokens DROP CONSTRAINT IF EXISTS fk_push_tokens_user;
ALTER TABLE public.push_tokens ADD CONSTRAINT fk_push_tokens_user
    FOREIGN KEY (user_id) REFERENCES public.profiles (id) ON DELETE CASCADE;

-- Lookup all tokens for a user when sending a notification.
CREATE INDEX IF NOT EXISTS idx_push_tokens_user_id
    ON public.push_tokens (user_id);

-- ============================================================================
-- RLS POLICIES
-- ============================================================================

ALTER TABLE public.push_tokens ENABLE ROW LEVEL SECURITY;

-- POLICIES - push_tokens

DROP POLICY IF EXISTS "push_tokens_select_policy" ON public.push_tokens;
CREATE POLICY "push_tokens_select_policy" ON public.push_tokens
    FOR SELECT USING (user_id = auth.uid() OR is_platform_admin());

DROP POLICY IF EXISTS "push_tokens_insert_policy" ON public.push_tokens;
CREATE POLICY "push_tokens_insert_policy" ON public.push_tokens
    FOR INSERT WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "push_tokens_delete_policy" ON public.push_tokens;
CREATE POLICY "push_tokens_delete_policy" ON public.push_tokens
    FOR DELETE USING (user_id = auth.uid());

-- ============================================================================
-- COMMENTS SECTION
-- ============================================================================

COMMENT ON TYPE  push_platform                                     IS 'Mobile OS platform for a push notification token.';

COMMENT ON TABLE  public.push_tokens                                    IS 'Device push notification tokens. One user can register tokens from multiple devices.';
COMMENT ON COLUMN public.push_tokens.id                                 IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN public.push_tokens.user_id                            IS 'The profile this token belongs to.';
COMMENT ON COLUMN public.push_tokens.token                              IS 'FCM (Android) or APNs (iOS) device token.';
COMMENT ON COLUMN public.push_tokens.platform                           IS 'ios, android, or web.';
COMMENT ON COLUMN public.push_tokens.created_at                         IS 'Row creation timestamp.';
