// exit-child-mode
// Exits Child Mode on a device after verifying the parent's password.
//
// The device is signed in as the parent; we must verify the password WITHOUT
// starting a new session (a client-side signInWithPassword would rotate the
// device's tokens). So verification happens here with a throwaway client whose
// session is immediately discarded, then the child row is updated with the
// service role.

import { z } from "zod";
import { createClient } from "@supabase/supabase-js";
import { handleCors } from "../_shared/cors.ts";
import { requireAuth, AuthError } from "../_shared/auth.ts";
import { supabaseAdmin } from "../_shared/supabaseAdmin.ts";
import { ok, err } from "../_shared/response.ts";

const bodySchema = z.object({
  child_id: z.string().uuid(),
  password: z.string().min(1),
});

Deno.serve(async (req) => {
  const preflight = handleCors(req);
  if (preflight) return preflight;

  try {
    const user = await requireAuth(req);
    const { child_id, password } = bodySchema.parse(await req.json());

    if (!user.email) {
      return err("Account has no email to verify against.", 400);
    }

    const admin = supabaseAdmin();

    // Authorization re-check: only the owning parent can exit Child Mode.
    const { data: child, error: childErr } = await admin
      .from("children")
      .select("id, families!inner(owner_id, status)")
      .eq("id", child_id)
      .maybeSingle();
    if (childErr) throw childErr;

    const childData = child as {
      id: string;
      families: {
        owner_id: string;
        status: string;
      } | null;
    } | null;

    const family = childData?.families;
    if (!child || family?.owner_id !== user.id || family?.status !== "active") {
      return err("Only the child's parent can exit Child Mode.", 403);
    }

    // Verify the parent's password on a throwaway client; discard the session.
    const verifier = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { auth: { autoRefreshToken: false, persistSession: false } },
    );
    const { error: pwErr } = await verifier.auth.signInWithPassword({
      email: user.email,
      password,
    });
    await verifier.auth.signOut();
    if (pwErr) {
      return err("Incorrect password.", 401);
    }

    const { error: updErr } = await admin
      .from("children")
      .update({ child_mode_enabled: false, child_mode_device_id: null })
      .eq("id", child_id);
    if (updErr) throw updErr;

    return ok({ child_id, child_mode_enabled: false });
  } catch (e) {
    if (e instanceof AuthError) return err(e.message, 401);
    if (e instanceof z.ZodError)
      return err(e.errors[0]?.message ?? "Invalid request body.", 400);
    console.error("exit-child-mode error:", e);
    return err("Internal server error.", 500);
  }
});
