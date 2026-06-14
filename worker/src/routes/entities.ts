import { and, count, desc, eq, like, ne, or, sql } from "drizzle-orm";
import { drizzle } from "drizzle-orm/d1";
import { Hono } from "hono";
import { HTTPException } from "hono/http-exception";
import { nanoid } from "nanoid";
import { z } from "zod";
import {
  ENTITY_TYPES,
  STATUSES,
  entities,
  entityRevisions,
  media,
  relationships,
} from "../db/schema";
import { validateEra } from "../lib/era";
import { requireEntity } from "../lib/resolve";
import { snapshotRevision } from "../lib/revisions";
import { SLUG_PATTERN, slugify, uniqueSlug } from "../lib/slug";
import { now, serialize } from "../lib/util";
import { parseJson, parseQuery } from "../lib/validate";
import type { Bindings } from "../types";

const app = new Hono<{ Bindings: Bindings }>();

// metadata is freeform, except tags: a flat array of non-empty strings,
// trimmed and deduped so the ?tag= filter matches exactly.
const metadataSchema = z
  .record(z.unknown())
  .superRefine((m, ctx) => {
    if (m.tags === undefined) return;
    if (
      !Array.isArray(m.tags) ||
      m.tags.some((t) => typeof t !== "string" || !t.trim())
    ) {
      ctx.addIssue({
        code: "custom",
        path: ["tags"],
        message: "tags must be an array of non-empty strings",
      });
    }
  })
  .transform((m) =>
    Array.isArray(m.tags)
      ? { ...m, tags: [...new Set(m.tags.map((t) => String(t).trim()))] }
      : m
  );

const createSchema = z.object({
  name: z.string().trim().min(1),
  type: z.enum(ENTITY_TYPES).default("lore"),
  status: z.enum(STATUSES).default("stub"),
  slug: z.string().regex(SLUG_PATTERN, "must be lowercase-kebab").optional(),
  parent_id: z.string().nullish(),
  summary: z.string().default(""),
  content: z.string().default(""),
  metadata: metadataSchema.default({}),
});

const updateSchema = z
  .object({
    name: z.string().trim().min(1),
    type: z.enum(ENTITY_TYPES),
    status: z.enum(STATUSES),
    slug: z.string().regex(SLUG_PATTERN, "must be lowercase-kebab"),
    parent_id: z.string().nullable(),
    summary: z.string(),
    content: z.string(),
    metadata: metadataSchema,
  })
  .partial();

const listQuerySchema = z.object({
  type: z.enum(ENTITY_TYPES).optional(),
  status: z.enum(STATUSES).optional(),
  parent_id: z.string().optional(),
  tag: z.string().trim().min(1).optional(),
  search: z.string().optional(),
  limit: z.coerce.number().int().min(1).max(200).default(50),
  offset: z.coerce.number().int().min(0).default(0),
});

function wikilinkTokens(slug: string) {
  return { exact: `[[${slug}]]`, aliased: `[[${slug}|` };
}

app.get("/entities", async (c) => {
  const db = drizzle(c.env.DB);
  const q = parseQuery(c, listQuerySchema);

  const conds = [];
  if (q.type) conds.push(eq(entities.type, q.type));
  if (q.status) conds.push(eq(entities.status, q.status));
  if (q.parent_id) conds.push(eq(entities.parent_id, q.parent_id));
  if (q.tag) {
    // Exact match against the metadata.tags array — json_each yields no
    // rows when the entity has no tags, so untagged entities just drop out.
    conds.push(
      sql`exists (select 1 from json_each(${entities.metadata}, '$.tags') where json_each.value = ${q.tag})`
    );
  }
  if (q.search) {
    const pattern = `%${q.search}%`;
    conds.push(
      or(
        like(entities.name, pattern),
        like(entities.summary, pattern),
        like(entities.content, pattern)
      )
    );
  }
  const where = conds.length ? and(...conds) : undefined;

  // When searching, rank by where the term hit — name matches are the most
  // specific, then summary, then a bare content mention. LIKE is
  // case-insensitive for ASCII, so the bare term acts as an exact-name check
  // and the prefix pattern catches "starts with". updated_at only breaks ties.
  const orderBy = q.search
    ? [
        sql`case
          when ${entities.name} like ${q.search} then 0
          when ${entities.name} like ${`${q.search}%`} then 1
          when ${entities.name} like ${`%${q.search}%`} then 2
          when ${entities.summary} like ${`%${q.search}%`} then 3
          else 4
        end`,
        desc(entities.updated_at),
      ]
    : [desc(entities.updated_at)];

  const items = await db
    .select()
    .from(entities)
    .where(where)
    .orderBy(...orderBy)
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

app.get("/entities/:id", async (c) => {
  const db = drizzle(c.env.DB);
  const entity = await requireEntity(db, c.req.param("id"));

  const rels = await db
    .select()
    .from(relationships)
    .where(
      or(
        eq(relationships.source_id, entity.id),
        eq(relationships.target_id, entity.id)
      )
    )
    .all();
  const mediaRows = await db
    .select()
    .from(media)
    .where(eq(media.entity_id, entity.id))
    .all();

  return c.json({
    ...serialize(entity),
    relationships: rels.map(serialize),
    media: mediaRows,
  });
});

app.post("/entities", async (c) => {
  const db = drizzle(c.env.DB);
  const body = await parseJson(c, createSchema);

  let parentId: string | null = null;
  if (body.parent_id) {
    parentId = (await requireEntity(db, body.parent_id)).id;
  }
  await validateEra(db, body.type, body.metadata);

  let slug: string;
  if (body.slug) {
    const taken = await db
      .select({ id: entities.id })
      .from(entities)
      .where(eq(entities.slug, body.slug))
      .get();
    if (taken) {
      throw new HTTPException(409, {
        message: `Slug "${body.slug}" is already in use`,
      });
    }
    slug = body.slug;
  } else {
    slug = await uniqueSlug(db, slugify(body.name));
  }

  const ts = now();
  const row = {
    id: nanoid(),
    slug,
    type: body.type,
    parent_id: parentId,
    name: body.name,
    status: body.status,
    summary: body.summary,
    content: body.content,
    metadata: JSON.stringify(body.metadata),
    created_at: ts,
    updated_at: ts,
  };
  await db.insert(entities).values(row).run();
  return c.json(serialize(row), 201);
});

app.put("/entities/:id", async (c) => {
  const db = drizzle(c.env.DB);
  const current = await requireEntity(db, c.req.param("id"));
  const body = await parseJson(c, updateSchema);

  const type = body.type ?? current.type;
  const metadata = body.metadata ?? JSON.parse(current.metadata);
  await validateEra(db, type, metadata);

  let parentId = current.parent_id;
  if (body.parent_id !== undefined) {
    if (body.parent_id === null) {
      parentId = null;
    } else {
      const parent = await requireEntity(db, body.parent_id);
      if (parent.id === current.id) {
        throw new HTTPException(400, {
          message: "An entity cannot be its own parent",
        });
      }
      parentId = parent.id;
    }
  }

  const ts = now();
  let slug = current.slug;
  let content = body.content ?? current.content;
  const rewrites = [];

  if (body.slug && body.slug !== current.slug) {
    const taken = await db
      .select({ id: entities.id })
      .from(entities)
      .where(eq(entities.slug, body.slug))
      .get();
    if (taken) {
      throw new HTTPException(409, {
        message: `Slug "${body.slug}" is already in use`,
      });
    }
    slug = body.slug;

    // Rewrite [[old-slug]] / [[old-slug|…]] across all other entities'
    // content in the same batch as the rename — links can never dangle.
    const old = wikilinkTokens(current.slug);
    const next = wikilinkTokens(slug);
    const mentions = await db
      .select({ id: entities.id, content: entities.content })
      .from(entities)
      .where(
        and(
          ne(entities.id, current.id),
          or(
            like(entities.content, `%${old.exact}%`),
            like(entities.content, `%${old.aliased}%`)
          )
        )
      )
      .all();
    for (const mention of mentions) {
      const rewritten = mention.content
        .replaceAll(old.exact, next.exact)
        .replaceAll(old.aliased, next.aliased);
      rewrites.push(
        db
          .update(entities)
          .set({ content: rewritten })
          .where(eq(entities.id, mention.id))
      );
    }
    content = content
      .replaceAll(old.exact, next.exact)
      .replaceAll(old.aliased, next.aliased);
  }

  // The prose safety net: a content-changing save snapshots what it replaces.
  // Mechanical wikilink rewrites from slug renames don't count as prose edits.
  if (body.content !== undefined && body.content !== current.content) {
    await snapshotRevision(db, current.id, current.content);
  }

  const values = {
    name: body.name ?? current.name,
    type,
    status: body.status ?? current.status,
    slug,
    parent_id: parentId,
    summary: body.summary ?? current.summary,
    content,
    metadata: JSON.stringify(metadata),
    updated_at: ts,
  };
  const update = db
    .update(entities)
    .set(values)
    .where(eq(entities.id, current.id));
  if (rewrites.length) {
    await db.batch([update, ...rewrites]);
  } else {
    await update.run();
  }

  return c.json(
    serialize({ id: current.id, created_at: current.created_at, ...values })
  );
});

app.get("/entities/:id/revisions", async (c) => {
  const db = drizzle(c.env.DB);
  const entity = await requireEntity(db, c.req.param("id"));

  const items = await db
    .select()
    .from(entityRevisions)
    .where(eq(entityRevisions.entity_id, entity.id))
    .orderBy(desc(entityRevisions.created_at))
    .limit(20)
    .all();

  return c.json({ items });
});

app.post("/entities/:id/revisions/:revId/restore", async (c) => {
  const db = drizzle(c.env.DB);
  const entity = await requireEntity(db, c.req.param("id"));

  const revision = await db
    .select()
    .from(entityRevisions)
    .where(
      and(
        eq(entityRevisions.id, c.req.param("revId")),
        eq(entityRevisions.entity_id, entity.id)
      )
    )
    .get();
  if (!revision) {
    throw new HTTPException(404, { message: "Revision not found" });
  }

  // The restore itself must be undoable: snapshot what it overwrites,
  // bypassing the coalescing window.
  if (revision.content !== entity.content) {
    await snapshotRevision(db, entity.id, entity.content, { force: true });
  }

  const values = { content: revision.content, updated_at: now() };
  await db.update(entities).set(values).where(eq(entities.id, entity.id)).run();

  return c.json(serialize({ ...entity, ...values }));
});

app.delete("/entities/:id", async (c) => {
  const db = drizzle(c.env.DB);
  const entity = await requireEntity(db, c.req.param("id"));

  const child = await db
    .select({ id: entities.id })
    .from(entities)
    .where(eq(entities.parent_id, entity.id))
    .get();
  if (child) {
    throw new HTTPException(409, {
      message: "Entity has children — reassign or delete them first",
    });
  }

  const mediaRows = await db
    .select({ r2_key: media.r2_key })
    .from(media)
    .where(eq(media.entity_id, entity.id))
    .all();
  if (mediaRows.length) {
    await c.env.MEDIA.delete(mediaRows.map((m) => m.r2_key));
  }

  await db.batch([
    db
      .delete(relationships)
      .where(
        or(
          eq(relationships.source_id, entity.id),
          eq(relationships.target_id, entity.id)
        )
      ),
    db.delete(media).where(eq(media.entity_id, entity.id)),
    db.delete(entityRevisions).where(eq(entityRevisions.entity_id, entity.id)),
    db.delete(entities).where(eq(entities.id, entity.id)),
  ]);

  return c.body(null, 204);
});

export default app;
