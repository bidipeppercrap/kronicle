import { eq } from "drizzle-orm";
import type { DrizzleD1Database } from "drizzle-orm/d1";
import { HTTPException } from "hono/http-exception";
import { entities } from "../db/schema";

export type EntityRow = typeof entities.$inferSelect;

/** Look up an entity by opaque id first, then by slug. */
export async function resolveEntity(
  db: DrizzleD1Database,
  idOrSlug: string
): Promise<EntityRow | undefined> {
  const byId = await db
    .select()
    .from(entities)
    .where(eq(entities.id, idOrSlug))
    .get();
  if (byId) return byId;
  return db.select().from(entities).where(eq(entities.slug, idOrSlug)).get();
}

export async function requireEntity(
  db: DrizzleD1Database,
  idOrSlug: string
): Promise<EntityRow> {
  const entity = await resolveEntity(db, idOrSlug);
  if (!entity) {
    throw new HTTPException(404, { message: `Entity not found: ${idOrSlug}` });
  }
  return entity;
}
