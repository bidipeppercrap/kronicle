import { and, count, desc, eq, like, or } from "drizzle-orm";
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

  const items = await db
    .select()
    .from(entities)
    .where(where)
    .orderBy(desc(entities.updated_at))
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
