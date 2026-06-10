import { and, eq, like, ne, or } from "drizzle-orm";
import { drizzle } from "drizzle-orm/d1";
import { Hono } from "hono";
import { HTTPException } from "hono/http-exception";
import { z } from "zod";
import { RELATIONSHIP_TYPES, entities, relationships } from "../db/schema";
import { requireEntity } from "../lib/resolve";
import { now, serialize } from "../lib/util";
import { parseJson } from "../lib/validate";
import type { Bindings } from "../types";

const app = new Hono<{ Bindings: Bindings }>();

const createSchema = z.object({
  source_id: z.string().min(1),
  target_id: z.string().min(1),
  type: z.enum(RELATIONSHIP_TYPES),
  label: z.string().nullish(),
  metadata: z.record(z.unknown()).default({}),
});

app.get("/entities/:id/relationships", async (c) => {
  const db = drizzle(c.env.DB);
  const entity = await requireEntity(db, c.req.param("id"));
  const rows = await db
    .select()
    .from(relationships)
    .where(
      or(
        eq(relationships.source_id, entity.id),
        eq(relationships.target_id, entity.id)
      )
    )
    .all();
  return c.json(rows.map(serialize));
});

app.get("/entities/:id/backlinks", async (c) => {
  const db = drizzle(c.env.DB);
  const entity = await requireEntity(db, c.req.param("id"));
  const rows = await db
    .select({
      id: entities.id,
      slug: entities.slug,
      type: entities.type,
      name: entities.name,
      status: entities.status,
      summary: entities.summary,
    })
    .from(entities)
    .where(
      and(
        ne(entities.id, entity.id),
        or(
          like(entities.content, `%[[${entity.slug}]]%`),
          like(entities.content, `%[[${entity.slug}|%`)
        )
      )
    )
    .all();
  return c.json(rows);
});

app.post("/relationships", async (c) => {
  const db = drizzle(c.env.DB);
  const body = await parseJson(c, createSchema);

  const source = await requireEntity(db, body.source_id);
  const target = await requireEntity(db, body.target_id);

  const duplicate = await db
    .select({ id: relationships.id })
    .from(relationships)
    .where(
      and(
        eq(relationships.source_id, source.id),
        eq(relationships.target_id, target.id),
        eq(relationships.type, body.type)
      )
    )
    .get();
  if (duplicate) {
    throw new HTTPException(409, {
      message: `Relationship already exists: ${source.slug} ${body.type} ${target.slug}`,
    });
  }

  const row = {
    id: crypto.randomUUID(),
    source_id: source.id,
    target_id: target.id,
    type: body.type,
    label: body.label ?? null,
    metadata: JSON.stringify(body.metadata),
    created_at: now(),
  };
  await db.insert(relationships).values(row).run();
  return c.json(serialize(row), 201);
});

app.delete("/relationships/:id", async (c) => {
  const db = drizzle(c.env.DB);
  const id = c.req.param("id");
  const row = await db
    .select({ id: relationships.id })
    .from(relationships)
    .where(eq(relationships.id, id))
    .get();
  if (!row) {
    throw new HTTPException(404, { message: `Relationship not found: ${id}` });
  }
  await db.delete(relationships).where(eq(relationships.id, id)).run();
  return c.body(null, 204);
});

export default app;
