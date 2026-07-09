import { z } from "zod";
import { createClient } from "@supabase/supabase-js";
import { handleCors, ok, err } from "../../_shared/response.ts";
import { requireAuth } from "../../_shared/auth.ts";
import { createAdminClient } from "../../_shared/supabase.ts";

const RequestSchema = z.object({
  child_id: z.string().uuid(),
  password: z.string().min(1),
});

Deno.serve(async (req: Request) => {
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;

  try {
    const user = await requireAuth(req);
    const body = await req.json();
    const data = RequestSchema.parse(body);

    if (!user.email) {
      return err("User has no email, cannot re-authenticate via password", 400);
    }

    // Verify parent's password by attempting to sign in
    // Use an anon client to avoid admin privilege escalation
    const anonClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      { auth: { persistSession: false } },
    );

    const { error: authError } = await anonClient.auth.signInWithPassword({
      email: user.email,
      password: data.password,
    });

    if (authError) {
      return err("Invalid password", 401);
    }

    const supabaseAdmin = createAdminClient();

    // Verify parent owns the child
    const { data: family, error: familyError } = await supabaseAdmin
      .from("children")
      .select("families!inner(owner_id)")
      .eq("id", data.child_id)
      .single();

    const families = family?.families as unknown as
      | { owner_id: string }
      | { owner_id: string }[]
      | null;
    const ownerId = Array.isArray(families)
      ? families[0]?.owner_id
      : families?.owner_id;

    if (familyError || ownerId !== user.id) {
      return err("Child not found or unauthorized", 403);
    }

    // Disable child mode
    const { error: updateError } = await supabaseAdmin
      .from("children")
      .update({
        child_mode_enabled: false,
        child_mode_device_id: null,
      })
      .eq("id", data.child_id);

    if (updateError) throw updateError;

    return ok({ child_id: data.child_id, child_mode_enabled: false });
  } catch (e: unknown) {
    const error = e instanceof Error ? e : new Error(String(e));
    return err(
      error.message || "Internal Server Error",
      error instanceof z.ZodError ? 400 : 500,
    );
  }
});
