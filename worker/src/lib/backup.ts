/**
 * Shared types and helpers for the export/import round-trip (DESIGN.md,
 * "Export (Portability)"). The zip carries two payloads for two audiences:
 *
 *   kronicle.json   — the lossless manifest; import reads ONLY this.
 *   <type>/<slug>.md — one human-/Obsidian-facing Markdown file per entity.
 *   media/<…>       — raw bytes for every media object.
 *
 * Because import is driven by kronicle.json, we never parse the Markdown back —
 * the frontmatter writer below is a one-way convenience, not a contract.
 */

export const BACKUP_VERSION = 1;

export interface ManifestEntity {
  id: string;
  slug: string;
  type: string;
  parent_id: string | null;
  name: string;
  status: string;
  summary: string;
  content: string;
  metadata: Record<string, unknown>;
  created_at: string;
  updated_at: string;
}

export interface ManifestRelationship {
  id: string;
  source_id: string;
  target_id: string;
  type: string;
  label: string | null;
  metadata: Record<string, unknown>;
  created_at: string;
}

export interface ManifestRevision {
  id: string;
  entity_id: string;
  content: string;
  created_at: string;
}

export interface ManifestMedia {
  id: string;
  entity_id: string;
  r2_key: string;
  media_type: string;
  alt_text: string | null;
  created_at: string;
  /** Captured from R2 at export time so import can restore the right type. */
  content_type: string | null;
}

export interface Manifest {
  version: number;
  exported_at: string;
  entities: ManifestEntity[];
  relationships: ManifestRelationship[];
  revisions: ManifestRevision[];
  media: ManifestMedia[];
  settings: Record<string, string>;
}

// JSON scalars/arrays are valid YAML flow scalars, so JSON.stringify gives us a
// correctly quoted-and-escaped frontmatter value for free — no YAML lib needed.
function yaml(value: unknown): string {
  return JSON.stringify(value);
}

/** Render one entity as a Markdown file: YAML frontmatter + prose. */
export function entityMarkdown(
  e: ManifestEntity,
  slugById: Map<string, string>
): string {
  const meta = e.metadata ?? {};
  const lines = [
    `slug: ${yaml(e.slug)}`,
    `type: ${yaml(e.type)}`,
    `name: ${yaml(e.name)}`,
    `status: ${yaml(e.status)}`,
  ];
  if (e.summary) lines.push(`summary: ${yaml(e.summary)}`);
  if (Array.isArray(meta.tags) && meta.tags.length) {
    lines.push(`tags: ${yaml(meta.tags)}`);
  }
  if (typeof meta.era === "string") lines.push(`era: ${yaml(meta.era)}`);
  if (e.parent_id && slugById.has(e.parent_id)) {
    lines.push(`parent: ${yaml(slugById.get(e.parent_id))}`);
  }
  lines.push(`created_at: ${yaml(e.created_at)}`);
  lines.push(`updated_at: ${yaml(e.updated_at)}`);
  return `---\n${lines.join("\n")}\n---\n\n${e.content}\n`;
}
