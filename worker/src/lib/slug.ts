import { eq } from "drizzle-orm";
import type { DrizzleD1Database } from "drizzle-orm/d1";
import { entities } from "../db/schema";

export const SLUG_PATTERN = /^[a-z0-9]+(-[a-z0-9]+)*$/;

export function slugify(name: string): string {
  const slug = name
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
  return slug || "entity";
}

/** Returns `base`, or `base-2`, `base-3`… if taken. */
export async function uniqueSlug(
  db: DrizzleD1Database,
  base: string
): Promise<string> {
  let candidate = base;
  for (let n = 2; ; n++) {
    const existing = await db
      .select({ id: entities.id })
      .from(entities)
      .where(eq(entities.slug, candidate))
      .get();
    if (!existing) return candidate;
    candidate = `${base}-${n}`;
  }
}
