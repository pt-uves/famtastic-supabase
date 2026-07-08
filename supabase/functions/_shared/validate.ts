import { z } from "zod";

/**
 * Validates JSON request body against a Zod schema.
 * Throws an array of error messages if validation fails.
 */
export const validateBody = async <T extends z.ZodTypeAny>(
  req: Request,
  schema: T
): Promise<z.infer<T>> => {
  try {
    const body = await req.json();
    return schema.parse(body);
  } catch (error) {
    if (error instanceof z.ZodError) {
      throw new Error(error.errors.map((e) => `${e.path.join(".")}: ${e.message}`).join(", "));
    }
    throw new Error("Invalid JSON body");
  }
};
