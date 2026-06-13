import { and, asc, eq, sql } from "drizzle-orm";
import { drizzle } from "drizzle-orm/d1";
import { Hono } from "hono";
import { z } from "zod";
import { STATUSES, entities } from "../db/schema";
import { serialize } from "../lib/util";
import { parseQuery } from "../lib/validate";
import type { Bindings } from "../types";

const app = new Hono<{ Bindings: Bindings }>();

const querySchema = z.object({
  era: z.string().trim().min(1).optional(),
  status: z.enum(STATUSES).optional(),
});

const orderIndex = sql`json_extract(${entities.metadata}, '$.order_index')`;

/**
 * The timeline is chronological first (DESIGN.md): every `event` sorted by
 * `metadata.order_index` ascending. Events with no `order_index` have no
 * fixed position yet, so they sort last. `era` is an optional grouping band
 * the client draws as the stream crosses it — never a filter the timeline
 * needs — so the feed works with no eras at all. The era `lore` entities ride
 * along so the client can label bands by name without a second round-trip.
 */
app.get("/timeline", async (c) => {
  const db = drizzle(c.env.DB);
  const q = parseQuery(c, querySchema);

  const conds = [eq(entities.type, "event")];
  if (q.status) conds.push(eq(entities.status, q.status));
  if (q.era) {
    conds.push(sql`json_extract(${entities.metadata}, '$.era') = ${q.era}`);
  }

  const items = await db
    .select()
    .from(entities)
    .where(and(...conds))
    // NULLs sort first in SQLite ascending; push the position-less events last.
    .orderBy(sql`${orderIndex} is null`, asc(orderIndex))
    .all();

  const eras = await db
    .select({ id: entities.id, slug: entities.slug, name: entities.name })
    .from(entities)
    .where(
      and(
        eq(entities.type, "lore"),
        sql`json_extract(${entities.metadata}, '$.category') = 'era'`
      )
    )
    .orderBy(asc(entities.name))
    .all();

  return c.json({ items: items.map(serialize), eras });
});

export default app;
