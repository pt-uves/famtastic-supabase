// child-mode-pin-reset-request
// Forgot-PIN step 1: emails the family admin a secure, single-use, time-limited
// deep link to set a new Child Mode PIN without the old one.
//
// Only the EMAIL SEND needs an edge function - the token is minted and stored
// (SHA-256 only) by the create_child_mode_pin_reset() RPC, and redemption is the
// redeem_child_mode_pin_reset() RPC the app calls directly. We call the RPC with
// the caller's own JWT (not the service role) so auth.uid() resolves the family.

import { createClient } from "@supabase/supabase-js";
import { AuthError, requireAuth } from "../_shared/auth.ts";
import { handleCors } from "../_shared/cors.ts";
import { sendEmail } from "../_shared/email.ts";
import { err, ok } from "../_shared/response.ts";
import { getChildModePinResetHtml } from "./child-mode-pin-reset.ts";

// Deep link the RN app handles via Linking. Overridable per environment.
const RESET_DEEPLINK =
  Deno.env.get("CHILD_MODE_RESET_DEEPLINK") ??
  "famtastic://child-mode/reset-pin";
const EXPIRY_MINUTES = "30"; // must match create_child_mode_pin_reset()

Deno.serve(async (req) => {
  const preflight = handleCors(req);
  if (preflight) return preflight;

  try {
    // Validates the bearer token; the same header authorizes the RPC below.
    await requireAuth(req);
    const authHeader = req.headers.get("Authorization")!;

    // A client bound to the caller's JWT so auth.uid() resolves inside the RPC.
    const userClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    );

    const { data, error } = await userClient.rpc("create_child_mode_pin_reset");

    if (error) {
      // The RPC signals the reason via the PostgreSQL error HINT.
      switch (error.hint) {
        case "no_family":
          return err("Only a family admin can reset the Child Mode PIN.", 403);
        case "rate_limited":
          return err(
            "A reset link was just sent. Please wait a couple of minutes before trying again.",
            429,
          );
        case "pin_required":
          return err("No Child Mode PIN is set yet.", 400);
        default:
          console.error("create_child_mode_pin_reset error:", error);
          return err("Internal server error.", 500);
      }
    }

    const { raw_token, email, full_name } = data as {
      raw_token: string;
      email: string;
      full_name: string | null;
    };

    const resetUrl = `${RESET_DEEPLINK}?token=${encodeURIComponent(raw_token)}`;

    const html = getChildModePinResetHtml({
      full_name: full_name ?? "there",
      reset_url: resetUrl,
      expiry_minutes: EXPIRY_MINUTES,
    });

    await sendEmail({
      to: email,
      subject: "Reset your Famtastic Child Mode PIN",
      html,
    });

    // Do not echo the token or email back to the client.
    return ok({ sent: true });
  } catch (e) {
    if (e instanceof AuthError) return err(e.message, 401);
    console.error("child-mode-pin-reset-request error:", e);
    return err("Internal server error.", 500);
  }
});
