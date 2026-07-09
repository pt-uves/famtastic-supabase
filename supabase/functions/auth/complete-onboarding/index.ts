import { z } from "zod";
import { handleCors, ok, err } from "../../_shared/response.ts";
import { requireAuth } from "../../_shared/auth.ts";
import { createAdminClient } from "../../_shared/supabase.ts";

const RequestSchema = z.object({
  full_name: z.string().min(1),
  family_name: z.string().min(1),
  avatar_url: z.string().url().optional(),
});

Deno.serve(async (req: Request) => {
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;

  try {
    const user = await requireAuth(req);
    const { full_name, family_name, avatar_url } = await (async () => {
      try {
        const body = await req.json();
        return RequestSchema.parse(body);
      } catch (e) {
        throw new Error(
          e instanceof z.ZodError ? e.errors[0].message : "Invalid JSON body",
        );
      }
    })();

    const supabaseAdmin = createAdminClient();

    // 1. Check if the user already has a family
    const { data: existingFamily, error: familyCheckError } =
      await supabaseAdmin
        .from("families")
        .select("id")
        .eq("owner_id", user.id)
        .maybeSingle();

    if (familyCheckError) throw familyCheckError;

    if (existingFamily) {
      return err("User already owns a family", 409);
    }

    // 2. Update profile
    const { data: profile, error: profileError } = await supabaseAdmin
      .from("profiles")
      .update({ full_name, avatar_url })
      .eq("id", user.id)
      .select()
      .single();

    if (profileError) throw profileError;

    // 3. Create family
    const { data: family, error: familyError } = await supabaseAdmin
      .from("families")
      .insert({ name: family_name, owner_id: user.id })
      .select()
      .single();

    if (familyError) throw familyError;

    return ok({ profile, family });
  } catch (e: unknown) {
    const error = e instanceof Error ? e : new Error(String(e));
    return err(
      error.message || "Internal Server Error",
      error.message.includes("Invalid") ? 400 : 500,
    );
  }
});
