# Kronicle — Design Document

> Written 2026-06-09. Updated 2026-06-10: renamed to Kronicle, design review fixes (immutable IDs, status column, auth proxy, quick capture, build phases); added Web UI Design (typography + warm editorial theme).
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

**Ordering convention:** `order` (chapters) and `order_index` (events) use sparse integers in steps of 100 (100, 200, 300…). Inserting between two items takes the midpoint — no renumbering.

---

### Linking convention — wikilinks

Mentions in Markdown `content` use `[[slug]]` (optionally `[[slug|display text]]`). Both clients render these as links to the entity detail view. Wikilinks are **render-only** — they do not create relationship rows; explicit relationships stay in the `relationships` table. Because links use the `slug` (not the immutable `id`), renaming a slug requires a find-and-replace across content — the editor should offer this when a slug changes.

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

---

## Tech Stack

| Layer | Choice | Rationale |
|-------|--------|-----------|
| **Database** | Cloudflare D1 (SQLite at edge) | Free: 5 GB, 5M reads/day. Single source of truth for both clients |
| **Backend API** | Cloudflare Workers + Hono | Routing, validation, CORS middleware. Free: 100K requests/day |
| **Web frontend** | SvelteKit → Cloudflare Workers (static assets) | Your existing stack. Cloudflare now steers new projects to Workers rather than Pages. Desktop-first editing experience |
| **Mobile app** | Flutter (Android) | Your existing stack. Phone-first reading experience |
| **ORM (Worker)** | Drizzle | Already used in `bidipeppercrap-api` |
| **HTTP (Flutter)** | `dio` | Interceptors for caching, retry, auth token injection |
| **State (Flutter)** | Riverpod | Modern. Swap if your projects use Provider/BLoC/GetX |
| **UI components (web)** | shadcn-svelte + Tailwind CSS | Accessible prebuilt components (dialogs, command palette, comboboxes), restyled to the warm theme |
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
GET    /api/entities?type=character&status=canon&search=guli&limit=50&offset=0
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

### AI

```
POST   /api/ai/polish                       → { content, notes, entity_type, metadata }
POST   /api/ai/expand                       → { summary, entity_type, metadata }
POST   /api/ai/suggest-relationships        → { entity_id } → candidate targets + relationship types
```

### Timeline, Search, Portability

```
GET    /api/timeline?era=age-of-conflict&status=canon
GET    /api/search?q=guli&type=character
GET    /api/export                          → zip of Markdown files + kronicle.json
POST   /api/import                          → zip upload, restores into D1 + R2 (the round-trip half of export)
```

Search is `LIKE '%q%'` over name/summary/content for v1 — fine at personal scale. Move to D1's FTS5 if it ever feels slow.

### Auth

All API requests include `Authorization: Bearer <static-token>`. The Worker validates it. No user accounts.

**The token must never reach the browser.** The SvelteKit app calls the Worker exclusively from its server routes (`+page.server.ts` / `+server.ts`), where the token lives in an environment variable. Shipping it in client-side JS on a public URL would hand out full write access plus the DeepSeek proxy (your API credits). The Flutter APK does embed the token — accepted risk for a personal device.

---

## App Screens

### Web (SvelteKit)

| Route | Purpose |
|-------|---------|
| `/` | Dashboard — **quick capture box** (name + optional note → stub), stubs awaiting triage, recent entities, quick stats |
| `/entities` | List with type tabs, status filter, search, sort |
| `/entities/[slug]` | Detail — metadata sidebar, rendered Markdown with wikilinks, media gallery, relationships, children |
| `/entities/[slug]/edit` | Editor — metadata form, Markdown editor, AI buttons, relationship picker |
| `/entities/new?type=character` | Create (full form) |
| `/timeline` | Chronological feed grouped by era |
| `/graph` | Force-directed relationship graph |
| `/search` | Full-text across all entities |
| `/export` | Download zip / upload zip to import |

### Mobile (Flutter)

| Screen | Purpose |
|--------|---------|
| **Home** | Dashboard — **quick capture** (one tap: name + note → stub), stubs to triage, recent, stats |
| **Entity List** | Type tabs, status filter, search |
| **Entity Detail** | Full read: metadata cards, Markdown with wikilinks, media, relationships, children |
| **Entity Editor** | Form + Markdown field + AI buttons + relationship picker |
| **Timeline** | Vertical feed grouped by era, tap to detail |
| **Graph** | Interactive graph, pinch-zoom, tap to navigate |
| **Search** | Full-text grouped by type |
| **Export** | Generate → share sheet |

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

**shadcn-svelte** (Bits UI underneath) + **Tailwind CSS**, restyled to the warm palette via CSS variables. Provides the dialogs, comboboxes (relationship picker), and the ⌘K command palette (quick capture + jump-to-entity) without building accessibility from scratch.

---

## Build Phases

| Phase | Scope |
|-------|-------|
| **1** | Worker API (entities, relationships, media, auth) + SvelteKit web with full CRUD, quick capture, detail/editor, list, search. This alone is a usable vault |
| **2** | Flutter app: quick capture, read/browse, basic editing. Timeline on both |
| **3** | Graph views, export/import, AI endpoints + buttons, media gallery polish |

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

## Remaining (decide during implementation)

| # | Question | Options |
|---|----------|---------|
| 1 | Graph rendering on mobile | `CustomPainter` widget vs. WebView + D3. Prototype both, pick what performs |
| 2 | Multi-device sync | Not in v1. Export/import covers the gap. Revisit when phone ↔ desktop real-time is needed |
