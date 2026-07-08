-- ============================================================================
-- CRON JOBS (pg_cron)
-- ============================================================================
-- Scheduled background tasks running inside the database.
-- Requires the pg_cron extension (enabled on Supabase by default).
-- ============================================================================

-- Ensure pg_cron is enabled in the extensions schema
CREATE EXTENSION IF NOT EXISTS pg_cron SCHEMA extensions;

-- ============================================================================
-- 1. OVERDUE TASKS
-- ============================================================================
-- Runs every hour at the top of the hour.
-- Finds all tasks where due_at is in the past and status is still 'pending'.
-- Updates their status to 'overdue'.

SELECT cron.schedule(
    'mark_overdue_tasks',
    '0 * * * *', -- Every hour
    $$
    UPDATE public.tasks
    SET status = 'overdue',
        updated_at = CURRENT_TIMESTAMP
    WHERE due_at < NOW()
      AND status = 'pending';
    $$
);

-- ============================================================================
-- 2. LOCATION HISTORY PURGE
-- ============================================================================
-- Runs daily at 02:00.
-- Deletes location history older than 30 days to prevent unbounded table growth.

SELECT cron.schedule(
    'purge_old_location_history',
    '0 2 * * *', -- 02:00 daily
    $$
    DELETE FROM public.location_history
    WHERE recorded_at < NOW() - INTERVAL '30 days';
    $$
);

-- ============================================================================
-- 3. CHECK-IN PROMPTS DISPATCH
-- ============================================================================
-- Runs every 5 minutes.
-- (This invokes an Edge Function via pg_net to actually send the push notification.
-- For Milestone 1, we just mark the DB rows as sent. Edge function call is TODO).
-- ============================================================================

-- Ensure pg_net is enabled for calling Edge Functions
CREATE EXTENSION IF NOT EXISTS pg_net SCHEMA extensions;

SELECT cron.schedule(
    'dispatch_scheduled_check_in_prompts',
    '*/5 * * * *', -- Every 5 minutes
    $$
    -- Update the sent_at timestamp so we don't process them again.
    -- The actual push notification delivery requires calling the Edge Function
    -- via extensions.http_post(), which is deferred until the push provider is set.
    UPDATE public.check_in_prompts
    SET sent_at = CURRENT_TIMESTAMP
    WHERE scheduled_at <= NOW()
      AND sent_at IS NULL;
    $$
);

-- ============================================================================
-- COMMENTS SECTION
-- ============================================================================

COMMENT ON EXTENSION pg_cron IS 'PostgreSQL cron extension for scheduling background jobs.';
COMMENT ON EXTENSION pg_net IS 'PostgreSQL networking extension for calling external APIs/Edge Functions.';
