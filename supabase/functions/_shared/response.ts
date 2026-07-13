// Standard JSON response helpers shared by all edge functions.

import { corsHeaders } from "./cors.ts";

const jsonHeaders = { ...corsHeaders, "Content-Type": "application/json" };

// Success response with an arbitrary JSON body.
export function ok(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), { status, headers: jsonHeaders });
}

// Error response with a message. Defaults to 400.
export function err(message: string, status = 400): Response {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: jsonHeaders,
  });
}
