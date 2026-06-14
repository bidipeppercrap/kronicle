import { and, desc, eq, inArray, like, or } from "drizzle-orm";
import { drizzle } from "drizzle-orm/d1";
import type { DrizzleD1Database } from "drizzle-orm/d1";
import { Hono } from "hono";
import { HTTPException } from "hono/http-exception";
import { streamSSE } from "hono/streaming";
import type { SSEStreamingApi } from "hono/streaming";
import { nanoid } from "nanoid";
import { z } from "zod";
import {
  ENTITY_TYPES,
  RELATIONSHIP_TYPES,
  STATUSES,
  entities,
  relationships,
} from "../db/schema";
import type { ChatMessage, ToolDefinition } from "../lib/deepseek";
import { streamCompletion } from "../lib/deepseek";
import { resolveEntity, requireEntity, type EntityRow } from "../lib/resolve";
import { getAiConfig } from "../lib/settings";
import { serialize } from "../lib/util";
import { parseJson } from "../lib/validate";
import type { Bindings } from "../types";

const app = new Hono<{ Bindings: Bindings }>();

/** Read tools per turn — bounds latency and DeepSeek spend (DESIGN.md). */
const READ_BUDGET = 8;
/** Model→tool round-trips per turn — a hard stop against runaway loops. */
const MAX_ROUNDS = 10;

const chatSchema = z.object({
  entity_id: z.string().optional(),
  messages: z
    .array(
      z.object({
        role: z.enum(["user", "assistant"]),
        content: z.string(),
      })
    )
    .min(1),
});

// ——— Tool definitions (OpenAI function-calling format) ———

const typeEnum = [...ENTITY_TYPES];
const statusEnum = [...STATUSES];

const TOOLS: ToolDefinition[] = [
  {
    type: "function",
    function: {
      name: "get_entity",
      description:
        "Fetch one entity by id or slug: full prose content, metadata, and its relationships.",
      parameters: {
        type: "object",
        properties: { id_or_slug: { type: "string" } },
        required: ["id_or_slug"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "search_entities",
      description:
        "Search the vault by text across entity names, summaries, and content.",
      parameters: {
        type: "object",
        properties: {
          q: { type: "string" },
          type: { type: "string", enum: typeEnum },
        },
        required: ["q"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "list_entities",
      description: "List entities, optionally filtered by type and status.",
      parameters: {
        type: "object",
        properties: {
          type: { type: "string", enum: typeEnum },
          status: { type: "string", enum: statusEnum },
        },
      },
    },
  },
  {
    type: "function",
    function: {
      name: "update_entity",
      description:
        "Propose changes to an entity's name, summary, content, or metadata. The writer sees a diff and applies or discards it — nothing is changed until they approve. Slug and status cannot be changed.",
      parameters: {
        type: "object",
        properties: {
          id_or_slug: { type: "string" },
          change_summary: {
            type: "string",
            description: "One line describing the change, shown on the proposal card.",
          },
          name: { type: "string" },
          summary: { type: "string" },
          content: {
            type: "string",
            description: "Full replacement Markdown — not a fragment.",
          },
          metadata: { type: "object" },
        },
        required: ["id_or_slug", "change_summary"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "create_entity",
      description:
        "Propose a new entity. It is always created as a draft — the writer promotes to canon. Requires their approval before anything is created.",
      parameters: {
        type: "object",
        properties: {
          change_summary: { type: "string" },
          type: { type: "string", enum: typeEnum },
          name: { type: "string" },
          summary: { type: "string" },
          content: { type: "string" },
          metadata: { type: "object" },
          parent_id: {
            type: "string",
            description: "id or slug of the parent entity, for nesting",
          },
        },
        required: ["change_summary", "type", "name"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "add_relationship",
      description:
        "Propose a relationship between two entities. Requires writer approval.",
      parameters: {
        type: "object",
        properties: {
          change_summary: { type: "string" },
          source: { type: "string", description: "id or slug of the source entity" },
          target: { type: "string", description: "id or slug of the target entity" },
          type: { type: "string", enum: [...RELATIONSHIP_TYPES] },
          label: { type: "string" },
        },
        required: ["change_summary", "source", "target", "type"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "remove_relationship",
      description:
        "Propose removing a relationship by its id. Requires writer approval.",
      parameters: {
        type: "object",
        properties: {
          change_summary: { type: "string" },
          relationship_id: { type: "string" },
        },
        required: ["change_summary", "relationship_id"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "apply_proposal",
      description:
        "Apply a pending proposal from this conversation, only when the writer's latest message explicitly asks for it (e.g. \"apply it\"). The id is the proposal id, like p_abc123.",
      parameters: {
        type: "object",
        properties: { proposal_id: { type: "string" } },
        required: ["proposal_id"],
      },
    },
  },
];

// ——— Tool argument schemas ———

const metadataSchema = z.record(z.unknown());
const getEntityArgs = z.object({ id_or_slug: z.string() });
const searchArgs = z.object({
  q: z.string().min(1),
  type: z.enum(ENTITY_TYPES).optional(),
});
const listArgs = z.object({
  type: z.enum(ENTITY_TYPES).optional(),
  status: z.enum(STATUSES).optional(),
});
const updateArgs = z
  .object({
    id_or_slug: z.string(),
    change_summary: z.string().min(1),
    name: z.string().min(1).optional(),
    summary: z.string().optional(),
    content: z.string().optional(),
    metadata: metadataSchema.optional(),
  })
  .refine(
    (a) =>
      a.name !== undefined ||
      a.summary !== undefined ||
      a.content !== undefined ||
      a.metadata !== undefined,
    { message: "at least one of name/summary/content/metadata is required" }
  );
const createArgs = z.object({
  change_summary: z.string().min(1),
  type: z.enum(ENTITY_TYPES),
  name: z.string().min(1),
  summary: z.string().optional(),
  content: z.string().optional(),
  metadata: metadataSchema.optional(),
  parent_id: z.string().optional(),
});
const addRelArgs = z.object({
  change_summary: z.string().min(1),
  source: z.string(),
  target: z.string(),
  type: z.enum(RELATIONSHIP_TYPES),
  label: z.string().optional(),
});
const removeRelArgs = z.object({
  change_summary: z.string().min(1),
  relationship_id: z.string(),
});
const applyArgs = z.object({ proposal_id: z.string() });

// ——— Context injection ———

/** Compact reference shape fed to the model for lists and search results. */
function brief(e: EntityRow) {
  return {
    id: e.id,
    slug: e.slug,
    name: e.name,
    type: e.type,
    status: e.status,
    summary: e.summary,
  };
}

async function relationshipLines(
  db: DrizzleD1Database,
  entity: EntityRow
): Promise<string[]> {
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
  if (!rels.length) return [];

  const counterpartIds = [
    ...new Set(
      rels.map((r) => (r.source_id === entity.id ? r.target_id : r.source_id))
    ),
  ];
  const rows = await db
    .select()
    .from(entities)
    .where(inArray(entities.id, counterpartIds))
    .all();
  const refs = new Map(rows.map((r) => [r.id, r]));

  return rels.map((r) => {
    const outgoing = r.source_id === entity.id;
    const other = refs.get(outgoing ? r.target_id : r.source_id);
    const who = other
      ? `${other.name} [[${other.slug}]] (${other.type}, ${other.status})`
      : "?";
    const verb = outgoing ? `this —${r.type}→ ${who}` : `${who} —${r.type}→ this`;
    const label = r.label ? ` "${r.label}"` : "";
    const summary = other?.summary ? ` — ${other.summary}` : "";
    return `- [${r.id}] ${verb}${label}${summary}`;
  });
}

/**
 * Compact one-line-per-entity index, always injected so the model can navigate
 * the whole vault by slug/id even when the writer is anchored to one entity or
 * looking at a non-entity view (DESIGN.md, route-aware chat). Capped at 200 by
 * recency — personal scale keeps this well inside the token budget.
 */
async function vaultIndex(db: DrizzleD1Database): Promise<string> {
  const rows = await db
    .select()
    .from(entities)
    .orderBy(desc(entities.updated_at))
    .limit(200)
    .all();
  if (!rows.length) return "(the vault is empty)";
  return rows
    .map((e) => `- ${e.name} [[${e.slug}]] (${e.type}, ${e.status})`)
    .join("\n");
}

/**
 * One route-aware system prompt. With an `entity` the writer is anchored to it
 * (rich block) — without one they're browsing the vault. Either way the vault
 * index rides along so navigation is always one read tool away (DESIGN.md).
 */
async function buildSystemPrompt(
  db: DrizzleD1Database,
  entity: EntityRow | null
): Promise<string> {
  const rules = `You are the writing assistant inside Kronicle, a personal storybuilding vault.

Rules:
- Read the vault freely with get_entity, search_entities, and list_entities.
- You cannot change anything yourself. To propose a change you MUST call update_entity, create_entity, add_relationship, or remove_relationship — a tool call is the ONLY thing that renders the interactive proposal card with Apply/Discard buttons. Describing the edit in prose, writing a "[Proposed …]" line, or claiming a change is pending or approved renders NO card: the writer is left with a message and nothing to act on. So never narrate a change in place of calling the tool, and never claim one is already made. Make the tool call; a short sentence like "Proposed it — apply when you're ready" is all the prose the card needs.
- The "[Proposed p_xxx: … — applied/discarded/pending]" lines in the transcript are records the app writes after you call a tool. They are never something you type yourself — they only tell you what landed on earlier turns. Only call apply_proposal when the writer's latest message explicitly asks to apply a pending one, and never for a proposal you created this same turn — the writer hasn't seen it yet.
- The "[Context: …]" lines in the transcript are records the app writes when the writer navigates to a different entity or view. They tell you what the writer is currently looking at; treat the most recent one as the live focus, and never type one yourself.
- If a write tool returns an error, the proposal was NOT created. Say so and ask how to proceed; never paste the rewritten content into chat as a substitute.
- update_entity content must be the full replacement Markdown, not a fragment.
- Prose references other entities as [[slug]] wikilinks (or [[slug|display text]]). Keep existing wikilinks intact unless the change is about them.
- New entities always land as drafts; promoting to canon is the writer's call.
- Vault metadata conventions, so you propose fields that fit instead of inventing your own (metadata is freeform JSON; these are the shapes the app and timeline already expect):
  - event: "order_index" (integer — the timeline sorts on this, so it is the field that places an event in time; leave gaps like 1000, 2000 so events can be inserted between later), "date" (free-form display string, e.g. "Year 500 AC"), "precision" ("exact" or "approximate"), and an optional "era".
  - "era" (on an event or lore entry) is OPTIONAL and, when set, must be the slug of an existing lore entity whose metadata.category is "era" — never invent an era slug; if no era entity fits, omit the field. The timeline is chronological first (order_index); eras are only optional grouping bands, so an event needs no era to appear on it.
  - tags live in metadata.tags (array of strings); location uses location_type/climate/population; ability uses principle/category/range; creature (flora & fauna) uses category ("flora" or "fauna")/habitat/diet/danger.
- Match the writer's tone and the vault's voice; be concrete and brief in chat.`;

  const index = await vaultIndex(db);

  if (!entity) {
    return `${rules}

The writer is browsing the whole vault — no single entity is in focus. Open anything by slug or id with get_entity, or find things with search_entities and list_entities.

Vault index (name [[slug]] (type, status)):
${index}`;
  }

  const relLines = await relationshipLines(db, entity);
  return `${rules}

The writer is currently looking at this entity:

name: ${entity.name}
slug: ${entity.slug}
id: ${entity.id}
type: ${entity.type}
status: ${entity.status}
summary: ${entity.summary || "(none)"}
metadata: ${entity.metadata}

relationships:
${relLines.length ? relLines.join("\n") : "(none)"}

content (Markdown):
${entity.content || "(blank — nothing written yet)"}

The rest of the vault, for reference (name [[slug]] (type, status)):
${index}`;
}

// ——— Tool execution ———

interface TurnState {
  readCalls: number;
  /** Proposal ids created this turn — apply_proposal may not target these. */
  createdIds: Set<string>;
}

async function runReadTool(
  db: DrizzleD1Database,
  name: string,
  args: unknown
): Promise<string> {
  if (name === "get_entity") {
    const a = getEntityArgs.parse(args);
    const entity = await resolveEntity(db, a.id_or_slug);
    if (!entity) return `No entity found for "${a.id_or_slug}".`;
    const relLines = await relationshipLines(db, entity);
    return JSON.stringify({
      ...serialize(entity),
      relationships: relLines,
    });
  }
  if (name === "search_entities") {
    const a = searchArgs.parse(args);
    const pattern = `%${a.q}%`;
    const conds = [
      or(
        like(entities.name, pattern),
        like(entities.summary, pattern),
        like(entities.content, pattern)
      ),
    ];
    if (a.type) conds.push(eq(entities.type, a.type));
    const rows = await db
      .select()
      .from(entities)
      .where(and(...conds))
      .limit(20)
      .all();
    return JSON.stringify(rows.map(brief));
  }
  // list_entities
  const a = listArgs.parse(args);
  const conds = [];
  if (a.type) conds.push(eq(entities.type, a.type));
  if (a.status) conds.push(eq(entities.status, a.status));
  const rows = await db
    .select()
    .from(entities)
    .where(conds.length ? and(...conds) : undefined)
    .orderBy(desc(entities.updated_at))
    .limit(20)
    .all();
  return JSON.stringify(rows.map(brief));
}

/**
 * Build the proposal for a write tool. `args` on the wire is the exact body
 * for the REST call the client makes on Apply (DESIGN.md) — every existing
 * guard (era validation, revision snapshot) applies there, not here.
 */
async function buildProposal(
  db: DrizzleD1Database,
  name: string,
  rawArgs: unknown
): Promise<{ summary: string; args: Record<string, unknown> }> {
  if (name === "update_entity") {
    const a = updateArgs.parse(rawArgs);
    const target = await resolveEntity(db, a.id_or_slug);
    if (!target) throw new Error(`No entity found for "${a.id_or_slug}"`);
    const { id_or_slug, change_summary, ...fields } = a;
    return { summary: change_summary, args: { id: target.id, ...fields } };
  }
  if (name === "create_entity") {
    const a = createArgs.parse(rawArgs);
    const { change_summary, parent_id, ...fields } = a;
    const args: Record<string, unknown> = { ...fields, status: "draft" };
    if (parent_id) {
      const parent = await resolveEntity(db, parent_id);
      if (!parent) throw new Error(`No parent entity found for "${parent_id}"`);
      args.parent_id = parent.id;
    }
    return { summary: change_summary, args };
  }
  if (name === "add_relationship") {
    const a = addRelArgs.parse(rawArgs);
    const source = await resolveEntity(db, a.source);
    if (!source) throw new Error(`No entity found for "${a.source}"`);
    const target = await resolveEntity(db, a.target);
    if (!target) throw new Error(`No entity found for "${a.target}"`);
    return {
      summary: a.change_summary,
      args: {
        source_id: source.id,
        target_id: target.id,
        type: a.type,
        label: a.label ?? null,
      },
    };
  }
  // remove_relationship
  const a = removeRelArgs.parse(rawArgs);
  return { summary: a.change_summary, args: { id: a.relationship_id } };
}

const READ_TOOLS = new Set(["get_entity", "search_entities", "list_entities"]);
const WRITE_TOOLS = new Set([
  "update_entity",
  "create_entity",
  "add_relationship",
  "remove_relationship",
]);

async function runTool(
  db: DrizzleD1Database,
  stream: SSEStreamingApi,
  state: TurnState,
  name: string,
  rawArguments: string
): Promise<string> {
  let args: unknown;
  try {
    args = rawArguments.trim() ? JSON.parse(rawArguments) : {};
  } catch {
    return `Error: arguments for ${name} were not valid JSON.`;
  }

  try {
    if (READ_TOOLS.has(name)) {
      if (state.readCalls >= READ_BUDGET) {
        return `Read budget exhausted (${READ_BUDGET} calls this turn). Answer with what you already have.`;
      }
      state.readCalls++;
      const detail =
        typeof args === "object" && args !== null
          ? Object.values(args as Record<string, unknown>).join(" ")
          : "";
      await stream.writeSSE({
        event: "reading",
        data: JSON.stringify({ tool: name, detail }),
      });
      return await runReadTool(db, name, args);
    }

    if (WRITE_TOOLS.has(name)) {
      const { summary, args: restArgs } = await buildProposal(db, name, args);
      const proposal = { id: `p_${nanoid(8)}`, tool: name, summary, args: restArgs };
      state.createdIds.add(proposal.id);
      await stream.writeSSE({
        event: "proposal",
        data: JSON.stringify(proposal),
      });
      return `Proposal ${proposal.id} created (${name}): ${summary}. Status: pending — the writer has not applied it. Do not describe it as done.`;
    }

    if (name === "apply_proposal") {
      const a = applyArgs.parse(args);
      // Consent must predate the proposal: applying one created this same
      // turn would mean the writer never saw it (DESIGN.md, "Apply it").
      if (state.createdIds.has(a.proposal_id)) {
        return `Error: proposal ${a.proposal_id} was created this turn — the writer has not seen it yet. It stays pending until they click Apply or ask for it in a later message. Tell them it is awaiting their approval.`;
      }
      await stream.writeSSE({
        event: "proposal",
        data: JSON.stringify({
          id: `p_${nanoid(8)}`,
          tool: "apply_proposal",
          summary: `Apply ${a.proposal_id}`,
          args: { id: a.proposal_id },
        }),
      });
      return `Relayed — the client is applying ${a.proposal_id} now on the writer's instruction.`;
    }

    return `Error: unknown tool "${name}".`;
  } catch (err) {
    if (err instanceof z.ZodError) {
      const detail = err.issues.map((i) => i.message).join("; ");
      return `Error: invalid arguments for ${name}: ${detail}`;
    }
    return `Error: ${err instanceof Error ? err.message : "tool failed"}`;
  }
}

// ——— Route ———

app.post("/ai/chat", async (c) => {
  const db = drizzle(c.env.DB);
  const ai = await getAiConfig(db, c.env);
  const apiKey = ai.apiKey;
  if (!apiKey) {
    throw new HTTPException(500, {
      message: "No AI API key configured — add one in Settings",
    });
  }
  const body = await parseJson(c, chatSchema);
  // entity_id is the current route's entity (auto-set by the client) and may be
  // absent on non-entity views — the chat is route-aware, not entity-bound.
  const entity = body.entity_id ? await requireEntity(db, body.entity_id) : null;
  const system = await buildSystemPrompt(db, entity);
  const messages: ChatMessage[] = [
    { role: "system", content: system },
    ...body.messages,
  ];

  return streamSSE(c, async (stream) => {
    const state: TurnState = { readCalls: 0, createdIds: new Set() };
    try {
      for (let round = 0; round < MAX_ROUNDS; round++) {
        const result = await streamCompletion({
          apiKey,
          baseUrl: ai.baseUrl,
          model: ai.model,
          messages,
          tools: TOOLS,
          onText: (delta) =>
            stream.writeSSE({ event: "text", data: JSON.stringify({ delta }) }),
        });
        if (!result.toolCalls.length) break;

        messages.push({
          role: "assistant",
          content: result.content || null,
          tool_calls: result.toolCalls,
        });
        for (const call of result.toolCalls) {
          const outcome = await runTool(
            db,
            stream,
            state,
            call.function.name,
            call.function.arguments
          );
          messages.push({
            role: "tool",
            content: outcome,
            tool_call_id: call.id,
          });
        }
      }
      await stream.writeSSE({ event: "done", data: "{}" });
    } catch (err) {
      console.error(err);
      await stream.writeSSE({
        event: "error",
        data: JSON.stringify({
          message: err instanceof Error ? err.message : "AI chat failed",
        }),
      });
    }
  });
});

export default app;
