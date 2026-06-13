import { count, eq } from "drizzle-orm";
import { drizzle } from "drizzle-orm/d1";
import type { BatchItem } from "drizzle-orm/batch";
import { type Unzipped, strFromU8, unzipSync } from "fflate";
import { Hono } from "hono";
import { HTTPException } from "hono/http-exception";
import {
  entities,
  entityRevisions,
  media,
  relationships,
  settings,
} from "../db/schema";
import type { Manifest } from "../lib/backup";
import { AI_SETTING_KEYS } from "../lib/settings";
import { now } from "../lib/util";
import type { Bindings } from "../types";

const app = new Hono<{ Bindings: Bindings }>();

function bad(message: string): never {
  throw new HTTPException(400, { message });
}

/**
 * POST /api/import?replace=true — restore a kronicle export zip into D1 + R2.
 * Driven entirely by kronicle.json (the Markdown files are ignored). Refuses to
 * touch a non-empty vault unless ?replace=true, which wipes first.
 */
app.post("/import", async (c) => {
  const db = drizzle(c.env.DB);
  const replace = c.req.query("replace") === "true";

  // The web proxy posts the raw zip bytes; also accept a multipart 'file' field.
  const contentType = c.req.header("content-type") ?? "";
  let bytes: Uint8Array;
  if (contentType.includes("multipart/form-data")) {
    const form = await c.req.parseBody();
    if (!(form.file instanceof File)) bad("Multipart field 'file' is required");
    bytes = new Uint8Array(await (form.file as File).arrayBuffer());
  } else {
    bytes = new Uint8Array(await c.req.arrayBuffer());
  }
  if (!bytes.length) bad("Empty request body");

  let unzipped: Unzipped;
  try {
    unzipped = unzipSync(bytes);
  } catch {
    bad("Not a valid zip file");
  }

  const manifestBytes = unzipped!["kronicle.json"];
  if (!manifestBytes) bad("Zip is missing kronicle.json");
  let manifest: Manifest;
  try {
    manifest = JSON.parse(strFromU8(manifestBytes));
  } catch {
    bad("kronicle.json is not valid JSON");
  }
  if (!Array.isArray(manifest!.entities)) bad("kronicle.json is malformed");

  const existing = await db.select({ n: count() }).from(entities).get();
  if ((existing?.n ?? 0) > 0 && !replace) {
    throw new HTTPException(409, {
      message: "Vault is not empty. Re-run with ?replace=true to overwrite it.",
    });
  }

  if (replace) {
    const existingMedia = await db.select({ r2_key: media.r2_key }).from(media).all();
    if (existingMedia.length) {
      await c.env.MEDIA.delete(existingMedia.map((m) => m.r2_key));
    }
    await db.batch([
      db.delete(relationships),
      db.delete(media),
      db.delete(entityRevisions),
      db.delete(entities),
    ]);
  }

  // Restore media blobs to R2 before the DB rows that reference them.
  for (const m of manifest!.media ?? []) {
    const blob = unzipped![m.r2_key];
    if (!blob) continue; // row kept; file just absent (export already skips gaps)
    await c.env.MEDIA.put(m.r2_key, blob, {
      httpMetadata: { contentType: m.content_type ?? "application/octet-stream" },
    });
  }

  const stmts: BatchItem<"sqlite">[] = [];

  // Insert entities with parent_id cleared, then re-link in a second pass — this
  // sidesteps any self-referential FK ordering issue regardless of array order.
  const relink: BatchItem<"sqlite">[] = [];
  for (const e of manifest!.entities) {
    stmts.push(
      db.insert(entities).values({
        id: e.id,
        slug: e.slug,
        type: e.type as never,
        parent_id: null,
        name: e.name,
        status: e.status as never,
        summary: e.summary ?? "",
        content: e.content ?? "",
        metadata: JSON.stringify(e.metadata ?? {}),
        created_at: e.created_at,
        updated_at: e.updated_at,
      })
    );
    if (e.parent_id) {
      relink.push(
        db
          .update(entities)
          .set({ parent_id: e.parent_id })
          .where(eq(entities.id, e.id))
      );
    }
  }
  stmts.push(...relink);

  for (const r of manifest!.relationships ?? []) {
    stmts.push(
      db.insert(relationships).values({
        id: r.id,
        source_id: r.source_id,
        target_id: r.target_id,
        type: r.type,
        label: r.label ?? null,
        metadata: JSON.stringify(r.metadata ?? {}),
        created_at: r.created_at,
      })
    );
  }
  for (const rev of manifest!.revisions ?? []) {
    stmts.push(
      db.insert(entityRevisions).values({
        id: rev.id,
        entity_id: rev.entity_id,
        content: rev.content,
        created_at: rev.created_at,
      })
    );
  }
  for (const m of manifest!.media ?? []) {
    stmts.push(
      db.insert(media).values({
        id: m.id,
        entity_id: m.entity_id,
        r2_key: m.r2_key,
        media_type: m.media_type,
        alt_text: m.alt_text ?? null,
        created_at: m.created_at,
      })
    );
  }
  const ts = now();
  for (const [key, value] of Object.entries(manifest!.settings ?? {})) {
    if (key === AI_SETTING_KEYS.apiKey) continue; // never import a secret key
    stmts.push(
      db
        .insert(settings)
        .values({ key, value, updated_at: ts })
        .onConflictDoUpdate({ target: settings.key, set: { value, updated_at: ts } })
    );
  }

  if (stmts.length) {
    await db.batch(stmts as [BatchItem<"sqlite">, ...BatchItem<"sqlite">[]]);
  }

  return c.json({
    imported: {
      entities: manifest!.entities.length,
      relationships: (manifest!.relationships ?? []).length,
      revisions: (manifest!.revisions ?? []).length,
      media: (manifest!.media ?? []).length,
    },
  });
});

export default app;
