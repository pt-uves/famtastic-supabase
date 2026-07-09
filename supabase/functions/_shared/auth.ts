import { createClient } from "@supabase/supabase-js";

/**
 * Extracts and verifies the JWT from the Authorization header,
 * returning the authenticated user. Throws an error if invalid.
 */
export const requireAuth = async (req: Request) => {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    throw new Error("Missing Authorization header");
  }

  // Create a fast, throwaway client just for auth verification
  const supabaseClient = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false },
    },
  );

  const {
    data: { user },
    error,
  } = await supabaseClient.auth.getUser();

  if (error || !user) {
    throw new Error("Invalid or expired token");
  }

  return user;
};
