-- ============================================================================
-- CRON JOBS (pg_cron)
-- ============================================================================
-- Scheduled background tasks running inside the database.
-- Requires the pg_cron extension (enabled on Supabase by default).
-- ============================================================================

-- ============================================================================
-- LOCATION HISTORY PURGE
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