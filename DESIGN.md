# Kronicle — Design Document

> Written 2026-06-09. Updated 2026-06-10: renamed to Kronicle, design review fixes (immutable IDs, status column, auth proxy, quick capture, build phases); added Web UI Design (typography + warm editorial theme); added writing-tool features (backlinks, editor spec, backups, AI ground rules, revisions, era validation, server-side slug rename); added AI chat (per-entity tool-calling chat, approval-gated writes); added Mobile UI Design (Material 3 warm theme + bundled OFL fonts); added Cloudflare Access in front of the web app + implementation defaults (monorepo layout, server-side slug generation, partial PUT, list envelope, revision endpoints); built the Phase 1 web app (`web/`) — component layer is Bits UI directly + hand-styled Tailwind rather than shadcn-svelte (decision 27); built per-entity AI chat from Phase 3 — Worker `POST /api/ai/chat` (DeepSeek tool loop, SSE, read tools capped at 8/turn, write tools intercepted as proposals) + web `AiChatPanel` on detail/edit views (diff and change-card proposals with Apply/Discard; in the editor, applied edits merge into the open buffer and ride autosave). Updated 2026-06-11: considered and rejected an app-level login (first-run root user + TOTP QR) — Cloudflare Access stays the sole web gate; added its setup runbook to the Auth section. Editor gains a Write/Peek toggle (Ctrl+E) that swaps the editing surface with rendered Markdown in place — a side-by-side preview pane was rejected for screen cost. Built revision history from Phase 3: `entity_revisions` table, snapshots coalesced to a 10-minute window, list/restore endpoints, History section in the editor sidebar. Added free-form tags (`metadata.tags` + `?tag=` filter + chips in editor/detail/list), per-type content templates (full create form + blank-editor affordance; stubs stay bare), family relationship types (`parent_of`, `sibling_of`, `married_to`), and a vault-health report (`GET /api/diagnostics` + web `/health`: broken wikilinks, orphans, stale stubs — computed at read time like backlinks). Moved the AI provider key into a D1 `settings` table editable from a new web Settings page (`GET/PUT /api/settings/ai`, masked hint only, env secret stays as fallback — decision 31); fixed chat self-applying its own proposals by blocking same-turn `apply_proposal` on both Worker and client (decision 32); documented that the AI provider is any OpenAI-compatible chat-completions endpoint (OpenAI, OpenRouter, Claude compat, Gemini compat, Ollama) configured entirely from Settings — DeepSeek is only the default.
> This is the reference for building the app.
> When building, read this first. When the design changes, update this.

---

## Overview

Kronicle is a personal **storybuilding ideas vault**: capture ideas the moment they strike as stubs, develop them into drafts, then promote them to canon or reject them. Two apps, one backend. A **SvelteKit web app** and a **Flutter Android app** — both talking to the same **Cloudflare Workers API** backed by **D1 (SQLite)**. Both platforms do full read and write. The convenience split is natural (keyboard on desktop, pocket on phone) but neither platform is restricted. AI writing assistance via the same API. Export to portable Markdown from either platform.

```
┌─────────────────────┐     ┌─────────────────────┐
│  SvelteKit (Web)    │     │  Flutter (Android)   │
│  Cloudflare Workers │     │  APK on device       │
└────────┬────────────┘     └────────┬────────────┘
         │  REST API                 │  REST API
         │  (via SvelteKit server    │  (token in app)
         │   routes — token stays    │
         │   server-side)            │
         └───────────┬───────────────┘
                     │
         ┌───────────▼───────────────┐
         │  Cloudflare Workers API   │
         │  /api/entities            │
         │  /api/relationships       │
         │  /api/ai/*                │
         │  /api/export, /api/import │
         └───────────┬───────────────┘
                     │
         ┌───────────▼───────────────┐
         │  Cloudflare D1 (SQLite)   │
         │  entities                 │
         │  relationships            │
         │  media                    │
         └───────────────────────────┘
```

---

## Data Model — Unified Graph on Relational Tables

### Why unified

A location, a character, and a faction all share the same core shape: an id, a name, a type, some prose content, and relationships to other entities. One entity table + one relationship table is simpler than separate tables per type and more flexible — any entity can relate to any other without schema changes. A `parent_id` column enables nesting (chapters under stories, buildings under cities, sub-factions).

### Entity types

| Type | Purpose |
|------|---------|
| `character` | Named individuals with unique abilities |
| `location` | Towns, cities, forests, regions, buildings |
| `faction` | Groups, guilds, covens, families |
| `lore` | Magic systems, history, religions, artifacts, creatures |
| `story` | Narrative arcs — a collection of chapters |
| `chapter` | A single chapter/scene within a story (nested under parent story) |
| `event` | A point on the timeline — character births, battles, discoveries |
| `ability` | A unique power — rooted in a principle, wielded by characters |

### Tables

#### entities

| Column | Type | Purpose |
|--------|------|---------|
| `id` | TEXT PK | Opaque immutable ID (nanoid). Never changes, so renames never break foreign keys |
| `slug` | TEXT UNIQUE | Human-readable handle, e.g. `guli`, `bangsur-town`. Used in URLs and `[[wikilinks]]`. Renameable |
| `type` | TEXT | `character`, `location`, `faction`, `lore`, `story`, `chapter`, `event`, `ability` |
| `parent_id` | TEXT FK → entities.id | For nesting: chapter → story, building → city, sub-faction → faction. Null for top-level |
| `name` | TEXT | Display name |
| `status` | TEXT CHECK | `canon` / `draft` / `rejected` / `stub`. Real column with a CHECK constraint — it's the most-filtered field, so it gets validation and an index, not a JSON blob |
| `summary` | TEXT | Short blurb (1–2 sentences), used in list views and cards |
| `content` | TEXT | Full Markdown prose — backstory, description, story text |
| `metadata` | JSON | Type-specific fields, extra attributes (see below) |
| `created_at` | TEXT | ISO timestamp |
| `updated_at` | TEXT | ISO timestamp |

Indexes: `(type, status)`, `slug`, `parent_id`. Fields inside `metadata` that ever need fast filtering can get a `json_extract` expression index — but at personal scale this is unlikely to matter.

#### relationships

| Column | Type | Purpose |
|--------|------|---------|
| `id` | TEXT PK | UUID |
| `source_id` | TEXT FK → entities.id | The entity declaring the relationship |
| `target_id` | TEXT FK → entities.id | The entity being pointed to |
| `type` | TEXT | Relationship verb (see table below) |
| `label` | TEXT | Human-readable edge label, e.g. "childhood friend" |
| `metadata` | JSON | Extra context, e.g. `{"joined_year": 342, "left_year": 350}` |
| `created_at` | TEXT | ISO timestamp |

Unique index on `(source_id, target_id, type)` — prevents duplicate edges.

**Direction rule:** relationships are single-source. You declare "Guli was born in Bangsur Town" once as `source: guli, target: bangsur-town, type: born_in`. The API returns relationships from both directions when querying.

#### Relationship types

| Type | From → To | Meaning |
|------|-----------|---------|
| `born_in` | character → location | Birthplace |
| `resides_in` | character → location | Current residence |
| `member_of` | character → faction | Faction membership |
| `leader_of` | character → faction | Leads the faction |
| `possesses` | character → ability | Character wields this ability |
| `friend_of` | character → character | Friendship |
| `rival_of` | character → character | Rivalry / enmity |
| `parent_of` | character → character | Parent (reads "child of" from the target side) |
| `sibling_of` | character → character | Siblings |
| `married_to` | character → character | Spouses |
| `related_to` | any → any | Generic connection (catch-all) |
| `appears_in` | character → chapter | Character appears in this chapter |
| `setting_of` | location → chapter | Chapter takes place here |
| `occurs_at` | event → location | Event happened here |
| `involves` | event → character | Character participated in event |
| `depicts` | story/chapter → event | Story depicts this timeline event |
| `causes` | event → event | Causal chain: this event caused that event |
| `based_in` | faction → location | Faction is headquartered here |

#### media

| Column | Type | Purpose |
|--------|------|---------|
| `id` | TEXT PK | UUID |
| `entity_id` | TEXT FK → entities.id | Owning entity |
| `r2_key` | TEXT | Object key in R2. All media lives in R2 — no base64 in the database |
| `media_type` | TEXT | `portrait`, `illustration`, `reference`, `logo` |
| `alt_text` | TEXT | Accessibility / caption |
| `created_at` | TEXT | ISO timestamp |

Media files are served through the Worker (`GET /api/media/:id/file` streams from R2) — the bucket stays private, auth applies. Deleting a media row (or its owning entity) also deletes the R2 object, so storage never leaks.

#### entity_revisions (Phase 3)

| Column | Type | Purpose |
|--------|------|---------|
| `id` | TEXT PK | UUID |
| `entity_id` | TEXT FK → entities.id | Entity this snapshot belongs to |
| `content` | TEXT | The Markdown prose as it was before the save |
| `created_at` | TEXT | ISO timestamp |

Snapshot taken on every content-changing save; keep the last 20 per entity. Insurance against bad rewrites, overeager AI accepts, and approved chat edits. Server-only — excluded from sync and export. Saves within 10 minutes of the newest snapshot coalesce into it (the editor autosaves every ~2s pause; without the window, one writing burst would flush all 20 slots) — the first save of a burst captures the pre-burst prose. Restore always snapshots the current content first, window ignored. Mechanical wikilink rewrites from slug renames don't snapshot.

---

### Status system — the core loop

Every entity has a `status` column. This is the heart of the ideas vault:

| Status | Meaning |
|--------|---------|
| `stub` | Placeholder — an idea was captured. Name and maybe a note, no prose yet. Needs triage |
| `draft` | Under development. May or may not become canon |
| `canon` | Confirmed part of the main story. Fully integrated |
| `rejected` | Explicitly not canon. Alternate idea, abandoned concept — kept, not deleted |

The flow: **capture → stub → draft → canon (or rejected)**. The dashboard surfaces stubs waiting for triage.

---

### Metadata conventions (JSON column)

Type-specific fields live in `metadata`. Adding a field is a UI change, not a migration. (`status` is a real column, not metadata.)

**Character:**
```json
{ "gender": "male", "species": "human", "age": 22, "is_npc": false }
```

**Location:**
```json
{ "location_type": "town", "climate": "temperate", "population": 500 }
```

**Faction:**
```json
{ "category": "godlike-coven", "member_count": 4 }
```

**Lore:**
```json
{ "category": "magic-system", "era": "age-of-awakening" }
```

**Story:**
```json
{ "chapter_count": 2, "is_complete": false }
```

**Chapter:**
```json
{ "order": 100 }
```

**Event (timeline):**
```json
{ "date": "Year 342, 3rd Moon, 15th Day", "era": "age-of-conflict", "order_index": 4200, "precision": "exact" }
```

**Ability:**
```json
{ "principle": "destruction", "category": "palm-based", "range": "contact" }
```

**Tags (any type):**
```json
{ "tags": ["villain", "book-2", "fire-motif"] }
```

Free-form labels — the fourth filter axis next to type, status, and era, and the only one that cuts across types ("everything in the book-2 arc" is neither a type nor a status). Trimmed and deduped on write; `GET /api/entities?tag=` filters by exact match via SQLite's `json_each` — no tag table, no management screen. A tag exists because some entity carries it.

**Ordering convention:** `order` (chapters) and `order_index` (events) use sparse integers in steps of 100 (100, 200, 300…). Inserting between two items takes the midpoint — no renumbering.

---

### Linking convention — wikilinks

Mentions in Markdown `content` use `[[slug]]` (optionally `[[slug|display text]]`). Both clients render these as links to the entity detail view. Wikilinks are **render-only** — they do not create relationship rows; explicit relationships stay in the `relationships` table.

**Backlinks ("Mentioned in"):** every entity detail view shows the reverse lookup — all entities whose `content` contains `[[this-slug]]`. Computed at read time (`LIKE '%[[slug%'` — fine at personal scale), no rows stored. This is how forgotten connections resurface.

**Slug renames are server-side and atomic:** when a `PUT /api/entities/:id` changes the `slug`, the Worker rewrites `[[old-slug]]` and `[[old-slug|...]]` across all entities' `content` in the same D1 batch as the rename. Clients never do this themselves — links can't dangle.

---

### NPCs vs. Characters

A town may have 500 residents. Only named, story-relevant characters become entities. The 500 is just `metadata.population`.

---

### Abilities — first-class entities

Every character has a unique ability rooted in a "principle." Abilities are their own entity type (`character → possesses → ability`). They have full Markdown `content` for mechanics, origin, and limitations.

The principle behind all abilities (the "principle of power") is described once in a `lore` entity — not repeated per ability. Each ability's metadata tags which principle it stems from (e.g. `"principle": "destruction"`), linking back to that lore entry conceptually.

---

### Nesting via `parent_id`

- `chapter` entities nest under their parent `story`
- Sub-locations (buildings) nest under parent locations (cities)
- Sub-factions nest under parent factions

Deleting an entity that has children is **blocked** by the API — reassign or delete the children first. Safer than silently cascading prose.

---

### Timeline — chronological precision

Events (`type: event`) are the backbone of the timeline:
- Character births, deaths, major life moments
- Battles, discoveries, faction foundings
- Story chapter occurrences

Relationships: `occurs_at` (location), `involves` (character), `causes` (event → event), `depicts` (story → event).

The Timeline view renders all `canon` events sorted by `metadata.order_index`, grouped by `era`.

**Eras are entities, not free strings.** Each era is a `lore` entity with `metadata.category: "era"`. An event's or lore entry's `metadata.era` must match an existing era entity's slug — the API validates this on write. One typo would otherwise silently split the timeline grouping.

---

## Tech Stack

| Layer | Choice | Rationale |
|-------|--------|-----------|
| **Database** | Cloudflare D1 (SQLite at edge) | Free: 5 GB, 5M reads/day. Single source of truth for both clients |
| **Backend API** | Cloudflare Workers + Hono | Routing, validation, CORS middleware. Cron trigger for weekly backups. Free: 100K requests/day |
| **Web frontend** | SvelteKit → Cloudflare Workers (static assets) | Your existing stack. Cloudflare now steers new projects to Workers rather than Pages. Desktop-first editing experience |
| **Mobile app** | Flutter (Android) | Your existing stack. Phone-first reading experience |
| **ORM (Worker)** | Drizzle | Already used in `bidipeppercrap-api` |
| **HTTP (Flutter)** | `dio` | Interceptors for caching, retry, auth token injection |
| **State (Flutter)** | Riverpod | Modern. Swap if your projects use Provider/BLoC/GetX |
| **UI components (web)** | Bits UI + Tailwind CSS | Accessible headless primitives (dialogs, command palette), styled directly to the warm theme. shadcn-svelte is just copy-pasted Bits UI — going direct skips the indirection (decision 27) |
| **Editor (web)** | CodeMirror 6 | Markdown mode, `[[` wikilink autocomplete, the standard for in-browser editing |
| **Fonts** | Literata / Inter / iA Writer Quattro | All SIL OFL, self-hosted via Fontsource. See Web UI Design |
| **Markdown (Flutter)** | `flutter_markdown` | Renders prose with custom link handling (wikilinks) |
| **AI** | Same Worker (`/api/ai/*`) → DeepSeek | One proxy, both clients share it |
| **Media** | Cloudflare R2 | Free: 10 GB. Portraits, illustrations, logos. Keeps DB lean |
| **Auth** | Static token, never exposed to the browser | Personal tool, not public. See Auth section |

### Why Cloudflare

- D1 + Workers + R2 are all under one free tier umbrella
- You already deploy to Cloudflare (`bidipeppercrap-api` has `wrangler.json`)
- Zero cold starts, global edge, generous limits for a solo tool

---

## API Design

The Worker serves a REST API. Both clients consume the same endpoints.

### Entities

```
GET    /api/entities?type=character&status=canon&tag=villain&search=guli&limit=50&offset=0
GET    /api/entities/:id                    → entity + relationships + media
POST   /api/entities                        → create (quick capture: just { name } → stub)
PUT    /api/entities/:id                    → update
DELETE /api/entities/:id                    → removes relationships, media rows, and R2 objects.
                                              409 if the entity has children (parent_id) — reassign or delete them first
```

`:id` accepts either the opaque id or the slug.

### Relationships

```
GET    /api/entities/:id/relationships      → all relationships for this entity (both directions)
GET    /api/entities/:id/backlinks          → entities whose content mentions [[this-slug]]
POST   /api/relationships                   → { source_id, target_id, type, label, metadata }
DELETE /api/relationships/:id
```

### Media

```
GET    /api/entities/:id/media
GET    /api/media/:id/file                  → streams the object from R2 (bucket stays private)
POST   /api/media                           → multipart upload → R2
DELETE /api/media/:id                       → deletes row + R2 object
```

### Revisions (Phase 3)

```
GET    /api/entities/:id/revisions          → last 20 content snapshots, newest first
POST   /api/entities/:id/revisions/:revId/restore
                                            → restores through the normal save path,
                                              so the current content is snapshotted first
```

### AI

```
POST   /api/ai/polish                       → { content, notes, entity_type, metadata }
POST   /api/ai/expand                       → { summary, entity_type, metadata }
POST   /api/ai/suggest-relationships        → { entity_id } → candidate targets + relationship types
POST   /api/ai/chat                         → { entity_id?, messages } → SSE: text + change proposals
GET    /api/settings/ai                     → provider config: masked key hint + source (settings/env), url, model
PUT    /api/settings/ai                     → save key/url/model from the web Settings page; empty string
                                              clears a field back to the Worker env fallback
```

The provider is **any OpenAI-compatible chat-completions endpoint** — DeepSeek is only the default. The Worker appends `/chat/completions` to the configured API URL, so most providers need their version prefix in the URL: `https://api.openai.com/v1`, `https://openrouter.ai/api/v1`, `https://api.anthropic.com/v1` (Anthropic's OpenAI-compat layer; streaming + tool calling supported), `https://generativelanguage.googleapis.com/v1beta/openai`, or a local `http://localhost:11434/v1` (Ollama). DeepSeek's bare `https://api.deepseek.com` works because it serves the route at root. Switching provider is a Settings change, not a code change.

**Ground rules:**

1. **Context injection** — every AI endpoint fetches the entity's relationships and the summaries of linked entities and includes them in the prompt. DeepSeek polishes and expands with canon awareness, not generically.
2. **AI never writes without explicit approval** — endpoints return suggestions and proposals, never database writes. Clients render them side-by-side, as diffs, or as change cards, and the writer explicitly applies or discards each one. Applied changes go through the normal REST save path (which also snapshots a revision). The AI itself has no write path to D1.
3. Long generations may stream via SSE — implementation choice, not a contract. The chat endpoint always streams.

#### AI Chat

A conversational layer over the same proxy: discuss an entity with the AI, and when you ask it to make a change, it proposes one — it never makes one.

**Stateless and ephemeral.** The client holds the conversation and sends the full message history every turn; closing the panel ends the conversation. No chat tables in D1 — the durable artifacts are the entities themselves (and their revisions), not the chatter that produced them.

**Server-side tool loop.** The Worker injects the entity's context (same as the other AI endpoints), then runs DeepSeek with function calling:

- **Read tools** the Worker executes freely, feeding results back to the model (capped at 8 calls per turn — bounds latency and DeepSeek spend):

| Tool | Maps to |
|------|---------|
| `get_entity(id_or_slug)` | `GET /api/entities/:id` |
| `search_entities(q, type?)` | `GET /api/search` |
| `list_entities(type?, status?)` | `GET /api/entities` |

- **Write tools** are never executed. The Worker intercepts the call, emits it to the client as a **proposal**, and feeds the model a synthetic result (`"proposed, pending approval"`) so it can keep narrating and propose several changes in one reply:

| Tool | Proposal renders as | Apply calls |
|------|---------------------|-------------|
| `update_entity(id, fields)` | Diff against current content/summary/metadata | `PUT /api/entities/:id` |
| `create_entity(type, name, …)` | Change card. Always created as `draft` — the AI doesn't get to declare canon | `POST /api/entities` |
| `add_relationship(source, target, type, label)` | Change card | `POST /api/relationships` |
| `remove_relationship(id)` | Change card | `DELETE /api/relationships/:id` |

Deliberately **not** in the tool set: `delete_entity`, media operations, slug or status changes. Deletes are the one operation revisions can't undo; status promotion is a writer's judgment call. Relationship removal is allowed — edges carry no prose and are cheap to re-add.

**Proposal object:**

```json
{
  "id": "p_8f2k",
  "tool": "update_entity",
  "summary": "Rewrite Guli's backstory to reference the Bangsur fire",
  "args": { "id": "abc123", "content": "…full replacement Markdown…" }
}
```

`args` is the exact body for the corresponding REST call — Apply is a dumb dispatch through the normal save path (revision snapshot, era validation, all existing guards apply). The diff is rendered against the current buffer at Apply time, so an edit that landed mid-conversation is visible before committing.

**SSE events:** `text` (assistant prose deltas), `reading` (read-tool activity, for a small "checking [[mira]]…" indicator), `proposal` (one complete proposal object), `done`.

**History convention:** the wire format is plain `{role, content}` messages. The client flattens proposals and their outcomes into the stored assistant turn — `[Proposed p_8f2k: update Guli's content — applied]` / `…discarded]` — so the model knows on the next turn what landed and what didn't, without the Worker remembering anything.

**"Apply it" in chat:** one extra write-adjacent tool, `apply_proposal(id)`. Also never executed server-side — but when the client receives it, it applies the referenced *pending* proposal immediately, because the approval just came from the writer's own message. The button and the phrase are the same path; the model is only relaying consent. Revisions are the safety net if it ever relays wrong. **Same-turn guard:** consent must predate the proposal — a model that creates a proposal and calls `apply_proposal` on it in the same turn is relaying consent the writer never gave (they haven't seen the card yet). The Worker refuses the call with an error result instead of emitting the relay event, and the client independently ignores relays that reference a proposal born in the still-streaming turn. Without this, the writer sees only "applied" prose and never an interactive card.

**Scope phasing:** with `entity_id`, the chat is anchored to one entity (Phase 3, in the editor/detail panel). Without it, the system prompt carries a vault index (names, slugs, types, statuses) and the model navigates by read tools — vault-wide chat, Phase 4.

### Timeline, Search, Portability

```
GET    /api/timeline?era=age-of-conflict&status=canon
GET    /api/search?q=guli&type=character
GET    /api/diagnostics                     → vault health: broken [[wikilinks]], orphaned
                                              entities, stubs past the 14-day triage window.
                                              Computed at read time, nothing stored
GET    /api/export                          → zip of Markdown files + kronicle.json
POST   /api/import                          → zip upload, restores into D1 + R2 (the round-trip half of export)
```

Search is `LIKE '%q%'` over name/summary/content for v1 — fine at personal scale. Move to D1's FTS5 if it ever feels slow.

### Auth

All API requests include `Authorization: Bearer <static-token>`. The Worker validates it. No user accounts.

**The token must never reach the browser.** The SvelteKit app calls the Worker exclusively from its server routes (`+page.server.ts` / `+server.ts`), where the token lives in an environment variable. Shipping it in client-side JS on a public URL would hand out full write access plus the DeepSeek proxy (your API credits). The Flutter APK does embed the token — accepted risk for a personal device.

**The web app itself sits behind Cloudflare Access** (Zero Trust free tier, email allowlist). The token-proxy keeps the secret out of the browser, but on its own it would attach that token for *any* visitor to the public URL — Access keeps strangers out of the proxy. Zero application code; configured on the SvelteKit Worker's route when the web app deploys. An in-app login (root user + TOTP) was considered and rejected: it would duplicate what Access provides for free, and localhost dev needs no gate.

**Access setup runbook** (one time, at web deploy):

1. Cloudflare dashboard → Zero Trust → Access → Applications → "Add an application" (type: self-hosted).
2. Application domain: the SvelteKit Worker's URL (`kronicle.<account>.workers.dev` or the custom domain).
3. Policy: Allow → Include → Emails → the owner's email.
4. Session duration: 30 days.
5. Login method: One-time PIN (email code) — enabled by default, no identity provider setup needed.
6. Verify: open the URL in a private window → Cloudflare lock screen → email PIN → app loads. A second visit skips the lock screen until the session expires.

---

## App Screens

### Web (SvelteKit)

| Route | Purpose |
|-------|---------|
| `/` | Dashboard — **quick capture box** (name + optional note → stub), stubs awaiting triage, recent entities, quick stats |
| `/entities` | List with type tabs, status filter, search, sort |
| `/entities/[slug]` | Detail — metadata sidebar, rendered Markdown with wikilinks, media gallery, relationships, children, mentioned-in (backlinks), AI chat panel |
| `/entities/[slug]/edit` | Editor — metadata form, Markdown editor, AI buttons, relationship picker, AI chat panel |
| `/entities/new?type=character` | Create (full form) — content pre-filled from the type's heading template (stubs stay bare) |
| `/timeline` | Chronological feed grouped by era |
| `/graph` | Force-directed relationship graph |
| `/search` | Full-text across all entities |
| `/health` | Vault health — broken wikilinks, orphans, stale stubs; the dashboard links here when the report is non-empty |
| `/export` | Download zip / upload zip to import |
| `/chat` | Vault-wide AI chat (Phase 4) — converse across the whole vault, proposals link to their entities |

### Mobile (Flutter)

| Screen | Purpose |
|--------|---------|
| **Home** | Dashboard — **quick capture** (one tap: name + note → stub), stubs to triage, recent, stats |
| **Entity List** | Type tabs, status filter, search |
| **Entity Detail** | Full read: metadata cards, Markdown with wikilinks, media, relationships, children, mentioned-in (backlinks), AI chat sheet |
| **Entity Editor** | Form + Markdown field + AI buttons + relationship picker + AI chat sheet |
| **Timeline** | Vertical feed grouped by era, tap to detail |
| **Graph** | Interactive graph, pinch-zoom, tap to navigate |
| **Search** | Full-text grouped by type |
| **Export** | Generate → share sheet |
| **Chat** | Vault-wide AI chat (Phase 4) |

Quick capture is the core loop of an ideas vault: getting an idea in must be one step, not a form with a type picker. Type can default to `lore` and be corrected at triage.

On web, a global **⌘K command palette** is available from every route: type a name to jump to any entity, or capture a new idea inline (name + note → `stub`) without leaving the page.

---

## Web UI Design

Kronicle is a reading and writing tool — long-form prose is the main content, so typography *is* the UI.

### Typography

Three font roles, all SIL OFL, self-hosted via [Fontsource](https://fontsource.org) npm packages (no Google Fonts requests):

| Role | Font | Why |
|------|------|-----|
| Prose (rendered Markdown) | **Literata** (variable, optical sizes) | Designed for long-form reading on screens (commissioned for Google Play Books). Warm, bookish |
| UI chrome (nav, forms, cards, buttons, metadata) | **Inter** (variable) | Workhorse sans, superb at small sizes |
| Editor + code/slugs | **iA Writer Quattro** | Writing-tuned near-monospace from iA Writer — made for distraction-free drafting. JetBrains Mono as fallback for true-mono contexts |

Writing happens in Quattro, reading happens in Literata — the "manuscript → book" transition is part of the appeal.

### Design language — warm editorial ("digital grimoire")

| Theme | Palette |
|-------|---------|
| Light ("paper") | Cream/ivory background, near-black warm ink text, muted amber accent |
| Dark ("candlelit study") | Deep warm gray (never pure black), soft off-white text, amber accents |

Status colors, used consistently in badges, list rows, and the dashboard: `stub` amber, `draft` blue-gray, `canon` green-ink, `rejected` muted red.

### Reading layout rules

- Prose measure ~68ch, line-height ~1.7
- Literata optical sizing: display cuts for headings, text cuts for body
- Chrome recedes in detail view: collapsible sidebar, no borders or cards around prose — the page should feel like a book page, not an admin panel

### Component layer

**Bits UI** (the headless layer shadcn-svelte wraps) + **Tailwind CSS**, styled to the warm palette via CSS variables. Provides the dialogs and the ⌘K command palette (quick capture + jump-to-entity) without building accessibility from scratch. The entity picker (relationships, parent) is a small hand-rolled async combobox — server-driven search didn't fit the static-list combobox primitive.

### Editor

The most-used surface in the app:

- **CodeMirror 6** with Markdown mode, set in iA Writer Quattro
- Typing `[[` opens entity autocomplete (searches names and slugs, inserts `[[slug]]`) — without this, wikilinks would mean memorizing slugs
- **Autosave**: debounced PUT after ~2s idle, plus a localStorage backup of the unsaved buffer. Losing prose is this app's worst possible failure; it must be impossible
- **Write/Peek toggle** (toolbar button or Ctrl+E): swaps the editing surface in place with rendered Markdown (`.prose-book`, same renderer as the detail view) — no side-by-side pane, which would cramp the screen next to the metadata sidebar and chat panel. The editor stays mounted while hidden so undo history survives the toggle
- **Content templates**: a blank page offers the type's heading skeleton (character: Appearance / Personality / Backstory / Abilities & Principle; ability: Mechanics / Origin / Limitations; …) — one click inserts it into the buffer. The full create form pre-fills the same skeleton; quick-capture stubs stay bare, the headings arrive at promotion time. Hardcoded per-type constants in the client, not user-editable template entities
- **Tags** are edited as chips in the sidebar (Enter or comma to add) and stored in `metadata.tags`, riding the same autosave as everything else
- The Flutter editor stays a plain text field with a wikilink-insert button — CodeMirror is web-only

### AI chat panel

- Collapsible right sidebar on detail and edit views — consistent with "chrome recedes"; closed by default
- Proposals render inline in the transcript: unified diff blocks for content edits, change cards for structural ops (create entity, add/remove relationship), each with Apply / Discard
- Applied cards lock with a status badge; discarded cards dim
- Mobile: a bottom sheet instead of a sidebar; v1 shows a full-replace preview rather than an inline diff

### Mobile UI Design (Flutter)

Same identity as web, native idiom: **Material 3, re-themed to the warm editorial palette**. Material 3 is Flutter's built-in component set — bottom sheets (AI chat), FAB (quick capture), navigation bar, search bar all come for free, with no extra design-system dependency. Cupertino or a custom design system would be the wrong bar for an Android-only personal tool.

- Theme via `ColorScheme.fromSeed` with a muted-amber seed, surfaces overridden to match the web palette: cream/ivory light ("paper"), deep warm gray dark ("candlelit study" — never pure black)
- **Dynamic color (Material You) is disabled** — the grimoire identity is fixed and shared with web; wallpaper-derived schemes would break it and the status-color semantics
- Status colors identical to web: `stub` amber, `draft` blue-gray, `canon` green-ink, `rejected` muted red

The same three fonts, **bundled as APK assets** via `pubspec.yaml` (not the `google_fonts` package — iA Writer Quattro isn't on Google Fonts, and bundling mirrors the web's self-hosted/no-Google-requests decision; sources: Google Fonts repos for Literata and Inter, [iA-Fonts on GitHub](https://github.com/iaolo/iA-Fonts) for Quattro):

| Role | Font | Flutter usage |
|------|------|---------------|
| Prose (rendered Markdown) | **Literata** | `flutter_markdown` stylesheet body |
| UI chrome | **Inter** | `ThemeData.textTheme` default |
| Editor text field | **iA Writer Quattro** | editor `TextField` style |

---

## Build Phases

| Phase | Scope |
|-------|-------|
| **1** | Worker API (entities, relationships, media, auth) + SvelteKit web with full CRUD, quick capture, detail/editor, list, search. This alone is a usable vault |
| **2** | Flutter app: quick capture, read/browse, basic editing. Timeline on both |
| **3** | Graph views, export/import + weekly cron backups, AI endpoints + buttons, per-entity AI chat (web), revision history, media gallery polish |
| **4** | Vault-wide AI chat (web `/chat` + Flutter chat screen), per-entity chat on Flutter |

"Neither platform is restricted" is the end state, not the v1 bar — building two full clients simultaneously doubles the work before anything is usable.

---

## Offline & Caching Strategy

Both apps are online-first. D1 is the single source of truth. Network latency to Cloudflare's edge is 20-80ms from Indonesia on mobile — near-instant for list and detail views.

### Response caching (Flutter)

The Flutter app caches API responses to eliminate repeated network calls:

| Cache scope | TTL | Rationale |
|-------------|-----|-----------|
| Entity detail + relationships + media | 5-10 min | Prose changes rarely. Most reads hit cache. |
| Entity list (filtered) | 1-2 min | Stale lists are acceptable for short windows |
| Timeline | 2 min | Events are stable |
| Search results | no cache | Always fresh |

Cache is in-memory (a Map keyed by request URL). Cleared on app restart. Any write clears the whole cache — at personal scale, simpler beats clever invalidation, and you never see stale data you just wrote.

**Result:** the app feels local. Scrolling through your characters, jumping between entities, re-reading lore — all cache hits. The network only wakes when you edit or when a cache entry expires.

### True offline (no signal)

- Export from web → download zip → import into Flutter app
- Flutter app renders entities from the imported zip
- This is a v1.5 feature — not in the initial build

### Full sync (future)

- Flutter app gets a local SQLite mirror
- Periodic sync via `GET /api/entities?updated_since=<timestamp>`
- Conflict resolution: server wins (web edits are authoritative)
- Note: deletes are invisible to `updated_since` — when this gets built, add soft-delete tombstones (a `deleted_at` column) rather than hard deletes

---

## Export (Portability)

Available from both web (download) and Flutter (share sheet).

**Format:** zip containing one Markdown file per entity (YAML frontmatter + prose) + `kronicle.json` manifest + all media files. Lossless round-trip — `POST /api/import` restores the zip into a fresh D1 + R2 instance.

### Automated backups

This database holds years of creative work behind one static token — it gets defense in depth:

1. **D1 Time Travel** — built-in 30-day point-in-time restore, zero setup. First line of defense.
2. **Weekly cron backup** — a Worker cron trigger runs the same export logic and writes the zip to R2 at `backups/kronicle-YYYY-MM-DD.zip`, keeping the last 8. Survives anything short of losing the Cloudflare account; restorable anywhere via `POST /api/import`.

---

## Resolved Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Principles are a `lore` entity, not separate entities | Described once. Abilities tag which principle they stem from |
| 2 | Media in Cloudflare R2 only, served through the Worker | Keeps the database lean, bucket stays private. R2 free tier: 10 GB |
| 3 | Hono for the Worker API framework | Routing, validation, CORS out of the box |
| 4 | `dio` for Flutter HTTP | Interceptors for caching, retry, auth token injection |
| 5 | Shared D1 backend with response caching | Real-time sync between platforms, cache makes it feel local |
| 6 | Opaque immutable IDs + renameable slugs | Renames never break foreign keys |
| 7 | `status` is a real column, not metadata | Most-filtered field gets a CHECK constraint and an index |
| 8 | Wikilinks `[[slug]]` are render-only | Explicit relationships stay in the relationships table |
| 9 | Web token stays in SvelteKit server routes | Never shipped to the browser |
| 10 | Typography: Literata (prose) + Inter (UI) + iA Writer Quattro (editor) | Reading-first app — the fonts are the UI. All OFL, self-hosted via Fontsource |
| 11 | Warm editorial design language on shadcn-svelte + Tailwind | Writerly "digital grimoire" feel with accessible prebuilt components underneath |
| 12 | Backlinks computed at read time via `LIKE` | No stored rows, no index to maintain. Personal scale makes this free |
| 13 | CodeMirror 6 editor with `[[` autocomplete and autosave | The editor is the most-used surface; losing prose must be impossible |
| 14 | Weekly cron backup to R2 (last 8 kept) on top of D1 Time Travel | Years of creative work deserve defense in depth |
| 15 | AI is context-aware and never writes without explicit approval | Prompts include linked entities' summaries; output is apply/discard suggestions and proposals only |
| 16 | Eras are `lore` entities, validated on write | Free strings + one typo would silently split the timeline |
| 17 | Slug renames rewrite wikilinks server-side, atomically | Links can never dangle; clients never do find-and-replace |
| 18 | AI chat is stateless — client holds history, full transcript sent per turn, no chat tables in D1 | Conversations are scaffolding; entities and revisions are the durable record |
| 19 | Tool-call split: read tools execute server-side, write tools return as proposals applied via normal REST | AI never touches D1 directly; every applied change inherits revisions and validation for free |
| 20 | AI tool set excludes deletes, slug, and status changes; `create_entity` lands as `draft` | Deletes are the one op revisions can't undo; canon is a human call |
| 21 | Flutter: Material 3 themed to the warm palette, dynamic color off; same three OFL fonts bundled as APK assets | Native component set, one shared identity across clients; Quattro isn't on Google Fonts, so assets it is |
| 22 | Cloudflare Access in front of the SvelteKit web app | The server-route proxy alone would attach the token for any visitor — full write access on a public URL. Access (free tier, email allowlist) closes that with zero code |
| 23 | Monorepo: `worker/` + `web/` (later `app/` for Flutter) | Two deployments, one design doc, one history |
| 24 | Slugs are generated server-side: slugify the name (lowercase alphanumeric + hyphens), suffix `-2`, `-3`… on collision | Quick capture stays `{ name }` only; clients never invent slugs |
| 25 | `PUT /api/entities/:id` is a partial update | Clients edit one field at a time; `metadata` is replaced wholly when provided |
| 26 | Paginated list endpoints return `{ items, total, limit, offset }` | Dashboard stats need `total` without a second endpoint |
| 27 | Web components: Bits UI used directly, no shadcn-svelte layer | shadcn-svelte is copy-pasted Bits UI wrappers; every component gets restyled to the warm theme anyway, so the wrapper layer added indirection without value. Async pickers are hand-rolled |
| 28 | Tags live in `metadata.tags`, filtered via `json_each` exact match | The one cross-type axis; no tag table, no tag screen — a tag exists because an entity carries it. JSON array + table-valued function keeps it at zero migrations |
| 29 | Content templates are hardcoded per-type client constants | Headings prompt what to write and keep sheets consistent. Quick capture stays one step — stubs never get a skeleton; the editor offers it when the page is blank |
| 30 | Vault health (broken links, orphans, stale stubs) is computed at read time | Same philosophy as backlinks: one pass over the vault per request, nothing stored, nothing to invalidate. Renames can't dangle links, but typing `[[a-typo]]` can — this is where those surface |
| 31 | AI provider config (key, API URL, model) lives in a D1 `settings` table, editable from the web Settings page; Worker env vars are fallbacks. Any OpenAI-compatible endpoint works — DeepSeek is just the default | Rotating a key or switching provider shouldn't require the Cloudflare console. The key never leaves the Worker — responses carry only a masked hint (`…1234`). D1 plaintext is acceptable: the same database holds the vault, behind the same single token |
| 32 | `apply_proposal` may not target a proposal created in the same turn (enforced Worker-side and client-side) | Consent must predate the proposal — the writer can't approve a card they haven't seen. Otherwise the model self-applies and chat shows only "applied" prose, no interactive card |

## Remaining (decide during implementation)

| # | Question | Options |
|---|----------|---------|
| 1 | Graph rendering on mobile | `CustomPainter` widget vs. WebView + D3. Prototype both, pick what performs |
| 2 | Multi-device sync | Not in v1. Export/import covers the gap. Revisit when phone ↔ desktop real-time is needed |
| 3 | Vault-wide chat specifics | Vault-index size vs. token budget; whether chat eventually subsumes the polish/expand buttons. Decide in Phase 4 with real usage |
