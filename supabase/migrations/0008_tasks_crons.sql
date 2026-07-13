-- ============================================================================
-- OVERDUE TASKS
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