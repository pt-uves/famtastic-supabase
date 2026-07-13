// Shared CORS handling for all edge functions.
// The mobile app and admin web portal call these functions from other origins,
// so every response must carry CORS headers and OPTIONS must be short-circuited.

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// Returns a 204 response for CORS preflight (OPTIONS) requests, or null when the
// request should proceed to the handler.
export function handleCors(req: Request): Response | null {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  return null;
}
