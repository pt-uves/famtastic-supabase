import { z } from "zod";
import { handleCors, ok, err } from "../../_shared/response.ts";
import { requireAuth } from "../../_shared/auth.ts";
import { createAdminClient } from "../../_shared/supabase.ts";

const RequestSchema = z.object({
  child_id: z.string().uuid(),
  device_id: z.string().min(1),
});

Deno.serve(async (req: Request) => {
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;

  try {
    const user = await requireAuth(req);
    const body = await req.json();
    const data = RequestSchema.parse(body);

    const supabaseAdmin = createAdminClient();

    // Verify parent owns the child
    const { data: family, error: familyError } = await supabaseAdmin
      .from("children")
      .select("families!inner(owner_id)")
      .eq("id", data.child_id)
      .single();

    const families = family?.families as unknown as { owner_id: string } | { owner_id: string }[] | null;
    const ownerId = Array.isArray(families) ? families[0]?.owner_id : families?.owner_id;

    if (familyError || ownerId !== user.id) {
      return err("Child not found or unauthorized", 403);
    }

    // Enable child mode
    const { error: updateError } = await supabaseAdmin
      .from("children")
      .update({
        child_mode_enabled: true,
        child_mode_device_id: data.device_id,
      })
      .eq("id", data.child_id);

    if (updateError) throw updateError;

    return ok({ child_id: data.child_id, child_mode_enabled: true });
  } catch (e: unknown) {
    const error = e instanceof Error ? e : new Error(String(e));
    return err(error.message || "Internal Server Error", error instanceof z.ZodError ? 400 : 500);
  }
});
