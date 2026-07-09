import { z } from "zod";
import { handleCors, ok, err } from "../../_shared/response.ts";
import { requireAuth } from "../../_shared/auth.ts";
import { createAdminClient } from "../../_shared/supabase.ts";

const RequestSchema = z.object({
  token: z.string().min(1),
});

Deno.serve(async (req: Request) => {
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;

  if (req.method !== "POST" && req.method !== "DELETE") {
    return err("Method not allowed", 405);
  }

  try {
    const user = await requireAuth(req);
    const body = await req.json();
    const data = RequestSchema.parse(body);

    const supabaseAdmin = createAdminClient();

    const { error: deleteError } = await supabaseAdmin
      .from("push_tokens")
      .delete()
      .eq("user_id", user.id)
      .eq("token", data.token);

    if (deleteError) throw deleteError;

    return ok({ unregistered: true });
  } catch (e: unknown) {
    const error = e instanceof Error ? e : new Error(String(e));
    return err(
      error.message || "Internal Server Error",
      error instanceof z.ZodError ? 400 : 500,
    );
  }
});
