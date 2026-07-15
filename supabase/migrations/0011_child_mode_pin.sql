-- ============================================================================
-- TABLES
-- ============================================================================

-- ----------------------------------------------------------------------------
-- child_mode_credentials
-- One row per family: the single Child Mode PIN shared across all of that
-- family's children, plus brute-force lockout counters and the forgot-PIN
-- reset-token state (folded in here since there is exactly one active reset per
-- family). The PIN is bcrypt-hashed; the reset token is stored only as a SHA-256
-- hash. RLS denies ALL direct client access - every read/write goes through the
-- SECURITY DEFINER functions below, so neither hash ever leaves the database.
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.child_mode_credentials (
    id                      UUID          PRIMARY KEY DEFAULT uuid_generate_v7(),
    family_id               UUID          NOT NULL,
    pin_hash                TEXT          NOT NULL,
    failed_attempts         INT           NOT NULL DEFAULT 0,
    locked_until            TIMESTAMPTZ,
    last_changed_at         TIMESTAMPTZ,
    reset_token_hash        TEXT,
    reset_token_expires_at  TIMESTAMPTZ,
    reset_requested_at      TIMESTAMPTZ,
    created_at              TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at              TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- INDEXES / CONSTRAINTS
-- ============================================================================

-- Exactly one PIN per family.
CREATE UNIQUE INDEX IF NOT EXISTS uk_child_mode_credentials_family
    ON public.child_mode_credentials (family_id);

ALTER TABLE public.child_mode_credentials DROP CONSTRAINT IF EXISTS fk_child_mode_credentials_family;
ALTER TABLE public.child_mode_credentials ADD CONSTRAINT fk_child_mode_credentials_family
    FOREIGN KEY (family_id) REFERENCES public.families (id) ON DELETE CASCADE;

-- ============================================================================
-- FUNCTIONS / TRIGGERS
-- ============================================================================

-- Keep updated_at current on every change.
DROP TRIGGER IF EXISTS trigger_child_mode_credentials_set_updated_at ON public.child_mode_credentials;
CREATE TRIGGER trigger_child_mode_credentials_set_updated_at
    BEFORE UPDATE ON public.child_mode_credentials
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

-- ----------------------------------------------------------------------------
-- _child_mode_family_id()
-- Single choke point for "is the caller a parent with an active family". Returns
-- the id of the active family owned by the current user; raises no_family
-- otherwise. Internal - REVOKEd from client roles (only the SECURITY DEFINER
-- RPCs below call it, as the function owner).
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public._child_mode_family_id()
RETURNS UUID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_family_id UUID;
BEGIN
    SELECT id INTO v_family_id
    FROM public.families
    WHERE owner_id = auth.uid() AND status = 'active';

    IF v_family_id IS NULL THEN
        RAISE EXCEPTION 'No active family found for the current user.'
            USING HINT = 'no_family', ERRCODE = 'check_violation';
    END IF;
    RETURN v_family_id;
END;
$$;

-- ----------------------------------------------------------------------------
-- _validate_child_mode_pin_format(p_pin)
-- Enforces the 6-digit numeric rule and rejects an all-same-digit PIN. Raises
-- pin_invalid on failure. Internal - REVOKEd from client roles.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public._validate_child_mode_pin_format(p_pin TEXT)
RETURNS VOID
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    IF p_pin IS NULL OR p_pin !~ '^[0-9]{6}$' THEN
        RAISE EXCEPTION 'PIN must be exactly 6 digits.'
            USING HINT = 'pin_invalid', ERRCODE = 'check_violation';
    END IF;
    IF p_pin ~ '^(.)\1*$' THEN
        RAISE EXCEPTION 'PIN cannot be all the same digit.'
            USING HINT = 'pin_invalid', ERRCODE = 'check_violation';
    END IF;
END;
$$;

-- ----------------------------------------------------------------------------
-- _verify_child_mode_pin(p_family_id, p_pin) -> jsonb {result, ...}
-- Verifies a PIN against a family's stored bcrypt hash with brute-force lockout,
-- RETURNING the outcome rather than raising for a wrong/locked PIN. This is
-- deliberate: the whole PostgREST call is one transaction, so raising on a wrong
-- attempt would roll back the failed_attempts increment and defeat the lockout.
-- Returning instead lets the caller finish normally and COMMIT the counter.
--   {"result":"ok"}
--   {"result":"incorrect","attempts_remaining":N}
--   {"result":"locked","locked_until":<ts>}
-- Locks the row FOR UPDATE; every 5th consecutive failure locks with an
-- escalating duration (5->15m, 10->30m, ...); a correct PIN clears the counters.
-- Only the genuine precondition "no PIN set" raises (nothing to persist).
-- Internal and REVOKEd from client roles so a client can never call it with an
-- arbitrary p_family_id to brute-force another family's PIN.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public._verify_child_mode_pin(p_family_id UUID, p_pin TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_hash          TEXT;
    v_failed        INT;
    v_locked_until  TIMESTAMPTZ;
    v_new_lock      TIMESTAMPTZ;
BEGIN
    SELECT pin_hash, failed_attempts, locked_until
      INTO v_hash, v_failed, v_locked_until
    FROM public.child_mode_credentials
    WHERE family_id = p_family_id
    FOR UPDATE;

    IF v_hash IS NULL THEN
        RAISE EXCEPTION 'No Child Mode PIN is set for this family.'
            USING HINT = 'pin_required', ERRCODE = 'check_violation';
    END IF;

    IF v_locked_until IS NOT NULL AND v_locked_until > CURRENT_TIMESTAMP THEN
        RETURN jsonb_build_object('result', 'locked', 'locked_until', v_locked_until);
    END IF;

    IF extensions.crypt(p_pin, v_hash) = v_hash THEN
        -- Correct: clear counters (only if there was anything to clear).
        IF v_failed <> 0 OR v_locked_until IS NOT NULL THEN
            UPDATE public.child_mode_credentials
            SET failed_attempts = 0, locked_until = NULL
            WHERE family_id = p_family_id;
        END IF;
        RETURN jsonb_build_object('result', 'ok');
    END IF;

    -- Wrong PIN: count it, lock every 5th failure with an escalating duration.
    v_failed := v_failed + 1;
    IF v_failed % 5 = 0 THEN
        v_new_lock := CURRENT_TIMESTAMP + ((v_failed / 5) * INTERVAL '15 minutes');
        UPDATE public.child_mode_credentials
        SET failed_attempts = v_failed, locked_until = v_new_lock
        WHERE family_id = p_family_id;
        RETURN jsonb_build_object('result', 'locked', 'locked_until', v_new_lock);
    END IF;

    UPDATE public.child_mode_credentials
    SET failed_attempts = v_failed
    WHERE family_id = p_family_id;

    RETURN jsonb_build_object('result', 'incorrect', 'attempts_remaining', 5 - (v_failed % 5));
END;
$$;

-- ----------------------------------------------------------------------------
-- child_mode_pin_status()
-- Non-mutating status for the app to branch setup-vs-enter and surface lockout.
-- Never returns any secret. Returns {has_pin, is_locked, locked_until,
-- failed_attempts}; has_pin=false (and no lock) when the caller owns no active
-- family, so the settings screen can render without throwing.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.child_mode_pin_status()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_family_id     UUID;
    v_has_pin       BOOLEAN := false;
    v_failed        INT := 0;
    v_locked_until  TIMESTAMPTZ;
BEGIN
    SELECT id INTO v_family_id
    FROM public.families
    WHERE owner_id = auth.uid() AND status = 'active';

    IF v_family_id IS NULL THEN
        RETURN jsonb_build_object(
            'has_pin', false, 'is_locked', false,
            'locked_until', NULL, 'failed_attempts', 0
        );
    END IF;

    SELECT true, failed_attempts, locked_until
      INTO v_has_pin, v_failed, v_locked_until
    FROM public.child_mode_credentials
    WHERE family_id = v_family_id;

    RETURN jsonb_build_object(
        'has_pin', COALESCE(v_has_pin, false),
        'is_locked', v_locked_until IS NOT NULL AND v_locked_until > CURRENT_TIMESTAMP,
        'locked_until', v_locked_until,
        'failed_attempts', COALESCE(v_failed, 0)
    );
END;
$$;

-- ----------------------------------------------------------------------------
-- set_child_mode_pin(p_new_pin, p_current_pin)
-- First-time setup AND change, in one RPC (matches the historical contract).
-- No row yet -> create the PIN (p_current_pin ignored). Row exists -> require and
-- verify p_current_pin (brute-force lockout applies) before re-hashing. The new
-- PIN is immediately valid for every Child Mode operation.
-- (p_new_pin is first so the defaulted p_current_pin can be last; callers use
-- named args, so declaration order is irrelevant to the client.)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.set_child_mode_pin(
    p_new_pin      TEXT,
    p_current_pin  TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_family_id UUID;
    v_exists    BOOLEAN;
    v_verify    JSONB;
BEGIN
    v_family_id := public._child_mode_family_id();
    PERFORM public._validate_child_mode_pin_format(p_new_pin);

    SELECT EXISTS (
        SELECT 1 FROM public.child_mode_credentials WHERE family_id = v_family_id
    ) INTO v_exists;

    IF NOT v_exists THEN
        INSERT INTO public.child_mode_credentials (family_id, pin_hash, last_changed_at)
        VALUES (
            v_family_id,
            extensions.crypt(p_new_pin, extensions.gen_salt('bf', 10)),
            CURRENT_TIMESTAMP
        );
        RETURN jsonb_build_object('result', 'ok');
    END IF;

    IF p_current_pin IS NULL THEN
        RAISE EXCEPTION 'Current PIN is required to change the Child Mode PIN.'
            USING HINT = 'pin_required', ERRCODE = 'check_violation';
    END IF;

    -- On a wrong/locked current PIN, return the status so the failed-attempt
    -- counter COMMITs (it would roll back if we raised instead).
    v_verify := public._verify_child_mode_pin(v_family_id, p_current_pin);
    IF v_verify ->> 'result' <> 'ok' THEN
        RETURN v_verify;
    END IF;

    UPDATE public.child_mode_credentials
    SET pin_hash = extensions.crypt(p_new_pin, extensions.gen_salt('bf', 10)),
        last_changed_at = CURRENT_TIMESTAMP,
        failed_attempts = 0,
        locked_until = NULL
    WHERE family_id = v_family_id;

    RETURN jsonb_build_object('result', 'ok');
END;
$$;

-- ----------------------------------------------------------------------------
-- enter_child_mode(p_child_id, p_device_id)
-- Turns Child Mode ON for one child (not PIN-gated, but a PIN must already
-- exist - the app is expected to run setup first, and the transition trigger
-- enforces it as a backstop). Owner-only via owns_child().
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.enter_child_mode(
    p_child_id   UUID,
    p_device_id  TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_family_id UUID;
BEGIN
    IF NOT public.owns_child(p_child_id) THEN
        RAISE EXCEPTION 'You can only manage Child Mode for your own children.'
            USING HINT = 'not_owner', ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT family_id INTO v_family_id FROM public.children WHERE id = p_child_id;

    IF NOT EXISTS (
        SELECT 1 FROM public.child_mode_credentials WHERE family_id = v_family_id
    ) THEN
        RAISE EXCEPTION 'Set a Child Mode PIN before enabling Child Mode.'
            USING HINT = 'pin_required', ERRCODE = 'check_violation';
    END IF;

    UPDATE public.children
    SET child_mode_enabled = true,
        child_mode_device_id = p_device_id
    WHERE id = p_child_id;

    RETURN p_child_id;
END;
$$;

-- ----------------------------------------------------------------------------
-- exit_child_mode(p_child_id, p_pin)
-- Turns Child Mode OFF for one child, gated by the family PIN (this is the core
-- guard - the child cannot exit without it). Owner-only. Sets a transaction-local
-- context flag that the children transition trigger requires, so a direct client
-- UPDATE can never disable Child Mode outside this verified path.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.exit_child_mode(
    p_child_id  UUID,
    p_pin       TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_family_id UUID;
    v_verify    JSONB;
BEGIN
    IF NOT public.owns_child(p_child_id) THEN
        RAISE EXCEPTION 'You can only manage Child Mode for your own children.'
            USING HINT = 'not_owner', ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT family_id INTO v_family_id FROM public.children WHERE id = p_child_id;

    -- A wrong/locked PIN is returned (not raised) so the lockout counter COMMITs.
    v_verify := public._verify_child_mode_pin(v_family_id, p_pin);
    IF v_verify ->> 'result' <> 'ok' THEN
        RETURN v_verify || jsonb_build_object('child_id', p_child_id);
    END IF;

    -- Authorise the disable transition for just our own UPDATE, then immediately
    -- clear it so the flag can never leak to another statement in the same
    -- transaction (belt-and-braces; PostgREST runs each RPC in its own txn anyway).
    PERFORM set_config('app.child_mode_ctx', 'exit', true);

    UPDATE public.children
    SET child_mode_enabled = false,
        child_mode_device_id = NULL
    WHERE id = p_child_id;

    PERFORM set_config('app.child_mode_ctx', '', true);

    RETURN jsonb_build_object('result', 'ok', 'child_id', p_child_id);
END;
$$;

-- ----------------------------------------------------------------------------
-- create_child_mode_pin_reset()
-- Forgot-PIN step 1: mints a single-use, 30-minute reset token for the caller's
-- family, stores ONLY its SHA-256 hash (overwriting any prior token), and returns
-- the raw token plus the owner's email/name to the edge function for emailing.
-- Requires an existing PIN and throttles to one request per 2 minutes. Runs under
-- the caller's JWT so auth.uid() resolves the family.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.create_child_mode_pin_reset()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_family_id     UUID;
    v_requested_at  TIMESTAMPTZ;
    v_exists        BOOLEAN;
    v_token         TEXT;
    v_email         TEXT;
    v_full_name     TEXT;
BEGIN
    v_family_id := public._child_mode_family_id();

    SELECT true, reset_requested_at
      INTO v_exists, v_requested_at
    FROM public.child_mode_credentials
    WHERE family_id = v_family_id;

    IF NOT COALESCE(v_exists, false) THEN
        RAISE EXCEPTION 'No Child Mode PIN is set, so there is nothing to reset.'
            USING HINT = 'pin_required', ERRCODE = 'check_violation';
    END IF;

    IF v_requested_at IS NOT NULL
       AND v_requested_at > CURRENT_TIMESTAMP - INTERVAL '2 minutes' THEN
        RAISE EXCEPTION 'A reset was just requested. Please wait a couple of minutes.'
            USING HINT = 'rate_limited', ERRCODE = 'check_violation';
    END IF;

    v_token := encode(extensions.gen_random_bytes(32), 'hex');

    UPDATE public.child_mode_credentials
    SET reset_token_hash = encode(extensions.digest(v_token, 'sha256'), 'hex'),
        reset_token_expires_at = CURRENT_TIMESTAMP + INTERVAL '30 minutes',
        reset_requested_at = CURRENT_TIMESTAMP
    WHERE family_id = v_family_id;

    SELECT email, full_name INTO v_email, v_full_name
    FROM public.profiles WHERE id = auth.uid();

    RETURN jsonb_build_object(
        'raw_token', v_token,
        'email', v_email,
        'full_name', v_full_name
    );
END;
$$;

-- ----------------------------------------------------------------------------
-- redeem_child_mode_pin_reset(p_token, p_new_pin)
-- Forgot-PIN step 2: sets a new PIN without the old one. Requires BOTH a valid
-- session (auth.uid() -> family) AND a token whose SHA-256 matches THIS family's
-- stored, unexpired reset_token_hash. On success it sets the new PIN, clears
-- lockout, and nulls the reset columns (single-use). Any failure raises a generic
-- reset_invalid (no enumeration).
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.redeem_child_mode_pin_reset(
    p_token    TEXT,
    p_new_pin  TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_family_id  UUID;
    v_hash       TEXT;
    v_expires    TIMESTAMPTZ;
BEGIN
    v_family_id := public._child_mode_family_id();
    PERFORM public._validate_child_mode_pin_format(p_new_pin);

    SELECT reset_token_hash, reset_token_expires_at
      INTO v_hash, v_expires
    FROM public.child_mode_credentials
    WHERE family_id = v_family_id
    FOR UPDATE;

    IF v_hash IS NULL
       OR v_expires IS NULL
       OR v_expires < CURRENT_TIMESTAMP
       OR v_hash <> encode(extensions.digest(p_token, 'sha256'), 'hex') THEN
        RAISE EXCEPTION 'This reset link is invalid or has expired.'
            USING HINT = 'reset_invalid', ERRCODE = 'check_violation';
    END IF;

    UPDATE public.child_mode_credentials
    SET pin_hash = extensions.crypt(p_new_pin, extensions.gen_salt('bf', 10)),
        last_changed_at = CURRENT_TIMESTAMP,
        failed_attempts = 0,
        locked_until = NULL,
        reset_token_hash = NULL,
        reset_token_expires_at = NULL,
        reset_requested_at = NULL
    WHERE family_id = v_family_id;
END;
$$;

-- ----------------------------------------------------------------------------
-- enforce_child_mode_transition()
-- BEFORE UPDATE trigger on children - the REAL enforcement point for the PIN
-- gate, holding on EVERY write path (direct client UPDATE included), because the
-- children_update_policy alone would let an owner flip child_mode_enabled off
-- without a PIN. Enabling requires a PIN to exist; disabling requires the
-- transaction-local context flag that only exit_child_mode() sets after verifying
-- the PIN. SECURITY DEFINER so it can read child_mode_credentials regardless of
-- the caller's RLS.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.enforce_child_mode_transition()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
    IF NEW.child_mode_enabled AND NOT OLD.child_mode_enabled THEN
        IF NOT EXISTS (
            SELECT 1 FROM public.child_mode_credentials WHERE family_id = NEW.family_id
        ) THEN
            RAISE EXCEPTION 'Set a Child Mode PIN before enabling Child Mode.'
                USING HINT = 'pin_required', ERRCODE = 'check_violation';
        END IF;

    ELSIF OLD.child_mode_enabled AND NOT NEW.child_mode_enabled THEN
        IF current_setting('app.child_mode_ctx', true) IS DISTINCT FROM 'exit' THEN
            RAISE EXCEPTION 'Child Mode can only be turned off with the family PIN.'
                USING HINT = 'pin_required_to_exit', ERRCODE = 'check_violation';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_children_enforce_child_mode ON public.children;
CREATE TRIGGER trigger_children_enforce_child_mode
    BEFORE UPDATE ON public.children
    FOR EACH ROW
    WHEN (OLD.child_mode_enabled IS DISTINCT FROM NEW.child_mode_enabled)
    EXECUTE FUNCTION public.enforce_child_mode_transition();

-- ----------------------------------------------------------------------------
-- Lock down the internal helpers: a client must never call _verify_child_mode_pin
-- with an arbitrary family_id to brute-force another family. The SECURITY DEFINER
-- RPCs above still call them, as the function owner. REVOKE is idempotent.
-- ----------------------------------------------------------------------------

REVOKE EXECUTE ON FUNCTION public._child_mode_family_id()               FROM anon, authenticated, PUBLIC;
REVOKE EXECUTE ON FUNCTION public._validate_child_mode_pin_format(TEXT) FROM anon, authenticated, PUBLIC;
REVOKE EXECUTE ON FUNCTION public._verify_child_mode_pin(UUID, TEXT)    FROM anon, authenticated, PUBLIC;

-- ============================================================================
-- RLS POLICIES
-- ============================================================================

-- RLS is enabled with NO permissive policies: all direct client access to the
-- PIN hash and reset token is denied. Access is exclusively through the
-- SECURITY DEFINER functions above (service_role bypasses RLS for the edge fn).
ALTER TABLE public.child_mode_credentials ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- COMMENTS SECTION
-- ============================================================================

COMMENT ON TABLE  public.child_mode_credentials                        IS 'One row per family: the single bcrypt-hashed Child Mode PIN, brute-force lockout counters, and the folded-in forgot-PIN reset-token state. RLS denies all direct client access; reached only via the SECURITY DEFINER child-mode functions.';
COMMENT ON COLUMN public.child_mode_credentials.id                     IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN public.child_mode_credentials.family_id              IS 'The family this PIN belongs to (unique - one PIN per family).';
COMMENT ON COLUMN public.child_mode_credentials.pin_hash              IS 'Bcrypt hash of the 6-digit PIN (pgcrypto crypt/gen_salt(''bf'',10)). Never exposed to clients.';
COMMENT ON COLUMN public.child_mode_credentials.failed_attempts        IS 'Consecutive failed PIN verifications; reset to 0 on success. Every 5th failure triggers an escalating lockout.';
COMMENT ON COLUMN public.child_mode_credentials.locked_until           IS 'When set and in the future, PIN verification is blocked until this time (brute-force lockout).';
COMMENT ON COLUMN public.child_mode_credentials.last_changed_at        IS 'When the PIN was last created or changed.';
COMMENT ON COLUMN public.child_mode_credentials.reset_token_hash       IS 'SHA-256 hex of the current forgot-PIN reset token (raw token never stored). NULL when no reset is pending.';
COMMENT ON COLUMN public.child_mode_credentials.reset_token_expires_at IS 'Expiry of the pending reset token (30 minutes from request). NULL when none pending.';
COMMENT ON COLUMN public.child_mode_credentials.reset_requested_at     IS 'When the current reset token was requested; backs the 2-minute request throttle.';
COMMENT ON COLUMN public.child_mode_credentials.created_at             IS 'Row creation timestamp.';
COMMENT ON COLUMN public.child_mode_credentials.updated_at             IS 'Last-modified timestamp, stamped by the set_updated_at() trigger.';

COMMENT ON FUNCTION public._child_mode_family_id()               IS 'Internal: returns the caller''s active owned family id or raises no_family. REVOKEd from client roles; called only by the child-mode RPCs.';
COMMENT ON FUNCTION public._validate_child_mode_pin_format(TEXT) IS 'Internal: validates the 6-digit numeric PIN rule and rejects an all-same-digit PIN (raises pin_invalid).';
COMMENT ON FUNCTION public._verify_child_mode_pin(UUID, TEXT)    IS 'Internal: verifies a PIN against a family''s bcrypt hash with escalating brute-force lockout, RETURNING {result: ok|incorrect|locked} rather than raising - so the failed-attempt increment COMMITs instead of rolling back. REVOKEd from client roles so it cannot be called with an arbitrary family_id.';
COMMENT ON FUNCTION public.child_mode_pin_status()               IS 'Returns {has_pin, is_locked, locked_until, failed_attempts} for the caller''s family. No secrets; has_pin=false when the caller owns no active family.';
COMMENT ON FUNCTION public.set_child_mode_pin(TEXT, TEXT)        IS 'Creates the family PIN (first time) or changes it (verifying the current PIN, lockout applies). Returns {result: ok|incorrect|locked}. New PIN is immediately valid.';
COMMENT ON FUNCTION public.enter_child_mode(UUID, TEXT)          IS 'Owner-only: turns Child Mode on for a child (requires a PIN to exist) and records the running device id.';
COMMENT ON FUNCTION public.exit_child_mode(UUID, TEXT)           IS 'Owner-only: turns Child Mode off for a child, gated by the family PIN. Returns {result: ok|incorrect|locked, child_id}; on ok sets a transaction-local flag the children trigger requires, so no unverified path can disable Child Mode.';
COMMENT ON FUNCTION public.create_child_mode_pin_reset()         IS 'Forgot-PIN step 1: mints a single-use 30-minute reset token (stores only its SHA-256), throttled to 1/2min, and returns the raw token + owner email/name to the edge function.';
COMMENT ON FUNCTION public.redeem_child_mode_pin_reset(TEXT, TEXT) IS 'Forgot-PIN step 2: sets a new PIN without the old one, given a valid session and a matching unexpired token for the caller''s family; clears lockout and consumes the token. Generic reset_invalid on failure.';
COMMENT ON FUNCTION public.enforce_child_mode_transition()      IS 'BEFORE UPDATE trigger on children: enforces the PIN gate on every write path - enabling needs a PIN to exist; disabling needs the exit context flag set only by exit_child_mode().';
