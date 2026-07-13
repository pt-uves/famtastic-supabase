-- ============================================================================
-- ENUMS
-- ============================================================================

DROP TYPE IF EXISTS sos_status CASCADE;
CREATE TYPE sos_status AS ENUM ('active', 'resolved');

DROP TYPE IF EXISTS notification_channel CASCADE;
CREATE TYPE notification_channel AS ENUM ('push', 'sms');

DROP TYPE IF EXISTS notification_status CASCADE;
CREATE TYPE notification_status AS ENUM ('sent', 'delivered', 'failed');

-- ============================================================================
-- TABLES
-- ============================================================================

-- ----------------------------------------------------------------------------
-- sos_events
-- One row per SOS trigger. The child's location at trigger time is stored
-- directly on this row (dedicated snapshot), independent of the live location
-- tables. Only an adult can resolve an SOS.
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.sos_events (
    id                      UUID                    PRIMARY KEY DEFAULT uuid_generate_v7(),
    child_id                UUID                    NOT NULL,
    triggered_by            UUID,
    triggered_by_child      BOOLEAN                 NOT NULL DEFAULT false,
    location_snapshot       GEOGRAPHY(POINT, 4326),
    location_accuracy_meters FLOAT,
    status                  sos_status              NOT NULL DEFAULT 'active',
    resolved_by             UUID,
    resolved_at             TIMESTAMPTZ,
    notes                   TEXT,
    cooldown_until          TIMESTAMPTZ,
    created_at              TIMESTAMPTZ             NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- An adult-triggered SOS must have triggered_by set.
    CONSTRAINT chk_sos_events_trigger CHECK (
        (triggered_by_child = true AND triggered_by IS NULL) OR
        (triggered_by_child = false AND triggered_by IS NOT NULL)
    ),
    -- resolved_by and resolved_at must both be set or both be NULL.
    CONSTRAINT chk_sos_events_resolve CHECK (
        (resolved_by IS NOT NULL AND resolved_at IS NOT NULL) OR
        (resolved_by IS NULL AND resolved_at IS NULL)
    )
);

-- ----------------------------------------------------------------------------
-- sos_notifications
-- One row per recipient per SOS event. Covers both in-app push (linked
-- members) and SMS (external emergency contacts).
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.sos_notifications (
    id                  UUID                        PRIMARY KEY DEFAULT uuid_generate_v7(),
    sos_event_id        UUID                        NOT NULL,
    recipient_id        UUID,
    external_contact_id UUID,
    channel             notification_channel        NOT NULL,
    status              notification_status         NOT NULL DEFAULT 'sent',
    sent_at             TIMESTAMPTZ                 NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Must target either an in-app member or an external contact, not neither.
    CONSTRAINT chk_sos_notifications_recipient CHECK (
        recipient_id IS NOT NULL OR external_contact_id IS NOT NULL
    )
);

-- ============================================================================
-- INDEXES / CONSTRAINTS
-- ============================================================================

ALTER TABLE public.sos_events DROP CONSTRAINT IF EXISTS fk_sos_events_child;
ALTER TABLE public.sos_events ADD CONSTRAINT fk_sos_events_child
    FOREIGN KEY (child_id) REFERENCES public.children (id) ON DELETE CASCADE;

ALTER TABLE public.sos_events DROP CONSTRAINT IF EXISTS fk_sos_events_triggered_by;
ALTER TABLE public.sos_events ADD CONSTRAINT fk_sos_events_triggered_by
    FOREIGN KEY (triggered_by) REFERENCES public.profiles (id) ON DELETE SET NULL;

ALTER TABLE public.sos_events DROP CONSTRAINT IF EXISTS fk_sos_events_resolved_by;
ALTER TABLE public.sos_events ADD CONSTRAINT fk_sos_events_resolved_by
    FOREIGN KEY (resolved_by) REFERENCES public.profiles (id) ON DELETE SET NULL;

-- Active SOS lookup - the most performance-critical query (full-screen alert).
CREATE INDEX IF NOT EXISTS idx_sos_events_child_status
    ON public.sos_events (child_id, status);

-- Admin portal SOS monitoring feed.
CREATE INDEX IF NOT EXISTS idx_sos_events_created_at
    ON public.sos_events (created_at DESC);

ALTER TABLE public.sos_notifications DROP CONSTRAINT IF EXISTS fk_sos_notifications_event;
ALTER TABLE public.sos_notifications ADD CONSTRAINT fk_sos_notifications_event
    FOREIGN KEY (sos_event_id) REFERENCES public.sos_events (id) ON DELETE CASCADE;

ALTER TABLE public.sos_notifications DROP CONSTRAINT IF EXISTS fk_sos_notifications_recipient;
ALTER TABLE public.sos_notifications ADD CONSTRAINT fk_sos_notifications_recipient
    FOREIGN KEY (recipient_id) REFERENCES public.profiles (id) ON DELETE SET NULL;

ALTER TABLE public.sos_notifications DROP CONSTRAINT IF EXISTS fk_sos_notifications_external;
ALTER TABLE public.sos_notifications ADD CONSTRAINT fk_sos_notifications_external
    FOREIGN KEY (external_contact_id) REFERENCES public.emergency_contacts (id) ON DELETE SET NULL;

-- ============================================================================
-- RLS POLICIES
-- ============================================================================

ALTER TABLE public.sos_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sos_notifications ENABLE ROW LEVEL SECURITY;

-- POLICIES - sos_events

DROP POLICY IF EXISTS "sos_events_select_policy" ON public.sos_events;
CREATE POLICY "sos_events_select_policy" ON public.sos_events
    FOR SELECT USING (
        owns_child(child_id) OR is_linked_to_child(child_id) OR is_platform_admin()
    );

DROP POLICY IF EXISTS "sos_events_insert_policy" ON public.sos_events;
CREATE POLICY "sos_events_insert_policy" ON public.sos_events
    FOR INSERT WITH CHECK (
        owns_child(child_id) OR is_linked_to_child(child_id)
    );

-- Only adults (not triggered_by_child) can resolve. Enforced here + app layer.
DROP POLICY IF EXISTS "sos_events_update_policy" ON public.sos_events;
CREATE POLICY "sos_events_update_policy" ON public.sos_events
    FOR UPDATE USING (
        (owns_child(child_id) OR is_linked_to_child(child_id))
        AND triggered_by_child = false  -- extra safety: children cannot resolve
    );

-- POLICIES - sos_notifications

DROP POLICY IF EXISTS "sos_notifications_select_policy" ON public.sos_notifications;
CREATE POLICY "sos_notifications_select_policy" ON public.sos_notifications
    FOR SELECT USING (
        recipient_id = auth.uid()
        OR is_platform_admin()
        OR EXISTS (
            SELECT 1 FROM public.sos_events e
            WHERE e.id = sos_notifications.sos_event_id
              AND (owns_child(e.child_id) OR is_linked_to_child(e.child_id))
        )
    );

-- ============================================================================
-- COMMENTS SECTION
-- ============================================================================

COMMENT ON TYPE  sos_status                                    IS 'Active = alert is live and visible to all linked members. Resolved = cleared by an adult.';
COMMENT ON TYPE  notification_channel                          IS 'Delivery channel: push notification (in-app member) or SMS (external contact).';
COMMENT ON TYPE  notification_status                           IS 'Delivery outcome for a single notification attempt.';

COMMENT ON TABLE  public.sos_events                                 IS 'A single SOS incident. Stores a dedicated location snapshot at trigger time, separate from the live location tables.';
COMMENT ON COLUMN public.sos_events.id                              IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN public.sos_events.child_id                        IS 'The child the SOS was raised for.';
COMMENT ON COLUMN public.sos_events.triggered_by                    IS 'Adult member who triggered the SOS. NULL when triggered_by_child = true.';
COMMENT ON COLUMN public.sos_events.triggered_by_child              IS 'True when the child tapped the SOS button in Child Mode.';
COMMENT ON COLUMN public.sos_events.location_snapshot               IS 'Location of the triggering person at the exact moment of trigger (GEOGRAPHY POINT, WGS 84).';
COMMENT ON COLUMN public.sos_events.location_accuracy_meters        IS 'GPS accuracy radius at trigger time.';
COMMENT ON COLUMN public.sos_events.status                          IS 'active while the alert is live; resolved after an adult clears it.';
COMMENT ON COLUMN public.sos_events.resolved_by                     IS 'Adult member who resolved the SOS.';
COMMENT ON COLUMN public.sos_events.resolved_at                     IS 'Timestamp when the SOS was resolved.';
COMMENT ON COLUMN public.sos_events.notes                           IS 'Optional outcome notes added at resolve time.';
COMMENT ON COLUMN public.sos_events.cooldown_until                  IS 'Timestamp until which new SOS triggers from this child should be ignored/debounced.';
COMMENT ON COLUMN public.sos_events.created_at                      IS 'Row creation timestamp - the SOS trigger time.';

COMMENT ON TABLE  public.sos_notifications                          IS 'One delivery record per recipient per SOS event. Covers push (linked members) and SMS (external contacts).';
COMMENT ON COLUMN public.sos_notifications.id                       IS 'Unique identifier (UUID v7).';
COMMENT ON COLUMN public.sos_notifications.sos_event_id             IS 'The SOS event this notification belongs to.';
COMMENT ON COLUMN public.sos_notifications.recipient_id             IS 'In-app member recipient. NULL for external contact SMS.';
COMMENT ON COLUMN public.sos_notifications.external_contact_id      IS 'External contact recipient. NULL for in-app push.';
COMMENT ON COLUMN public.sos_notifications.channel                  IS 'push or sms.';
COMMENT ON COLUMN public.sos_notifications.status                   IS 'Delivery outcome: sent, delivered, or failed.';
COMMENT ON COLUMN public.sos_notifications.sent_at                  IS 'When the notification was dispatched.';
