import { createClient } from "@supabase/supabase-js";

// Create a service-role client for privileged admin operations.
// WARNING: Bypasses RLS. Do not use for generic reads where RLS should apply.
export const createAdminClient = () => {
  return createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    },
  );
};
