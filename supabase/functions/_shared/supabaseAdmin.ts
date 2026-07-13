// Service-role client factory. This client BYPASSES Row Level Security, so every
// handler that uses it MUST re-check authorization explicitly (e.g. confirm the
// caller owns the child) before mutating data.

import { createClient, type SupabaseClient } from "@supabase/supabase-js";

export function supabaseAdmin(): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { autoRefreshToken: false, persistSession: false } },
  );
}
