import { z } from "zod";
import { handleCors, ok, err } from "../../_shared/response.ts";
import { requireAuth } from "../../_shared/auth.ts";
import { createAdminClient } from "../../_shared/supabase.ts";

const RequestSchema = z.object({
  token: z.string().min(1),
  platform: z.enum(["ios", "android", "web"]),
});

Deno.serve(async (req: Request) => {
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;

  try {
    const user = await requireAuth(req);
    const body = await req.json();
    const data = RequestSchema.parse(body);

    const supabaseAdmin = createAdminClient();

    const { error: insertError } = await supabaseAdmin
      .from("push_tokens")
      .upsert(
        {
          user_id: user.id,
          token: data.token,
          platform: data.platform,
        },
        { onConflict: "user_id,token" },
      );

    if (insertError) throw insertError;

    return ok({ registered: true });
  } catch (e: unknown) {
    const error = e instanceof Error ? e : new Error(String(e));
    return err(
      error.message || "Internal Server Error",
      error instanceof z.ZodError ? 400 : 500,
    );
  }
});
