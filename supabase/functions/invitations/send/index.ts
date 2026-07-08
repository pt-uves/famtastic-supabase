import { z } from "zod";
import { handleCors, ok, err } from "../../_shared/response.ts";
import { requireAuth } from "../../_shared/auth.ts";
import { createAdminClient } from "../../_shared/supabase.ts";

const RequestSchema = z.object({
  email: z.string().email(),
  child_id: z.string().uuid(),
  role_category: z.enum([
    "co_parent",
    "caregiver",
    "grandparent",
    "teacher",
    "therapist",
    "relative",
    "other",
  ]),
  role_label: z.string().optional(),
});

Deno.serve(async (req: Request) => {
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;

  try {
    const user = await requireAuth(req);
    const body = await req.json();
    const data = RequestSchema.parse(body);

    const supabaseAdmin = createAdminClient();

    // Verify caller owns the child
    const { data: child, error: childError } = await supabaseAdmin
      .from("children")
      .select("family_id, families!inner(owner_id)")
      .eq("id", data.child_id)
      .single();

    const families = child?.families as unknown as { owner_id: string } | { owner_id: string }[] | null;
    const ownerId = Array.isArray(families) ? families[0]?.owner_id : families?.owner_id;

    if (childError || ownerId !== user.id) {
      return err("Child not found or unauthorized", 403);
    }

    // Lookup profile by email
    const { data: existingProfile } = await supabaseAdmin
      .from("profiles")
      .select("id")
      .eq("email", data.email)
      .maybeSingle();

    let accountId = existingProfile?.id;

    if (!accountId) {
      // Create auth user and send invite email
      const { data: inviteData, error: inviteError } = await supabaseAdmin.auth.admin.inviteUserByEmail(data.email);
      if (inviteError) throw inviteError;
      accountId = inviteData.user.id;
    }

    // Insert or update membership
    const { data: membership, error: membershipError } = await supabaseAdmin
      .from("memberships")
      .upsert(
        {
          account_id: accountId,
          child_id: data.child_id,
          role_category: data.role_category,
          role_label: data.role_label,
          invited_by: user.id,
          invite_status: "pending",
        },
        { onConflict: "account_id,child_id" }
      )
      .select()
      .single();

    if (membershipError) throw membershipError;

    // TODO: We will implement exact call once email/push libraries are finalized.
    console.log(`[TODO] Sent invitation email to ${data.email} for child ${data.child_id}`);

    return ok({ membership });
  } catch (e: unknown) {
    const error = e instanceof Error ? e : new Error(String(e));
    return err(error.message || "Internal Server Error", error instanceof z.ZodError ? 400 : 500);
  }
});
