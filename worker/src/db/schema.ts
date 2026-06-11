import { sql } from "drizzle-orm";
import {
  check,
  index,
  sqliteTable,
  text,
  uniqueIndex,
  type AnySQLiteColumn,
} from "drizzle-orm/sqlite-core";

export const ENTITY_TYPES = [
  "character",
  "location",
  "faction",
  "lore",
  "story",
  "chapter",
  "event",
  "ability",
] as const;

export const STATUSES = ["stub", "draft", "canon", "rejected"] as const;

export const RELATIONSHIP_TYPES = [
  "born_in",
  "resides_in",
  "member_of",
  "leader_of",
  "possesses",
  "friend_of",
  "rival_of",
  "parent_of",
  "sibling_of",
  "married_to",
  "related_to",
  "appears_in",
  "setting_of",
  "occurs_at",
  "involves",
  "depicts",
  "causes",
  "based_in",
] as const;

export const entities = sqliteTable(
  "entities",
  {
    id: text().primaryKey(),
    slug: text().notNull().unique(),
    type: text({ enum: ENTITY_TYPES }).notNull(),
    parent_id: text().references((): AnySQLiteColumn => entities.id),
    name: text().notNull(),
    status: text({ enum: STATUSES }).notNull().default("stub"),
    summary: text().notNull().default(""),
    content: text().notNull().default(""),
    metadata: text().notNull().default("{}"),
    created_at: text().notNull(),
    updated_at: text().notNull(),
  },
  (t) => [
    index("idx_entities_type_status").on(t.type, t.status),
    index("idx_entities_parent_id").on(t.parent_id),
    check(
      "entities_status_check",
      sql`${t.status} IN ('stub', 'draft', 'canon', 'rejected')`
    ),
  ]
);

export const relationships = sqliteTable(
  "relationships",
  {
    id: text().primaryKey(),
    source_id: text()
      .notNull()
      .references(() => entities.id),
    target_id: text()
      .notNull()
      .references(() => entities.id),
    type: text().notNull(),
    label: text(),
    metadata: text().notNull().default("{}"),
    created_at: text().notNull(),
  },
  (t) => [
    uniqueIndex("uq_relationships_edge").on(t.source_id, t.target_id, t.type),
  ]
);

export const entityRevisions = sqliteTable(
  "entity_revisions",
  {
    id: text().primaryKey(),
    entity_id: text()
      .notNull()
      .references(() => entities.id),
    // The Markdown prose as it was *before* the save that triggered the snapshot.
    content: text().notNull(),
    created_at: text().notNull(),
  },
  (t) => [
    index("idx_revisions_entity_created").on(t.entity_id, t.created_at),
  ]
);

/**
 * Single-row-per-key app settings (AI provider key etc.). Values set here
 * win over the equivalent Worker env vars, which remain as fallbacks.
 */
export const settings = sqliteTable("settings", {
  key: text().primaryKey(),
  value: text().notNull(),
  updated_at: text().notNull(),
});

export const media = sqliteTable("media", {
  id: text().primaryKey(),
  entity_id: text()
    .notNull()
    .references(() => entities.id),
  r2_key: text().notNull(),
  media_type: text().notNull(),
  alt_text: text(),
  created_at: text().notNull(),
});
