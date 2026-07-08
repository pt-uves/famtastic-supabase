import { z } from "zod";
import { handleCors, ok, err } from "../../_shared/response.ts";
import { requireAuth } from "../../_shared/auth.ts";
import { createAdminClient } from "../../_shared/supabase.ts";

const RequestSchema = z.object({
  child_id: z.string().uuid(),
  question_text: z.string().optional(),
  scheduled_at: z.string().datetime().optional(),
});

Deno.serve(async (req: Request) => {
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;

  try {
    const user = await requireAuth(req);
    const body = await req.json();
    const data = RequestSchema.parse(body);

    const supabaseAdmin = createAdminClient();

    // Verify access - only parent owner can send prompts
    const { data: family, error: familyError } = await supabaseAdmin
      .from("children")
      .select("family_id, families!inner(owner_id)")
      .eq("id", data.child_id)
      .single();

    const families = family?.families as unknown as { owner_id: string } | { owner_id: string }[] | null;
    const ownerId = Array.isArray(families) ? families[0]?.owner_id : families?.owner_id;

    if (familyError || ownerId !== user.id) {
      return err("Child not found or unauthorized (must be parent)", 403);
    }

    const isScheduled = !!data.scheduled_at;

    // Insert prompt
    const { data: prompt, error: insertError } = await supabaseAdmin
      .from("check_in_prompts")
      .insert({
        child_id: data.child_id,
        initiated_by: user.id,
        question_text: data.question_text,
        scheduled_at: data.scheduled_at,
        sent_at: isScheduled ? null : new Date().toISOString(),
      })
      .select()
      .single();

    if (insertError) throw insertError;

    if (!isScheduled) {
      // TODO: We will implement exact Expo Push call once libraries are finalized.
      // E.g. find push tokens for the child's active device
      console.log(`[TODO] Dispatch Expo Push check-in prompt to child ${data.child_id}`);
    }

    return ok({ prompt });
  } catch (e: unknown) {
    const error = e instanceof Error ? e : new Error(String(e));
    return err(error.message || "Internal Server Error", error instanceof z.ZodError ? 400 : 500);
  }
});
