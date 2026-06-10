import { eq } from "drizzle-orm";
import type { DrizzleD1Database } from "drizzle-orm/d1";
import { HTTPException } from "hono/http-exception";
import { entities } from "../db/schema";

/**
 * `metadata.era` on events and lore must match the slug of an existing
 * `lore` entity with `metadata.category: "era"` — one typo would silently
 * split the timeline grouping.
 */
export async function validateEra(
  db: DrizzleD1Database,
  type: string,
  metadata: Record<string, unknown> | undefined
): Promise<void> {
  if (type !== "event" && type !== "lore") return;
  const era = metadata?.era;
  if (era === undefined || era === null) return;
  if (typeof era === "string") {
    const match = await db
      .select({ type: entities.type, metadata: entities.metadata })
      .from(entities)
      .where(eq(entities.slug, era))
      .get();
    if (
      match &&
      match.type === "lore" &&
      JSON.parse(match.metadata).category === "era"
    ) {
      return;
    }
  }
  throw new HTTPException(422, {
    message: `Unknown era "${String(era)}" — metadata.era must match the slug of a lore entity with metadata.category "era"`,
  });
}
