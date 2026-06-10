import type { Context } from "hono";
import { HTTPException } from "hono/http-exception";
import type { z } from "zod";

function fail(error: z.ZodError): never {
  const detail = error.issues
    .map((i) => (i.path.length ? `${i.path.join(".")}: ${i.message}` : i.message))
    .join("; ");
  throw new HTTPException(400, { message: detail });
}

export async function parseJson<S extends z.ZodTypeAny>(
  c: Context,
  schema: S
): Promise<z.output<S>> {
  let body: unknown;
  try {
    body = await c.req.json();
  } catch {
    throw new HTTPException(400, { message: "Invalid JSON body" });
  }
  const result = schema.safeParse(body);
  if (!result.success) fail(result.error);
  return result.data;
}

export function parseQuery<S extends z.ZodTypeAny>(
  c: Context,
  schema: S
): z.output<S> {
  const result = schema.safeParse(c.req.query());
  if (!result.success) fail(result.error);
  return result.data;
}
