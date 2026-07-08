import { z } from "zod";
import { handleCors, ok, err } from "../../_shared/response.ts";
import { requireAuth } from "../../_shared/auth.ts";
import { createAdminClient } from "../../_shared/supabase.ts";

const RequestSchema = z.object({
  family_id: z.string().uuid(),
  name: z.string().min(1),
  date_of_birth: z.string().optional(),
  gender: z.enum(["male", "female", "other", "prefer_not_to_say"]).optional(),
  diagnosis: z.string().optional(),
  special_notes: z.string().optional(),
  language_level: z.enum(["simple", "standard", "full"]).default("standard"),
  communication_preferences: z.string().optional(),
});

Deno.serve(async (req: Request) => {
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;

  try {
    const user = await requireAuth(req);
    const body = await req.json();
    const data = RequestSchema.parse(body);

    const supabaseAdmin = createAdminClient();

    // Verify family ownership
    const { data: family, error: familyError } = await supabaseAdmin
      .from("families")
      .select("id")
      .eq("id", data.family_id)
      .eq("owner_id", user.id)
      .maybeSingle();

    if (familyError) throw familyError;
    if (!family) return err("Family not found or unauthorized", 403);

    // Insert child
    const { data: child, error: childError } = await supabaseAdmin
      .from("children")
      .insert(data)
      .select()
      .single();

    if (childError) throw childError;

    return ok({ child });
  } catch (e: unknown) {
    const error = e instanceof Error ? e : new Error(String(e));
    return err(error.message || "Internal Server Error", error instanceof z.ZodError ? 400 : 500);
  }
});
