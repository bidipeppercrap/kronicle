import { drizzle } from "drizzle-orm/d1";
import { type Zippable, strToU8, zipSync } from "fflate";
import { Hono } from "hono";
import {
  entities,
  entityRevisions,
  media,
  relationships,
  settings,
} from "../db/schema";
import {
  BACKUP_VERSION,
  type Manifest,
  type ManifestMedia,
  entityMarkdown,
} from "../lib/backup";
import { AI_SETTING_KEYS } from "../lib/settings";
import { now, serialize } from "../lib/util";
import type { Bindings } from "../types";

const app = new Hono<{ Bindings: Bindings }>();

/**
 * GET /api/export — the whole vault as a downloadable zip: a lossless
 * kronicle.json manifest, one Markdown file per entity, and every media file.
 * The AI provider key is a secret and is deliberately left out of the export.
 */
app.get("/export", async (c) => {
  const db = drizzle(c.env.DB);

  const entityRows = await db.select().from(entities).all();
  const relRows = await db.select().from(relationships).all();
  const revRows = await db.select().from(entityRevisions).all();
  const mediaRows = await db.select().from(media).all();
  const settingRows = await db.select().from(settings).all();

  const files: Zippable = {};
  const slugById = new Map(entityRows.map((e) => [e.id, e.slug]));

  // Pull every media object from R2 first, so the manifest only lists files we
  // actually managed to bundle (a missing R2 object is skipped, not fatal).
  const mediaManifest: ManifestMedia[] = [];
  for (const m of mediaRows) {
    const object = await c.env.MEDIA.get(m.r2_key);
    if (!object) continue;
    files[m.r2_key] = new Uint8Array(await object.arrayBuffer());
    mediaManifest.push({
      ...m,
      content_type: object.httpMetadata?.contentType ?? null,
    });
  }

  const settingsObj: Record<string, string> = {};
  for (const s of settingRows) {
    if (s.key === AI_SETTING_KEYS.apiKey) continue; // never export the secret
    settingsObj[s.key] = s.value;
  }

  const manifest: Manifest = {
    version: BACKUP_VERSION,
    exported_at: now(),
    entities: entityRows.map(serialize),
    relationships: relRows.map(serialize),
    revisions: revRows,
    media: mediaManifest,
    settings: settingsObj,
  };

  files["kronicle.json"] = strToU8(JSON.stringify(manifest, null, 2));
  for (const e of manifest.entities) {
    files[`${e.type}/${e.slug}.md`] = strToU8(entityMarkdown(e, slugById));
  }

  const zip = zipSync(files);
  const date = manifest.exported_at.slice(0, 10);
  return new Response(zip, {
    headers: {
      "Content-Type": "application/zip",
      "Content-Disposition": `attachment; filename="kronicle-backup-${date}.zip"`,
    },
  });
});

export default app;
