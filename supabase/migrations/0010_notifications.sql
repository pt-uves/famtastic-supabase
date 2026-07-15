-- ============================================================================
-- ENUMS
-- ============================================================================

DROP TYPE IF EXISTS push_platform CASCADE;
CREATE TYPE push_platform AS ENUM ('ios', 'android', 'web');

DROP TYPE IF EXISTS notification_status CASCADE;
CREATE TYPE notification_status AS ENUM ('pending', 'sent', 'failed');

DROP TYPE IF EXISTS notification_priority CASCADE;
CREATE TYPE notification_priority AS ENUM ('normal', 'high');

-- ============================================================================
-- TABLES
-- ============================================================================

-- ----------------------------------------------------------------------------
-- push_tokens
-- Device push tokens. One account can register several devices. device_id ties
-- a token to a physical device so a child-mode prompt can be delivered to the
-- exact device running Child Mode (children.child_mode_device_id), even though
-- that device is signed in as an adult (the child never authenticates).
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.push_tokens (
    id            UUID          PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id       UUID          NOT NULL,
    device_id     TEXT,
    token         TEXT          NOT NULL,
    platform      push_platform NOT NULL,
    last_seen_at  TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at    TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ----------------------------------------------------------------------------
-- notifications
-- Generic outbox + inbox for ANY app notification. A row targets EITHER an adult
-- account (recipient_user_id) OR a child's Child-Mode device (recipient_child_id)
-- - exactly one. The source is a polymorphic (entity_type, entity_id) reference
-- so any feature (check-in prompts, tasks, SOS, invites, ...) can produce
-- notifications without schema changes. status tracks delivery; read_at tracks
-- the in-app inbox. Check-in prompts are simply the first producer.
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.notifications (
    id                  UUID                    PRIMARY KEY DEFAULT uuid_generate_v7(),
    recipient_user_id   UUID,
    recipient_child_id  UUID,
    entity_type         TEXT,
    entity_id           UUID,
    title               TEXT                    NOT NULL,
    body                TEXT,
    data                JSONB                   NOT NULL DEFAULT '{}'::jsonb,
    status              notification_status     NOT NULL DEFAULT 'pending',
    priority            notification_priority   NOT NULL DEFAULT 'normal',
    last_error          TEXT,
    sent_at             TIMESTAMPTZ,
    read_at             TIMESTAMPTZ,
    created_at          TIMESTAMPTZ             NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMPTZ             NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Exactly one recipient: an adult account or a child device, never both/neither.
    CONSTRAINT chk_notifications_recipient CHECK (
        (recipient_user_id IS NOT NULL)::int + (recipient_child_id IS NOT NULL)::int = 1
    ),
    -- A polymorphic source is either fully present or fully absent.
    CONSTRAINT chk_notifications_entity CHECK (
        (entity_type IS NULL) = (entity_id IS NULL)
    )
);

-- ============================================================================
-- INDEXES / CONSTRAINTS
-- ============================================================================

-- A device token is registered once per account.
CREATE UNIQUE INDEX IF NOT EXISTS uk_push_tokens_user_token
    ON public.push_tokens (user_id, token);

ALTER TABLE public.push_tokens DROP CONSTRAINT IF EXISTS fk_push_tokens_user;
ALTER TABLE public.push_tokens ADD CONSTRAINT fk_push_tokens_user
    FOREIGN KEY (user_id) REFERENCES public.profiles (id) ON DELETE CASCADE;

-- Lookup all tokens for an account when sending to that account's devices.
CREATE INDEX IF NOT EXISTS idx_push_tokens_user_id
    ON public.push_tokens (user_id);

-- Lookup the token for a specific device (child-mode delivery target).
CREATE INDEX IF NOT EXISTS idx_push_tokens_device_id
    ON public.push_tokens (device_id)
    WHERE device_id IS NOT NULL;

ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS fk_notifications_recipient_user;
ALTER TABLE public.notifications ADD CONSTRAINT fk_notifications_recipient_user
    FOREIGN KEY (recipient_user_id) REFERENCES public.profiles (id) ON DELETE CASCADE;

ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS fk_notifications_recipient_child;
ALTER TABLE public.notifications ADD CONSTRAINT fk_notifications_recipient_child
    FOREIGN KEY (recipient_child_id) REFERENCES public.children (id) ON DELETE CASCADE;

-- (entity_type, entity_id) is a polymorphic reference across many tables, so it
-- carries no FK. Producers set it; readers use it for deep-linking/grouping.

-- Inbox reads for an adult account, newest first.
CREATE INDEX IF NOT EXISTS idx_notifications_recipient_user
    ON public.notifications (recipient_user_id, created_at DESC)
    WHERE recipient_user_id IS NOT NULL;

-- Inbox reads for a child's device, newest first.
CREATE INDEX IF NOT EXISTS idx_notifications_recipient_child
    ON public.notifications (recipient_child_id, created_at DESC)
    WHERE recipient_child_id IS NOT NULL;

-- Dispatch queue: the sender picks up everything still pending.
CREATE INDEX IF NOT EXISTS idx_notifications_pending
    ON public.notifications (created_at)
    WHERE status = 'pending';

-- Find notifications for a given source entity (e.g. all for one prompt/task).
CREATE INDEX IF NOT EXISTS idx_notifications_entity
    ON public.notifications (entity_type, entity_id)
    WHERE entity_id IS NOT NULL;

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Keep updated_at current on every change.
DROP TRIGGER IF EXISTS trigger_push_tokens_set_updated_at ON public.push_tokens;
CREATE TRIGGER trigger_push_tokens_set_updated_at
    BEFORE UPDATE ON public.push_tokens
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trigger_notifications_set_updated_at ON public.notifications;
CREATE TRIGGER trigger_notifications_set_updated_at
    BEFORE UPDATE ON public.notifications
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

-- ----------------------------------------------------------------------------
-- enqueue_notification(...)
-- Generic producer helper. ANY feature (check-in prompt, task, SOS, invite, ...)
-- calls this to queue one notification; the notifications AFTER INSERT trigger
-- then delivers it via send-push. Targets exactly one recipient - pass EITHER
-- p_recipient_user_id (an adult account) OR p_recipient_child_id (a child's
-- Child-Mode device); the table CHECK rejects both/neither. p_priority = 'high'
-- for time-sensitive alerts (e.g. SOS), which send-push maps to a high-priority
-- FCM payload. Returns the new notification id. SECURITY DEFINER so producers
-- can enqueue regardless of the caller's RLS.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.enqueue_notification(
    p_title              TEXT,
    p_body               TEXT                  DEFAULT NULL,
    p_recipient_user_id  UUID                  DEFAULT NULL,
    p_recipient_child_id UUID                  DEFAULT NULL,
    p_entity_type        TEXT                  DEFAULT NULL,
    p_entity_id          UUID                  DEFAULT NULL,
    p_data               JSONB                 DEFAULT '{}'::jsonb,
    p_priority           notification_priority DEFAULT 'normal'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_id UUID;
BEGIN
    INSERT INTO public.notifications (
        recipient_user_id, recipient_child_id, entity_type, entity_id,
        title, body, data, priority
    ) VALUES (
        p_recipient_user_id, p_recipient_child_id, p_entity_type, p_entity_id,
        p_title, p_body, COALESCE(p_data, '{}'::jsonb), p_priority
    )
    RETURNING id INTO v_id;
    RETURN v_id;
END;
$$;

-- ----------------------------------------------------------------------------
-- enqueue_child_family_notification(...)
-- Fan-out helper: queue one adult-targeted notification per account linked to a
-- child - the family owner plus every accepted member - skipping suspended
-- families and, optionally, one account (p_exclude_user_id, e.g. the actor who
-- triggered the event). Use for alerts that go to the whole care circle (SOS,
-- task assigned/completed, ...). Returns the number of notifications queued.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.enqueue_child_family_notification(
    p_child_id        UUID,
    p_title           TEXT,
    p_body            TEXT                  DEFAULT NULL,
    p_entity_type     TEXT                  DEFAULT NULL,
    p_entity_id       UUID                  DEFAULT NULL,
    p_data            JSONB                 DEFAULT '{}'::jsonb,
    p_priority        notification_priority DEFAULT 'normal',
    p_exclude_user_id UUID                  DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid   UUID;
    v_count INTEGER := 0;
BEGIN
    FOR v_uid IN
        SELECT f.owner_id
        FROM public.children c
        JOIN public.families f ON f.id = c.family_id
        WHERE c.id = p_child_id AND f.status = 'active'
        UNION
        SELECT m.account_id
        FROM public.memberships m
        JOIN public.children c2 ON c2.id = m.child_id
        JOIN public.families  f2 ON f2.id = c2.family_id
        WHERE m.child_id = p_child_id
          AND m.invite_status = 'accepted'
          AND f2.status = 'active'
    LOOP
        IF p_exclude_user_id IS NOT NULL AND v_uid = p_exclude_user_id THEN
            CONTINUE;
        END IF;
        PERFORM public.enqueue_notification(
            p_title              => p_title,
            p_body               => p_body,
            p_recipient_user_id  => v_uid,
            p_entity_type        => p_entity_type,
            p_entity_id          => p_entity_id,
            p_data               => p_data,
            p_priority           => p_priority
        );
        v_count := v_count + 1;
    END LOOP;
    RETURN v_count;
END;
$$;

-- ----------------------------------------------------------------------------
-- enqueue_check_in_prompt_notification()
-- Producer for check-in prompts (delivered to the child's Child-Mode device on
-- creation). Dogfoods enqueue_notification, then stamps the prompt's sent_at.
-- SECURITY DEFINER so it can write regardless of the initiating parent's RLS.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.enqueue_check_in_prompt_notification()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public.enqueue_notification(
        p_title              => 'Time to check in',
        p_body               => COALESCE(NEW.question_text, 'Your parent asked how you are feeling.'),
        p_recipient_child_id => NEW.child_id,
        p_entity_type        => 'check_in_prompt',
        p_entity_id          => NEW.id,
        p_data               => jsonb_build_object('prompt_id', NEW.id, 'child_id', NEW.child_id)
    );

    UPDATE public.check_in_prompts
    SET sent_at = CURRENT_TIMESTAMP
    WHERE id = NEW.id AND sent_at IS NULL;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_check_in_prompts_enqueue_notification ON public.check_in_prompts;
CREATE TRIGGER trigger_check_in_prompts_enqueue_notification
    AFTER INSERT ON public.check_in_prompts
    FOR EACH ROW
    EXECUTE FUNCTION public.enqueue_check_in_prompt_notification();

-- Delivery is server-driven and purely event-triggered: the notifications AFTER
-- INSERT trigger below POSTs to the send-push edge function via pg_net the moment
-- a pending row is created. Retry is built into send-push (transient FCM failures
-- are retried with backoff in the same invocation). No client, no polling cron.

-- ----------------------------------------------------------------------------
-- notification_edge_request(p_body jsonb)
-- Internal helper: fire an async pg_net POST to the send-push edge function with
-- the shared webhook secret. Reads the base URL + secret from Vault so the same
-- migration works local/staging/prod (set the secrets per environment). If
-- either secret is unset (e.g. a fresh local db) it no-ops, so db:reset and
-- ordinary inserts never fail on a missing config (the notification just stays
-- pending). SECURITY DEFINER to read vault + call net regardless of the
-- inserting user. Every failure is swallowed - delivery must never roll back the
-- transaction that produced the notification.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.notification_edge_request(p_body JSONB)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, vault, net
AS $$
DECLARE
    v_url    TEXT;
    v_secret TEXT;
BEGIN
    SELECT decrypted_secret INTO v_url    FROM vault.decrypted_secrets WHERE name = 'edge_base_url';
    SELECT decrypted_secret INTO v_secret FROM vault.decrypted_secrets WHERE name = 'push_webhook_secret';

    IF v_url IS NULL OR v_secret IS NULL THEN
        RETURN;  -- unconfigured environment: leave pending for the cron sweep
    END IF;

    PERFORM net.http_post(
        url     := rtrim(v_url, '/') || '/functions/v1/send-push',
        body    := p_body,
        headers := jsonb_build_object(
            'Content-Type',    'application/json',
            'x-webhook-secret', v_secret
        )
    );
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'notification_edge_request failed: %', SQLERRM;
END;
$$;

-- ----------------------------------------------------------------------------
-- dispatch_notification()
-- AFTER INSERT trigger on notifications: any producer (check-in prompt, task,
-- SOS, ...) that inserts a pending row triggers an immediate server-side push.
-- No client is involved - the app just creates its source row. pg_net queues the
-- POST to run after commit, so this never blocks the insert.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.dispatch_notification()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.status = 'pending' THEN
        PERFORM public.notification_edge_request(
            jsonb_build_object('notification_id', NEW.id)
        );
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_notifications_dispatch ON public.notifications;
CREATE TRIGGER trigger_notifications_dispatch
    AFTER INSERT ON public.notifications
    FOR EACH ROW
    EXECUTE FUNCTION public.dispatch_notification();

-- ----------------------------------------------------------------------------
-- retry_pending_notifications()
-- Safety net for the fire-once dispatch trigger: the AFTER INSERT push can be
-- lost if the edge function is briefly down/cold or Vault secrets were unset
-- when the row was created, leaving it stuck 'pending' with no self-heal. This
-- re-drives every notification still pending after a grace period (5 min, so it
-- never races the insert-time dispatch) by handing their ids to send-push, which
-- marks each sent/failed. Scheduled every 5 minutes by pg_cron below. Returns the
-- number of notifications re-driven.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.retry_pending_notifications()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_ids JSONB;
BEGIN
    SELECT jsonb_agg(id) INTO v_ids
    FROM public.notifications
    WHERE status = 'pending'
      AND created_at < CURRENT_TIMESTAMP - INTERVAL '5 minutes';

    IF v_ids IS NULL THEN
        RETURN 0;
    END IF;

    PERFORM public.notification_edge_request(
        jsonb_build_object('notification_ids', v_ids)
    );
    RETURN jsonb_array_length(v_ids);
END;
$$;

-- Re-drive stuck-pending notifications every 5 minutes.
SELECT cron.schedule(
    'retry_pending_notifications',
    '*/5 * * * *',
    $$ SELECT public.retry_pending_notifications(); $$
);

-- ============================================================================
-- RLS POLICIES
-- ============================================================================

ALTER TABLE public.push_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- POLICIES - push_tokens (an account manages only its own device tokens)

DROP POLICY IF EXISTS "push_tokens_select_policy" ON public.push_tokens;
CREATE POLICY "push_tokens_select_policy" ON public.push_tokens
    FOR SELECT USING (user_id = auth.uid() OR is_platform_admin());

DROP POLICY IF EXISTS "push_tokens_insert_policy" ON public.push_tokens;
CREATE POLICY "push_tokens_insert_policy" ON public.push_tokens
    FOR INSERT WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "push_tokens_update_policy" ON public.push_tokens;
CREATE POLICY "push_tokens_update_policy" ON public.push_tokens
    FOR UPDATE USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "push_tokens_delete_policy" ON public.push_tokens;
CREATE POLICY "push_tokens_delete_policy" ON public.push_tokens
    FOR DELETE USING (user_id = auth.uid());

-- POLICIES - notifications
-- Read: the adult recipient, or anyone with access to the recipient child
-- (the account running that child's device sees the child's prompts).

DROP POLICY IF EXISTS "notifications_select_policy" ON public.notifications;
CREATE POLICY "notifications_select_policy" ON public.notifications
    FOR SELECT USING (
        is_platform_admin()
        OR recipient_user_id = auth.uid()
        OR (recipient_child_id IS NOT NULL
            AND (owns_child(recipient_child_id) OR is_linked_to_child(recipient_child_id)))
    );

-- Direct creation is limited to the child's owner; the normal path is the
-- SECURITY DEFINER enqueue trigger (and the service role, which bypasses RLS).
DROP POLICY IF EXISTS "notifications_insert_policy" ON public.notifications;
CREATE POLICY "notifications_insert_policy" ON public.notifications
    FOR INSERT WITH CHECK (
        recipient_child_id IS NOT NULL AND owns_child(recipient_child_id)
    );

-- Update: recipients mark their own notifications read.
DROP POLICY IF EXISTS "notifications_update_policy" ON public.notifications;
CREATE POLICY "notifications_update_policy" ON public.notifications
    FOR UPDATE
    USING (
        recipient_user_id = auth.uid()
        OR (recipient_child_id IS NOT NULL
            AND (owns_child(recipient_child_id) OR is_linked_to_child(recipient_child_id)))
    )
    WITH CHECK (
        recipient_user_id = auth.uid()
        OR (recipient_child_id IS NOT NULL
            AND (owns_child(recipient_child_id) OR is_linked_to_child(recipient_child_id)))
    );

DROP POLICY IF EXISTS "notifications_delete_policy" ON public.notifications;
CREATE POLICY "notifications_delete_policy" ON public.notifications
    FOR DELETE USING (
        recipient_user_id = auth.uid()
        OR (recipient_child_id IS NOT NULL AND owns_child(recipient_child_id))
    );

-- ============================================================================
-- COMMENTS SECTION
-- ============================================================================

COMMENT ON TYPE  push_platform        IS 'Mobile OS platform for a push notification token.';
COMMENT ON TYPE  notification_status  IS 'Delivery state of a notification: pending -> sent | failed.';
COMMENT ON TYPE  notification_priority IS 'Delivery urgency: normal, or high for time-sensitive alerts (e.g. SOS) that send-push maps to a high-priority FCM payload.';

COMMENT ON TABLE  public.push_tokens               IS 'Device push tokens. An account can register multiple devices; device_id targets the specific Child-Mode device.';
COMMENT ON COLUMN public.push_tokens.id            IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN public.push_tokens.user_id       IS 'The account (adult) that owns this device/token. A child device is signed in as the hosting adult.';
COMMENT ON COLUMN public.push_tokens.device_id     IS 'Stable device identifier; matches children.child_mode_device_id to route child-mode prompts to the right device.';
COMMENT ON COLUMN public.push_tokens.token         IS 'FCM (Android) or APNs (iOS) / web push device token.';
COMMENT ON COLUMN public.push_tokens.platform      IS 'ios, android, or web.';
COMMENT ON COLUMN public.push_tokens.last_seen_at  IS 'Last time this token was confirmed active (refresh on app open).';
COMMENT ON COLUMN public.push_tokens.created_at    IS 'Row creation timestamp.';
COMMENT ON COLUMN public.push_tokens.updated_at    IS 'Last-modified timestamp, stamped by the set_updated_at() trigger.';

COMMENT ON TABLE  public.notifications                     IS 'Generic app notification outbox/inbox for any feature. Targets exactly one recipient: an adult account or a child device. Source is the polymorphic (entity_type, entity_id).';
COMMENT ON COLUMN public.notifications.id                  IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN public.notifications.recipient_user_id   IS 'Adult recipient. NULL when the notification targets a child device.';
COMMENT ON COLUMN public.notifications.recipient_child_id  IS 'Child recipient (delivered to that child''s Child-Mode device). NULL when targeting an adult.';
COMMENT ON COLUMN public.notifications.entity_type         IS 'Polymorphic source kind (e.g. check_in_prompt, task). NULL for a source-less notification. Set together with entity_id.';
COMMENT ON COLUMN public.notifications.entity_id           IS 'Polymorphic source row id (no FK - may reference any table). Set together with entity_type.';
COMMENT ON COLUMN public.notifications.title               IS 'Short notification title shown on the device.';
COMMENT ON COLUMN public.notifications.body                IS 'Notification body text.';
COMMENT ON COLUMN public.notifications.data                IS 'JSON payload for client deep-linking (e.g. prompt_id, child_id).';
COMMENT ON COLUMN public.notifications.status              IS 'Delivery state: pending until the sender dispatches it, then sent or failed.';
COMMENT ON COLUMN public.notifications.priority            IS 'Delivery urgency (normal | high). high yields a high-priority FCM payload (sound, time-sensitive), used for alerts like SOS.';
COMMENT ON COLUMN public.notifications.last_error          IS 'Provider/delivery error from the last send-push attempt (e.g. an FCM error), for observability. NULL when never failed. send-push retries transient failures internally before recording this.';
COMMENT ON COLUMN public.notifications.sent_at             IS 'Timestamp the push was dispatched. NULL while pending.';
COMMENT ON COLUMN public.notifications.read_at             IS 'Timestamp the recipient opened it in-app. NULL = unread.';
COMMENT ON COLUMN public.notifications.created_at          IS 'Row creation timestamp.';
COMMENT ON COLUMN public.notifications.updated_at          IS 'Last-modified timestamp, stamped by the set_updated_at() trigger.';

COMMENT ON FUNCTION public.enqueue_notification(TEXT, TEXT, UUID, UUID, TEXT, UUID, JSONB, notification_priority) IS 'Generic producer: queues one notification (exactly one recipient - user or child) and returns its id. The dispatch trigger delivers it via send-push. Any feature calls this instead of inserting notifications directly.';
COMMENT ON FUNCTION public.enqueue_child_family_notification(UUID, TEXT, TEXT, TEXT, UUID, JSONB, notification_priority, UUID) IS 'Fan-out producer: queues one adult-targeted notification per account linked to the child (owner + accepted members, active families only), optionally excluding one account. Returns the count queued. Use for whole-care-circle alerts (SOS, task events).';
COMMENT ON FUNCTION public.enqueue_check_in_prompt_notification() IS 'Trigger function: on prompt insert, queues a child-device notification via enqueue_notification and stamps the prompt sent_at. The dispatch trigger delivers it via send-push.';
COMMENT ON FUNCTION public.notification_edge_request(JSONB) IS 'Fires an async pg_net POST to the send-push edge function with the Vault webhook secret. No-ops when Vault secrets are unset; swallows all errors so delivery never rolls back the producing transaction.';
COMMENT ON FUNCTION public.dispatch_notification()         IS 'AFTER INSERT trigger on notifications: event-triggered server-side push dispatch for any pending notification via send-push (no client; send-push retries transient FCM failures internally).';
COMMENT ON FUNCTION public.retry_pending_notifications()   IS 'pg_cron sweep (every 5 min): re-drives notifications still pending after a 5-minute grace period through send-push, recovering rows the fire-once dispatch trigger failed to deliver. Returns the count re-driven.';
