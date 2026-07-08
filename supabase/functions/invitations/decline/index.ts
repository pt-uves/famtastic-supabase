import { z } from "zod";
import { handleCors, ok, err } from "../../_shared/response.ts";
import { requireAuth } from "../../_shared/auth.ts";
import { createAdminClient } from "../../_shared/supabase.ts";

const RequestSchema = z.object({
  membership_id: z.string().uuid(),
});

Deno.serve(async (req: Request) => {
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;

  try {
    const user = await requireAuth(req);
    const body = await req.json();
    const { membership_id } = RequestSchema.parse(body);

    const supabaseAdmin = createAdminClient();

    // Verify membership belongs to caller and is pending
    const { data: membership, error: fetchError } = await supabaseAdmin
      .from("memberships")
      .select("*")
      .eq("id", membership_id)
      .eq("account_id", user.id)
      .eq("invite_status", "pending")
      .maybeSingle();

    if (fetchError) throw fetchError;
    if (!membership) return err("Membership not found, unauthorized, or not pending", 403);

    // Decline invite
    const { data: updatedMembership, error: updateError } = await supabaseAdmin
      .from("memberships")
      .update({ invite_status: "declined" })
      .eq("id", membership_id)
      .select()
      .single();

    if (updateError) throw updateError;

    return ok({ membership: updatedMembership });
  } catch (e: unknown) {
    const error = e instanceof Error ? e : new Error(String(e));
    return err(error.message || "Internal Server Error", error instanceof z.ZodError ? 400 : 500);
  }
});
