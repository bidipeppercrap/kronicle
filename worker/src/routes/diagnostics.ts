import { drizzle } from "drizzle-orm/d1";
import { Hono } from "hono";
import { entities, relationships } from "../db/schema";
import type { Bindings } from "../types";

const app = new Hono<{ Bindings: Bindings }>();

const STALE_STUB_DAYS = 14;
const WIKILINK = /\[\[([^\]|]+)(?:\|[^\]]*)?\]\]/g;

interface EntityRef {
  id: string;
  slug: string;
  type: string;
  name: string;
  status: string;
  summary: string;
  updated_at: string;
}

function ref(row: EntityRef & { [k: string]: unknown }): EntityRef {
  const { id, slug, type, name, status, summary, updated_at } = row;
  return { id, slug, type, name, status, summary, updated_at };
}

/**
 * Vault health, computed at read time like backlinks — nothing stored:
 * - broken_links: [[slugs]] in prose that match no entity (typos or links
 *   written before the target was captured; renames can't dangle, typing can)
 * - orphans: entities with no relationships, no parent or children, no
 *   mention anywhere, and no outgoing links of their own — disconnected
 *   from the vault's graph entirely
 * - stale_stubs: stubs untouched for two weeks, waiting for triage
 */
app.get("/diagnostics", async (c) => {
  const db = drizzle(c.env.DB);
  const rows = await db
    .select({
      id: entities.id,
      slug: entities.slug,
      type: entities.type,
      name: entities.name,
      status: entities.status,
      parent_id: entities.parent_id,
      summary: entities.summary,
      content: entities.content,
      updated_at: entities.updated_at,
    })
    .from(entities)
    .all();
  const rels = await db
    .select({
      source_id: relationships.source_id,
      target_id: relationships.target_id,
    })
    .from(relationships)
    .all();

  const slugs = new Set(rows.map((r) => r.slug));
  const connected = new Set<string>();
  for (const r of rels) {
    connected.add(r.source_id);
    connected.add(r.target_id);
  }
  const hasChildren = new Set(rows.map((r) => r.parent_id).filter(Boolean));

  const mentioned = new Set<string>();
  const linksOut = new Set<string>();
  const broken_links: Array<EntityRef & { missing_slug: string; count: number }> = [];
  for (const row of rows) {
    const missing = new Map<string, number>();
    for (const match of row.content.matchAll(WIKILINK)) {
      const slug = match[1].trim();
      if (slugs.has(slug)) {
        mentioned.add(slug);
        linksOut.add(row.id);
      } else {
        missing.set(slug, (missing.get(slug) ?? 0) + 1);
      }
    }
    for (const [missing_slug, count] of missing) {
      broken_links.push({ ...ref(row), missing_slug, count });
    }
  }

  const orphans = rows
    .filter(
      (r) =>
        !connected.has(r.id) &&
        !mentioned.has(r.slug) &&
        !linksOut.has(r.id) &&
        !r.parent_id &&
        !hasChildren.has(r.id)
    )
    .map(ref);

  const cutoff = new Date(
    Date.now() - STALE_STUB_DAYS * 24 * 60 * 60 * 1000
  ).toISOString();
  const stale_stubs = rows
    .filter((r) => r.status === "stub" && r.updated_at < cutoff)
    .sort((a, b) => a.updated_at.localeCompare(b.updated_at))
    .map(ref);

  return c.json({ broken_links, orphans, stale_stubs });
});

export default app;
