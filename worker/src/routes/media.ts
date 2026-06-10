import { eq } from "drizzle-orm";
import { drizzle } from "drizzle-orm/d1";
import { Hono } from "hono";
import { HTTPException } from "hono/http-exception";
import { media } from "../db/schema";
import { requireEntity } from "../lib/resolve";
import { now } from "../lib/util";
import type { Bindings } from "../types";

const app = new Hono<{ Bindings: Bindings }>();

const MEDIA_TYPES = ["portrait", "illustration", "reference", "logo"];

app.get("/entities/:id/media", async (c) => {
  const db = drizzle(c.env.DB);
  const entity = await requireEntity(db, c.req.param("id"));
  const rows = await db
    .select()
    .from(media)
    .where(eq(media.entity_id, entity.id))
    .all();
  return c.json(rows);
});

app.get("/media/:id/file", async (c) => {
  const db = drizzle(c.env.DB);
  const id = c.req.param("id");
  const row = await db.select().from(media).where(eq(media.id, id)).get();
  if (!row) {
    throw new HTTPException(404, { message: `Media not found: ${id}` });
  }
  const object = await c.env.MEDIA.get(row.r2_key);
  if (!object) {
    throw new HTTPException(404, { message: `Object missing in R2: ${id}` });
  }
  return new Response(object.body, {
    headers: {
      "Content-Type":
        object.httpMetadata?.contentType ?? "application/octet-stream",
      "Content-Length": String(object.size),
      ETag: object.httpEtag,
      "Cache-Control": "private, max-age=3600",
    },
  });
});

app.post("/media", async (c) => {
  const db = drizzle(c.env.DB);
  const body = await c.req.parseBody();

  const file = body.file;
  if (!(file instanceof File)) {
    throw new HTTPException(400, { message: "Multipart field 'file' is required" });
  }
  if (typeof body.entity_id !== "string" || !body.entity_id) {
    throw new HTTPException(400, { message: "Field 'entity_id' is required" });
  }
  const mediaType = body.media_type;
  if (typeof mediaType !== "string" || !MEDIA_TYPES.includes(mediaType)) {
    throw new HTTPException(400, {
      message: `Field 'media_type' must be one of: ${MEDIA_TYPES.join(", ")}`,
    });
  }
  const entity = await requireEntity(db, body.entity_id);

  const id = crypto.randomUUID();
  const safeName =
    file.name.replace(/[^A-Za-z0-9._-]+/g, "-").replace(/^-+|-+$/g, "") ||
    "file";
  const r2Key = `media/${id}/${safeName}`;

  await c.env.MEDIA.put(r2Key, await file.arrayBuffer(), {
    httpMetadata: {
      contentType: file.type || "application/octet-stream",
    },
  });

  const row = {
    id,
    entity_id: entity.id,
    r2_key: r2Key,
    media_type: mediaType,
    alt_text: typeof body.alt_text === "string" ? body.alt_text : null,
    created_at: now(),
  };
  await db.insert(media).values(row).run();
  return c.json(row, 201);
});

app.delete("/media/:id", async (c) => {
  const db = drizzle(c.env.DB);
  const id = c.req.param("id");
  const row = await db.select().from(media).where(eq(media.id, id)).get();
  if (!row) {
    throw new HTTPException(404, { message: `Media not found: ${id}` });
  }
  await c.env.MEDIA.delete(row.r2_key);
  await db.delete(media).where(eq(media.id, id)).run();
  return c.body(null, 204);
});

export default app;
