import { and, count, desc, eq, like, or, sql } from "drizzle-orm";
import { drizzle } from "drizzle-orm/d1";
import { Hono } from "hono";
import { z } from "zod";
import { ENTITY_TYPES, entities } from "../db/schema";
import { serialize } from "../lib/util";
import { parseQuery } from "../lib/validate";
import type { Bindings } from "../types";

const app = new Hono<{ Bindings: Bindings }>();

const searchQuerySchema = z.object({
  q: z.string().trim().min(1, "query parameter 'q' is required"),
  type: z.enum(ENTITY_TYPES).optional(),
  limit: z.coerce.number().int().min(1).max(200).default(50),
  offset: z.coerce.number().int().min(0).default(0),
});

app.get("/search", async (c) => {
  const db = drizzle(c.env.DB);
  const q = parseQuery(c, searchQuerySchema);

  const pattern = `%${q.q}%`;
  const conds = [
    or(
      like(entities.name, pattern),
      like(entities.summary, pattern),
      like(entities.content, pattern)
    ),
  ];
  if (q.type) conds.push(eq(entities.type, q.type));
  const where = and(...conds);

  // Rank by where the term hit — name matches are the most specific (exact,
  // then prefix, then anywhere), then summary, then a bare content mention.
  // LIKE is case-insensitive for ASCII, so the bare term acts as an exact-name
  // check. updated_at only breaks ties within the same relevance tier.
  const relevance = sql`case
    when ${entities.name} like ${q.q} then 0
    when ${entities.name} like ${`${q.q}%`} then 1
    when ${entities.name} like ${pattern} then 2
    when ${entities.summary} like ${pattern} then 3
    else 4
  end`;

  const items = await db
    .select()
    .from(entities)
    .where(where)
    .orderBy(relevance, desc(entities.updated_at))
    .limit(q.limit)
    .offset(q.offset)
    .all();
  const totalRow = await db
    .select({ total: count() })
    .from(entities)
    .where(where)
    .get();

  return c.json({
    items: items.map(serialize),
    total: totalRow?.total ?? 0,
    limit: q.limit,
    offset: q.offset,
  });
});

export default app;
