// Authentication helper: resolves the caller from the request's bearer token.
// Uses an anon client bound to the caller's JWT so auth.getUser() validates it.

import { createClient, type User } from "@supabase/supabase-js";

// Thrown when the request is missing or carries an invalid bearer token.
// Callers map this to a 401 response.
export class AuthError extends Error {
  constructor(message = "Unauthorized") {
    super(message);
    this.name = "AuthError";
  }
}

// Validates the Authorization bearer token and returns the authenticated user.
// Throws AuthError (→ 401) when the token is missing or invalid.
export async function requireAuth(req: Request): Promise<User> {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    throw new AuthError("Missing Authorization header");
  }

  const client = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data, error } = await client.auth.getUser();
  if (error || !data.user) {
    throw new AuthError("Invalid or expired token");
  }
  return data.user;
}
