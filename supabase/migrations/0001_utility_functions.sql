-- ============================================================================
-- FUNCTIONS
-- ============================================================================

CREATE OR REPLACE FUNCTION public.uuid_generate_v7()
RETURNS uuid
AS $$
DECLARE
  v_time timestamp with time zone := clock_timestamp();
  v_unix_t bigint := floor(extract(epoch from v_time) * 1000)::bigint;
  v_time_hex varchar := lpad(to_hex(v_unix_t), 12, '0');
  v_random_uuid varchar := gen_random_uuid()::text;
BEGIN
  RETURN (
    substr(v_time_hex, 1, 8) || '-' ||
    substr(v_time_hex, 9, 4) || '-' ||
    '7' || substr(v_random_uuid, 16, 3) || '-' ||
    substr(v_random_uuid, 20, 4) || '-' ||
    substr(v_random_uuid, 25, 12)
  )::uuid;
END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;

-- ============================================================================
-- COMMENTS SECTION
-- ============================================================================

COMMENT ON FUNCTION public.uuid_generate_v7() IS 'Generates a UUID version 7 based on the current timestamp.';
COMMENT ON FUNCTION public.set_updated_at()   IS 'Generic BEFORE UPDATE trigger that stamps updated_at = CURRENT_TIMESTAMP on every row update.';
