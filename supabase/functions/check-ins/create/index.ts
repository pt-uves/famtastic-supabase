import { z } from "zod";
import { handleCors, ok, err } from "../../_shared/response.ts";
import { requireAuth } from "../../_shared/auth.ts";
import { createAdminClient } from "../../_shared/supabase.ts";

const RequestSchema = z.object({
  child_id: z.string().uuid(),
  mood: z.enum(["happy", "calm", "overwhelmed", "angry"]),
  text_response: z.string().optional(),
  voice_note_url: z.string().url().optional(),
  shared_with_family: z.boolean().default(true),
  is_from_child: z.boolean().default(false),
  reply_prompt_id: z.string().uuid().optional(),
});

Deno.serve(async (req: Request) => {
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;

  try {
    const user = await requireAuth(req);
    const body = await req.json();
    const data = RequestSchema.parse(body);

    const supabaseAdmin = createAdminClient();

    // Verify access to child
    const { data: childAccess, error: accessError } = await supabaseAdmin.rpc(
      "is_linked_to_child",
      {
        p_child_id: data.child_id,
      },
    );
    const { data: isOwner } = await supabaseAdmin.rpc("owns_child", {
      p_child_id: data.child_id,
    });

    if (accessError || (!childAccess && !isOwner)) {
      // NOTE: Using raw admin check isn't perfectly mapped without injecting the caller context,
      // but RPCs called via admin client execute as postgres role. We need to check explicitly
      // by querying families/memberships or using a user-context client.
      // Let's use standard query to be safe with admin client.
      const { data: family } = await supabaseAdmin
        .from("children")
        .select("family_id, families!inner(owner_id)")
        .eq("id", data.child_id)
        .single();

      const { data: membership } = await supabaseAdmin
        .from("memberships")
        .select("id")
        .eq("child_id", data.child_id)
        .eq("account_id", user.id)
        .eq("invite_status", "accepted")
        .maybeSingle();

      const families = family?.families as unknown as
        | { owner_id: string }
        | { owner_id: string }[]
        | null;
      const ownerId = Array.isArray(families)
        ? families[0]?.owner_id
        : families?.owner_id;

      if (ownerId !== user.id && !membership) {
        return err("Child not found or unauthorized", 403);
      }
    }

    const checkInData = {
      child_id: data.child_id,
      author_id: data.is_from_child ? null : user.id,
      is_from_child: data.is_from_child,
      mood: data.mood,
      text_response: data.text_response,
      voice_note_url: data.voice_note_url,
      shared_with_family: data.shared_with_family,
    };

    // Insert check-in
    const { data: checkIn, error: insertError } = await supabaseAdmin
      .from("check_ins")
      .insert(checkInData)
      .select()
      .single();

    if (insertError) throw insertError;

    // If answering a prompt, link it
    if (data.reply_prompt_id && data.is_from_child) {
      await supabaseAdmin
        .from("check_in_prompts")
        .update({ reply_check_in_id: checkIn.id })
        .eq("id", data.reply_prompt_id)
        .eq("child_id", data.child_id);
    }

    // Push Notification dispatch logic
    if (data.shared_with_family) {
      // TODO: We will implement exact Expo Push call once libraries are finalized.
      console.log(
        `[TODO] Dispatch Expo Push notification to linked members for child ${data.child_id}`,
      );
    }

    return ok({ check_in: checkIn });
  } catch (e: unknown) {
    const error = e instanceof Error ? e : new Error(String(e));
    return err(
      error.message || "Internal Server Error",
      error instanceof z.ZodError ? 400 : 500,
    );
  }
});
