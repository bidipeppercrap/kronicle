import { and, desc, eq, notInArray } from "drizzle-orm";
import type { DrizzleD1Database } from "drizzle-orm/d1";
import { nanoid } from "nanoid";
import { entityRevisions } from "../db/schema";
import { now } from "./util";

const KEEP = 20;
/** Saves within this window coalesce into the previous snapshot — the editor
 * autosaves every ~2s pause, and 20 near-identical states would make the cap
 * worthless. The first save of a burst captures the pre-burst prose. */
const COALESCE_MS = 10 * 60 * 1000;

export async function snapshotRevision(
  db: DrizzleD1Database,
  entityId: string,
  priorContent: string,
  opts: { force?: boolean } = {}
): Promise<void> {
  if (!opts.force) {
    const newest = await db
      .select({ created_at: entityRevisions.created_at })
      .from(entityRevisions)
      .where(eq(entityRevisions.entity_id, entityId))
      .orderBy(desc(entityRevisions.created_at))
      .limit(1)
      .get();
    if (newest && Date.now() - Date.parse(newest.created_at) < COALESCE_MS) {
      return;
    }
  }

  await db
    .insert(entityRevisions)
    .values({
      id: nanoid(),
      entity_id: entityId,
      content: priorContent,
      created_at: now(),
    })
    .run();

  // Prune beyond the newest KEEP for this entity.
  const keepIds = db
    .select({ id: entityRevisions.id })
    .from(entityRevisions)
    .where(eq(entityRevisions.entity_id, entityId))
    .orderBy(desc(entityRevisions.created_at))
    .limit(KEEP);
  await db
    .delete(entityRevisions)
    .where(
      and(
        eq(entityRevisions.entity_id, entityId),
        notInArray(entityRevisions.id, keepIds)
      )
    )
    .run();
}
